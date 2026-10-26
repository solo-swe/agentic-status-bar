# State file schema, version 1

This is the public contract between the writer of session state (the hook) and every reader (the SwiftBar plugin
today, the `asb` CLI and the app later, other tools). The shell hook (`hooks/state-hook.sh`) and the Swift hook
(`asb hook`) must both write exactly this; every reader must accept exactly this.

Changes that readers could misread need a new version number. Adding an optional field does not.

## Where

| File | Path today | Path after the rename |
| --- | --- | --- |
| Session state | `~/.claude/swiftbar-claudecode-minimal/<sessionId>.json` | `~/.claude/agentic-status-bar/<sessionId>.json` |
| Mutes | `<state dir>/mutes` | the same, in the new state dir |
| Refresh stamp | `<state dir>/.last-poke` | the same |
| Plugin log | `<state dir>/plugin.log` | the same |
| Config | `~/.config/swiftbar-claudecode-minimal/config` | `~/.config/agentic-status-bar/config` |

The state dir can be moved with the config key `state_dir` (or an environment override, for tests).

## Session state file

One JSON object per Claude Code session, on one line, named after the session ID. Session IDs that don't match
`[A-Za-z0-9_-]+` are never written (they become file names).

| Field | Type | Required | Written by | Meaning |
| --- | --- | --- | --- | --- |
| `v` | integer | yes | every write | Schema version, `1` |
| `sessionId` | string | yes | every write | Claude Code's session ID; equals the file name |
| `state` | `"busy"`, `"waiting"`, `"idle"` | yes¹ | every event | What the hooks last saw |
| `reason` | `"permission"`, `"question"` | when waiting | Notification | Why the session waits |
| `message` | string | no | Notification | Claude Code's notification text |
| `updatedAt` | integer, epoch ms | yes | every write | When this file was last written |
| `stateSince` | integer, epoch ms | yes | every write | When `state` last changed (unchanged when a write keeps the state) |
| `pid` | integer or `null` | no | SessionStart, backfill | PID of the `claude` process; `null` means none was found (don't look again) |
| `procStart` | string | with `pid` | SessionStart, backfill | That process's start time as `ps -o lstart=` prints it in local time, e.g. `"Mon Oct 19 09:12:03 2026"`. Compare after collapsing runs of spaces. |
| `cwd` | string | no | SessionStart, backfill | The session's working directory (the project) |
| `kind` | `"interactive"`, `"headless"`, `"ide"`, `"desktop"` | no | SessionStart, backfill | Missing means interactive |
| `termBundleId` | string | no | SessionStart, backfill | Bundle ID of the terminal app (`__CFBundleIdentifier`) |
| `herdrPane` | string | no | SessionStart, backfill | herdr pane ID (`HERDR_PANE_ID`) |
| `transcriptPath` | string | no | SessionStart, backfill | Path of the session's JSONL transcript |
| `lastTool` | string | no | PreToolUse | Name of the last tool started |
| `promptPreview` | string | no | UserPromptSubmit | The first 80 characters of the last typed prompt, whitespace collapsed. Absent when `store_prompt_preview=0`. |
| `promptAt` | integer, epoch ms | no | UserPromptSubmit | When the user last sent a prompt (not a background-task result). Lifts a mute on the project. |
| `subagents` | object | no | SubagentStart, SubagentStop | Running subagents: `{ "<agent_id>": { "type": string, "since": epoch ms } }`; removed when empty |

¹ A file created by an early `SubagentStart` gets `state: "busy"`.

Example:

```json
{"v":1,"sessionId":"3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90","state":"waiting","reason":"permission","message":"Claude needs your permission to use Bash","updatedAt":1792891073038,"stateSince":1792891073038,"pid":48213,"procStart":"Mon Oct 19 09:12:03 2026","cwd":"/Users/alex/code/api-gateway","kind":"interactive","termBundleId":"com.mitchellh.ghostty","herdrPane":"w2:p1","transcriptPath":"/Users/alex/.claude/projects/api-gateway/3f9c2a7e.jsonl","lastTool":"Bash","promptPreview":"Add rate limiting to the auth routes","promptAt":1792891060000,"subagents":{"a1":{"type":"Explore","since":1792891070000}}}
```

### Events

| Hook event | Effect |
| --- | --- |
| `SessionStart` | Records the session details (see Metadata). `state = "idle"` and drops `reason`, `message`, `subagents`, except when `source` is `"compact"` and the file already has a state. Deletes other state files with the same `pid`. |
| `UserPromptSubmit` | `state = "busy"`, drops `reason` and `message`. Sets `promptPreview` and `promptAt` unless the prompt starts with `<task-notification>` (a background-task result). With `store_prompt_preview=0`, drops `promptPreview`. |
| `PreToolUse` | `state = "busy"`, drops `reason` and `message`, sets `lastTool`. |
| `PostToolUse` | `state = "busy"`, drops `reason` and `message`. |
| `Notification` | `permission_prompt` → `waiting`, `reason` `"question"` if `lastTool` is `AskUserQuestion`, else `"permission"`, and `message`. `elicitation_dialog` → `waiting`, `"question"`, `message`. `idle_prompt` → `idle`, drops `reason` and `message`. Without `notification_type`, a message containing "needs your permission" counts as `permission_prompt` and "waiting for your input" as `idle_prompt`. Other types change nothing. |
| `Stop` | `state = "idle"`, drops `reason` and `message`. |
| `SubagentStart` | Adds `subagents[agent_id] = {type (or "agent" when empty), since: now}`; sets `state = "busy"` only if the file had none. Ignored without `agent_id`. |
| `SubagentStop` | Removes `subagents[agent_id]`, and `subagents` when it becomes empty. Ignored without `agent_id` or with an empty `agent_type` (one such stop follows every `Stop`). |
| `SessionEnd` | Deletes the file. |

### Metadata

Recorded at `SessionStart`, and backfilled once by the first other event of a session whose file lacks `pid` or `cwd`
(it was running before the hooks were installed). A backfill never changes `state` or `stateSince`.

- `pid`: walk up from the hook's parent process, at most 6 levels, to the first process named `claude`, or `node`
  with `claude` in its arguments. `null` if none.
- `kind`: `CLAUDE_CODE_ENTRYPOINT` `sdk-*` → headless; containing `vscode`, `jetbrains` or `ide` → ide; containing
  `desktop` → desktop; otherwise a ` -p ` or ` --print ` argument on the claude process → headless; otherwise
  interactive.
- `cwd` and `transcriptPath` from the payload; `herdrPane` and `termBundleId` from the environment, omitted when
  empty.

## Writer rules

1. **Lock:** take the per-session lock `<file>.lock` (a directory, created with `mkdir`), retrying 50 times every
   10 ms; give up silently if it can't be taken. Release it after writing.
2. **Newer wins:** hooks run asynchronously and can finish out of order. Each event notes its start time (epoch ms)
   when the hook starts. If the file's `updatedAt` is later than that, the event is dropped.
3. **Read-modify-write:** a missing or corrupt file counts as `{}`. Apply the event, then set `v`, `sessionId`,
   `updatedAt = now`, and `stateSince = now` when `state` changed or `stateSince` is missing.
4. **Atomic:** write to `<file>.tmp.<pid>`, then rename over the file.
5. **Silent:** the hook never prints, never fails Claude Code, and always exits 0, also on bad input.
6. **Refresh:** when a write happened and `instant_refresh=1`, ask the front end to refresh, at most once per 500 ms
   (stamp in `.last-poke`, epoch ms).

## Reader rules

1. Read only `*.json` files in the state dir; skip `*.tmp.*` files and `*.lock` directories.
2. Ignore unknown fields.
3. A file that doesn't parse, isn't an object, or has `v` missing, not a number, below 1 or above the highest version
   the reader knows is **invalid**: count it and show the warning state; don't delete it.
4. Treat every field but `v` and `sessionId` as optional.
5. Readers may delete a file whose `pid` no longer runs or runs with a different `procStart` (check C1). They must
   not otherwise modify state files.

## Mutes file

`<state dir>/mutes`, one JSON object keyed by project directory (`cwd`), written atomically by the front end:

```json
{"/Users/alex/code/api-gateway":{"until":1792900000000,"at":1792896400000,"today":false}}
```

| Field | Meaning |
| --- | --- |
| `until` | Epoch ms when the mute ends (one hour after `at`, or the next local midnight) |
| `at` | Epoch ms when it was set |
| `today` | `true` for "mute for today" |

A mute is active while `until` is in the future and no session in that `cwd` has a `promptAt` later than `at`.
Expired entries are dropped on the next write. A corrupt file counts as no mutes.

## Config file

Plain `key=value` lines; `#` starts a comment line; unknown keys are ignored; a value is accepted only if valid,
otherwise the default stays. Writers change one line and keep the others.

| Key | Default | Valid values |
| --- | --- | --- |
| `show_interactive`, `show_headless`, `show_subagents`, `show_ide` | `1` | `0` or `1` |
| `stale_minutes` | `30` | a whole number (`0` = off) |
| `use_registry` | `1` | `0` or `1` |
| `instant_refresh` | `1` | `0` or `1` |
| `store_prompt_preview` | `1` | `0` or `1` |
| `state_dir` | the state dir above | a path; `~` is expanded |
| `theme` | `default` | `default`, `monochrome`, `high_contrast` (unknown → default) |
| `icon` | empty | an SF Symbol name (busy and empty icon; older shortcut) |
| `icon_<state>` | empty | an SF Symbol name |
| `color_<state>` | empty | `#RRGGBB`, or `#RRGGBB,#RRGGBB` (light, dark) |

`<state>` is one of `waiting`, `idle`, `uncertain`, `busy`, `subagents`, `muted`, `none`, `warning`. All values
other than colors may contain only letters, digits and `_ . / ~ -`.
