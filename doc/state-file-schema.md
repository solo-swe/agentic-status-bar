# State file schema, version 1

This is the public contract between the writer of session state (the hook, `asb hook`) and every reader (the app,
the `asb` CLI, other tools). The hook must write exactly this; every reader must accept exactly this.

Changes that readers could misread need a new version number. Adding an optional field does not.

## Where

| File | Path |
| --- | --- |
| Session state | `~/.claude/agentic-status-bar/<sessionId>.json` |
| Mutes | `<state dir>/mutes` |
| Log | `<state dir>/plugin.log` (the name is from the SwiftBar era) |
| Config | `~/.config/agentic-status-bar/config` |

The state dir can be moved with the config key `state_dir` (or an environment override, for tests). Before the
rename, the SwiftBar plugin used `~/.claude/swiftbar-claudecode-minimal/` and
`~/.config/swiftbar-claudecode-minimal/config`; `asb install` moves them. A `.last-poke` file left in the state dir by
older hooks is unused.

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
| `eventAt` | integer, epoch ms | yes² | every write | When the hook of the latest event applied started (see Writer rules › Newer wins) |
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
| `subagents` | object | no | SubagentStart, SubagentStop, Stop | Running subagents: `{ "<agent_id>": { "type": string, "since": epoch ms, "background": true } }`; `background` marks one Claude Code's task registry listed as a background task. Removed when empty |

¹ A file created by an early `SubagentStart` gets `state: "busy"`.
² Files written before `eventAt` existed lack it until their next write.

Example:

```json
{"v":1,"sessionId":"3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90","state":"waiting","reason":"permission","message":"Claude needs your permission to use Bash","updatedAt":1792891073038,"eventAt":1792891073031,"stateSince":1792891073038,"pid":48213,"procStart":"Mon Oct 19 09:12:03 2026","cwd":"/Users/alex/code/api-gateway","kind":"interactive","termBundleId":"com.mitchellh.ghostty","herdrPane":"w2:p1","transcriptPath":"/Users/alex/.claude/projects/api-gateway/3f9c2a7e.jsonl","lastTool":"Bash","promptPreview":"Add rate limiting to the auth routes","promptAt":1792891060000,"subagents":{"a1":{"type":"Explore","since":1792891070000}}}
```

### Events

| Hook event | Effect |
| --- | --- |
| `SessionStart` | Records the session details (see Metadata). `state = "idle"` and drops `reason`, `message`, `subagents`, except when `source` is `"compact"` and the file already has a state. Deletes other state files with the same `pid`. |
| `UserPromptSubmit` | `state = "busy"`, drops `reason` and `message`. Sets `promptPreview` and `promptAt` unless the prompt starts with `<task-notification>` (a background-task result). With `store_prompt_preview=0`, drops `promptPreview`. |
| `PreToolUse` | `state = "busy"`, drops `reason` and `message`, sets `lastTool`. |
| `PostToolUse` | `state = "busy"`, drops `reason` and `message`. |
| `Notification` | `permission_prompt` → `waiting`, `reason` `"question"` if `lastTool` is `AskUserQuestion`, else `"permission"`, and `message`. `elicitation_dialog` → `waiting`, `"question"`, `message`. `idle_prompt` → `idle`, drops `reason` and `message`. Without `notification_type`, a message containing "needs your permission" counts as `permission_prompt` and "waiting for your input" as `idle_prompt`. Other types change nothing. |
| `Stop` | `state = "idle"`, drops `reason` and `message`. With `background_tasks` (see Background subagents), `subagents` becomes exactly the running background subagents it lists. |
| `SubagentStart` | Adds `subagents[agent_id] = {type (or "agent" when empty), since: now}` unless the agent is already listed (a resumed subagent keeps its entry); sets `state = "busy"` only if the file had none. Ignored without `agent_id`. |
| `SubagentStop` | Without `background_tasks`: removes `subagents[agent_id]`. With it: keeps the agent (marked `background`) while the registry still lists it, else removes it; also removes other `background` agents the registry no longer lists and adds listed ones that are missing. `subagents` is dropped when empty. Ignored without `agent_id` or with an empty `agent_type` (one such stop follows every `Stop`). |
| `SessionEnd` | Deletes the file. |

### Background subagents

A background subagent fires `SubagentStop` each time it pauses to wait on its own background work (a shell
command, a monitor) and `SubagentStart` when it resumes, so start and stop events alone can't tell "paused" from
"finished". `Stop` and `SubagentStop` payloads carry `background_tasks`, the parent session's in-flight task registry
([hooks reference › Stop input](https://code.claude.com/docs/en/hooks)): an entry with `type: "subagent"`, whose `id`
is the agent ID, is a running background subagent, unless its `status` is a finished one (`completed`, `failed`,
`killed`, `stopped`, `cancelled`, `error`). It is the source of truth for background subagents; it also clears agents
killed with TaskStop, which fire no `SubagentStop`. Foreground subagents are never in it: a `SubagentStop` leaves
them alone, and at `Stop` none can be running. An older `SubagentStop` (see Newer wins) only keeps or removes its own
agent. Payloads without `background_tasks` (older Claude Code, or the registry wasn't reachable) use the plain
add/remove rules.

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
   when the hook starts. If the file's `eventAt` (the start time of the latest event applied) is later than that,
   the event started earlier and is dropped; a file without `eventAt` accepts it. `SubagentStart` and
   `SubagentStop` are the exception: an earlier one still adds or removes its subagent (the map is keyed by agent ID,
   so order doesn't matter) but changes nothing else. Comparing with `updatedAt`, the time of the previous *write*,
   would drop events whose hooks started together, such as parallel subagents or a `Stop` right after a tool.
3. **Read-modify-write:** a missing or corrupt file counts as `{}`. Apply the event, then set `v`, `sessionId`,
   `updatedAt = now`, `eventAt` = the later of its old value and this event's start time, and `stateSince = now`
   when `state` changed or `stateSince` is missing.
4. **Atomic:** write to `<file>.tmp.<pid>`, then rename over the file.
5. **Silent:** the hook never prints, never fails Claude Code, and always exits 0, also on bad input.

Readers learn about writes by watching the state dir (the rename in rule 4 shows up as a change); the hook doesn't
notify anyone.

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
| `instant_refresh` | `1` | `0` or `1`; read but unused (it asked SwiftBar to refresh after each hook event) |
| `store_prompt_preview` | `1` | `0` or `1` |
| `state_dir` | the state dir above | a path; `~` is expanded |
| `theme` | `default` | `default`, `monochrome`, `high_contrast` (unknown → default) |
| `icon` | empty | an SF Symbol name (busy and empty icon; older shortcut) |
| `icon_<state>` | empty | an SF Symbol name |
| `color_<state>` | empty | `#RRGGBB`, or `#RRGGBB,#RRGGBB` (light, dark) |
| `notify_waiting` | `1` | `0` or `1`: the app notifies when a session waits on you (also in muted projects) |
| `notify_idle` | `0` | `0` or `1`: the app notifies when a session goes idle (not in muted projects) |
| `notify_delay_seconds` | `10` | a whole number: how long a session stays waiting or idle before the notification; the app offers 5, 10, 30 and 60 |
| `notify_sound` | `1` | `0` or `1` |
| `debug_hook_log` | `0` | `0` or `1`: `asb hook` appends every payload it receives, with the environment variables it reads and its parent pid, to `<state dir>/hook-payloads.jsonl` (one JSON object per line; nothing is appended once the file reaches 5 MB). For debugging; turn it off and delete the file afterwards |

`<state>` is one of `waiting`, `idle`, `uncertain`, `busy`, `subagents`, `muted`, `none`, `warning`. All values
other than colors may contain only letters, digits and `_ . / ~ -`.
