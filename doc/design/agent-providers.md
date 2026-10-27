# Agent providers: showing other coding agents

Status (2026-10-26): proposal. Nothing here is built. Today the app shows only Claude Code sessions. This document
maps every place the code assumes Claude Code, summarizes what other terminal coding agents offer for status
reporting, and proposes a provider abstraction that adds them without changing what Claude Code users see.

Part 1 is the map of today's code. Part 2 is the research, one section per agent. Part 3 is the proposal: the
abstraction, schema changes, UI, a feasibility table, risks, migration and a task breakdown.

## Part 1: Claude Code assumptions in today's code

The pipeline has four stages, and each one assumes Claude Code somewhere:

1. **Integration:** `asb install` registers `asb hook` for nine Claude Code hook events.
2. **Hook:** `asb hook` reads a Claude Code payload on stdin and writes `<state dir>/<sessionId>.json`.
3. **Engine:** `Engine.reconcile` runs checks C1 to C5 on every state file, with Claude Code's registry, transcript
   format and process names built in.
4. **Front end:** the snapshot, the app's rows, notifications and Settings.

### Generic already

These parts don't care which agent wrote a state file and can stay as they are:

| Part | File | Why it is generic |
| --- | --- | --- |
| Lock, atomic write | `Sources/ASBCore/StateWriter.swift` | Per-file `mkdir` lock and temp-file rename |
| Newer wins, `stamped` | `Sources/ASBCore/HookEvents.swift` (`apply`, `stamped`) | Works on `eventAt` and the hook's start time, not on event names |
| Stored states | `doc/state-file-schema.md` | `busy`, `waiting` (`permission`, `question`), `idle` fit every agent researched below |
| Header priority, ranks, words, durations | `Sources/ASBCore/MenuModel.swift` | Only read `shown` and `reason` |
| Mutes | `Sources/ASBCore/Mutes.swift` | Keyed by `cwd` |
| Themes | `Sources/ASBCore/Themes.swift` | Keyed by display state; nothing per agent |
| C1 liveness | `Sources/ASBCore/Checks.swift` (`liveness`) | Needs only `pid` and `procStart`, whoever recorded them |
| C5 staleness | `Sources/ASBCore/Checks.swift` (`staleness`) | Hook writes, transcript mtime, child process starts: all optional signals |
| Process table | `Sources/ASBCore/Processes.swift`, `ProcessesDarwin.swift` | `ProcessInspector` is a protocol with a libproc implementation |
| Focus | `Sources/ASBCore/Actions.swift` (`focus`) | Uses `herdrPane` and `termBundleId`, both from the environment, not from Claude Code |
| Notification timing | `App/Sources/NotificationRules.swift` (`evaluate`) | Works on `shown` and `since` |

### Claude Code specific

| # | Assumption | Where | Effect for another agent |
| --- | --- | --- | --- |
| A1 | One hook entry point that takes a Claude Code payload on stdin. No argument says who called it. | `Sources/asb/Hook.swift` | Can't tell agents apart; payload shapes differ (Codex `notify` passes JSON as an argument, not on stdin) |
| A2 | Payload field names: `hook_event_name`, `session_id`, `cwd`, `transcript_path`, `source`, `prompt`, `tool_name`, `notification_type`, `message`, `agent_id`, `agent_type`, `background_tasks` | `HookPayload.parse` in `Sources/ASBCore/HookEvents.swift` | Other agents use other names (`thread-id`, `conversation_id`, `sessionId`) |
| A3 | Event names `SessionStart` … `SessionEnd` and their meaning | `HookEvents.apply` | Each agent has its own event set |
| A4 | `Notification` types `permission_prompt`, `elicitation_dialog`, `idle_prompt`, and the English fallbacks "needs your permission" and "waiting for your input" | `HookEvents.apply` | Claude Code wording |
| A5 | A question is a permission prompt for the tool `AskUserQuestion` | `HookEvents.apply` (`lastTool == "AskUserQuestion"`) | Claude Code tool name |
| A6 | `<task-notification>` prompts are background-task results; `source: "compact"` keeps the state | `HookEvents.taskNotificationPrefix`, `apply` | Claude Code behavior |
| A7 | Subagent rules: `SubagentStart`/`SubagentStop` keyed by `agent_id`, the empty-`agent_type` stop after every `Stop`, `background_tasks` as the source of truth | `HookEvents.apply`, `backgroundEntry`; schema › Background subagents | Claude Code's subagent model |
| A8 | The session process is `claude`, or `node` with `claude` in its arguments, at most 6 parents up | `HookMetadata.findClaude` in `Sources/ASBCore/HookMetadata.swift` | No pid, so no C1 or C4, for any other agent |
| A9 | Kind from `CLAUDE_CODE_ENTRYPOINT` and a `-p`/`--print` argument | `HookMetadata.kind` | Other agents have other headless flags (`codex exec`, `gemini -p`, `cursor-agent -p`) |
| A10 | One session per process: `SessionStart` deletes other state files with the same pid | `HookMetadata.staleFiles`, `Sources/asb/Hook.swift` | Would delete another agent's file if pids ever matched; an opencode server can hold several sessions in one process |
| A11 | Hooks live in `~/.claude/settings.json` as `hooks.<Event>[].hooks[] = {type, command, async, timeout}`, tagged with `# agentic-status-bar`; "installed" means one entry per event | `HookSettings` in `Sources/ASBCore/Settings.swift`; `Installer.hooksInstalled` | Other agents use other files (TOML, JSON with other shapes, JS plugins). `async: true` is a Claude Code feature: other agents may run hooks synchronously |
| A12 | The settings path `~/.claude/settings.json` (overridable with `ASB_SETTINGS`) | `Sources/asb/Install.swift`, `App/Sources/HookInstaller.swift` | One file, one agent |
| A13 | The state dir is `~/.claude/agentic-status-bar/` | `Paths.defaultStateDir` in `Sources/ASBCore/Paths.swift` | Lives under Claude Code's folder; works, but reads oddly for other agents |
| A14 | The file name is the session ID, and `sessionId` equals the file name | `Sources/asb/Hook.swift`, `StateFile.parse` fallback, `Actions.field` | IDs from two agents share one namespace |
| A15 | C2: Claude Code's registry `~/.claude/sessions/<pid>.json` (`status`, `statusUpdatedAt`, `waitingFor`, `name`, `nameSource`) | `Sources/ASBCore/Registry.swift`, `Paths.registryDir`, `LiveInputs.gather` | Only Claude Code has one |
| A16 | C3: Claude Code's JSONL transcript: `type: "user"` prompts, `isMeta`, `system`/`turn_duration`, the marker `[Request interrupted by user` | `Sources/ASBCore/Transcript.swift` | Other transcripts look different; the parser finds nothing in them, so C3 does nothing (safe, but no help) |
| A17 | C4 ignores a `caffeinate` child, which Claude Code starts every turn | `Checks.approvedTools` in `Sources/ASBCore/Checks.swift` | Other agents have other long-lived children (MCP servers, language servers, a Node runtime) |
| A18 | "Waiting on subagents" when `lastTool` is `Task` or `Agent` | `Checks.subagents` | Claude Code tool names |
| A19 | Every check runs on every session | `Engine.reconcile` in `Sources/ASBCore/Engine.swift` | There is no way to turn a check off per agent |
| A20 | herdr titles are taken only for `agent == "claude"` and matched by Claude's session ID | `HerdrTitles.parse` in `Sources/ASBCore/MenuModel.swift` | herdr also lists other agents (unverified which), but they are dropped |
| A21 | Kinds `interactive`, `headless`, `ide`, `desktop`; "Headless sessions (claude -p)" | `Sources/ASBCore/Filters.swift`, `App/Sources/SettingsView.swift` | Fine as kinds; the label names Claude |
| A22 | Config key `use_registry` | `Sources/ASBCore/Config.swift`, `Actions.toggleKeys` | Means Claude Code's registry |
| A23 | User-facing text names Claude: "Claude needs your permission to continue.", "Claude has a question for you.", "Claude finished and is waiting for your next prompt." | `NotificationRules.alert` in `App/Sources/NotificationRules.swift` | Wrong agent named |
| A24 | "No Claude Code sessions", "Claude Code hooks", "Find sessions in Claude Code's registry", first-run, Help and About text, CLI abstracts | `App/Sources/StatusItemController.swift`, `PopoverView.swift`, `SettingsView.swift`, `FirstRunView.swift`, `HelpView.swift`, `AboutPanel.swift`; `Sources/asb/ASB.swift`, `Install.swift`, `Hook.swift` | Text only |
| A25 | Snapshot rows have no agent field; the PRD's goal 5 is "use only documented Claude Code APIs" | `doc/snapshot-schema.md`, `Sources/ASBCore/Snapshot.swift`, `doc/PRD.md` | Front ends can't show or filter by agent |

### What the conformance suite pins

`tests/conformance/` has 80 cases (76 single-file, 4 directories). Every one is Claude Code: state files without an
agent field, processes named `claude`, Claude Code registry files and transcript fixtures. The runner compares
snapshots as JSON values, and "absent and `null` are different" (`tests/conformance/README.md` › Comparing). So:

- a new snapshot field must be **left out** for these inputs, or every `expected.json` changes;
- a state file without an agent field must keep meaning Claude Code, with every check on, exactly as today.

The migration plan in Part 3 keeps both, so no existing case changes.

## Part 2: What other agents offer

Researched 2026-10-26 and 2026-10-27 from official docs, release notes and source on the main branch. **Unverified**
marks what we could not confirm in docs or source; such claims need a spike against a real install before code
depends on them. Every agent changes fast: re-check the version column before building.

### Summary

| Agent | Version looked at | Integration point | Payload | Install |
| --- | --- | --- | --- | --- |
| Claude Code | (today) | Hooks in `~/.claude/settings.json` | JSON on stdin | Merge into one JSON file |
| OpenAI Codex CLI | 0.164.0 (2026-10-23), main 2026-10-27 | Hooks in `~/.codex/hooks.json` (Claude Code shape) | JSON on stdin | Merge into one JSON file; the user must trust new hooks once |
| GitHub Copilot CLI | 1.0.104 (2026-10-27) | Hooks in `~/.copilot/hooks/*.json` | JSON on stdin | One file of our own |
| opencode | 1.19.4 (2026-10-22); 2.x line too | JS plugin, in process | Bus events | One file of our own (1.x); 2.x differs |
| Google Gemini CLI | 0.65.0 (2026-10-20), nightly 0.67 | Hooks in settings or in an extension | JSON on stdin | An extension directory |
| Cursor (IDE and `cursor-agent`) | docs read 2026-10-26; CLI 2026.09.26 in forum reports | Hooks in `~/.cursor/hooks.json` | JSON on stdin | Merge into one JSON file |
| Amp | docs read 2026-10-26 (no version stamp) | TS plugin (Bun), no shell hooks | Plugin events and a thread-state observable | One file of our own |
| Aider | 0.86.0 (2025-08-09) | `notifications_command` | None (a fixed command string) | Two keys in `~/.aider.conf.yml`; single slot |

### OpenAI Codex CLI

Sources: [hooks docs](https://learn.chatgpt.com/docs/hooks) (developers.openai.com/codex/hooks redirects there),
[advanced config](https://learn.chatgpt.com/docs/config-file/config-advanced), source in
[openai/codex](https://github.com/openai/codex): `codex-rs/hooks/src/lib.rs`, `engine/command_runner.rs`,
`engine/discovery.rs`, `hooks/schema/generated/*.command.input.schema.json`, `rollout/src/`, `codex-cli/bin/codex.js`.

- **Hooks:** on by default (`[features] hooks = false` turns them off). Same shape as Claude Code: event → matcher
  group → handlers `{type: "command", command, timeout, async}`. Files: `~/.codex/hooks.json` or `[hooks]` in
  `~/.codex/config.toml`; project `.codex/` only in trusted projects. All layers run.
- **Events:** `SessionStart` (source startup, resume, clear, compact, fork), `UserPromptSubmit`, `PreToolUse`,
  `PermissionRequest` ("before an approval prompt"), `PostToolUse`, `Stop`, `Interrupt` (the user interrupts a turn),
  `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `SessionEnd`. `PreModelRequest`/`PostModelRequest`
  are on main, not documented, maybe unreleased.
- **Payload:** `session_id`, `transcript_path` ("not a stable interface"), `cwd`, `hook_event_name`, `model`,
  `permission_mode`, `turn_id`; tool events add `tool_name`, `tool_input`; `agent_id` and `agent_type` inside
  subagents. Subagents share the parent's `session_id`. `SessionStart` also fires for subagents, without `agent_id`.
- **Invocation:** `$SHELL -lc "<command>"` (a login shell: the user's zsh profile runs on every hook, which adds
  latency we don't control), in a new process session, cwd = session cwd. Default timeout 600 s; `SessionEnd` and
  `Interrupt` 1 s, capped at 3 s. Exit 0 with no output changes nothing. Plain stdout on `SessionStart` and
  `UserPromptSubmit` is added to the model's context, so the hook must stay silent (a noisy shell profile leaks too).
- **Trust gate:** every non-managed hook, user level included, is skipped until the user approves it in the `/hooks`
  panel. Approvals are stored in `~/.codex/config.toml` as `[hooks.state."<key>"] trusted_hash = "sha256:…"`, keyed
  by position (`<file>:<event>:<group>:<handler>`). Inserting a group before the user's shifts their keys and
  silently untrusts their hooks, so we must append. Writing `trusted_hash` ourselves is possible but undocumented.
- **Legacy `notify`:** `notify = ["prog", …]` in `config.toml`, JSON appended as the last argument, only
  `agent-turn-complete`. One slot, marked for removal in source. Not worth using.
- **Files:** rollouts at `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<uuid>.jsonl` (cold ones compressed to
  `.jsonl.zst`). Lines `{timestamp, type, payload}`. A turn that ended has a last `event_msg` of `task_complete` or
  `turn_aborted` (reason `interrupted`, …) after its `task_started`. Approvals and questions are not written.
- **Process:** native `codex` (Homebrew, standalone), or `node …/bin/codex.js` that spawns the native `codex` (npm).
  From the hook: hook → shell → `codex`; walk up to `comm == "codex"`.
- **States:** busy: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`. Permission: `PermissionRequest` (it fires
  before the prompt; whether it also fires when the approval policy needs no prompt is **unverified**). Question:
  the model calls the tool `request_user_input` (Plan mode only unless a feature flag is on; root thread only), seen
  as `PreToolUse` with that tool name (**unverified end to end**). Idle: `Stop`, `Interrupt`. End: `SessionEnd`
  (also fires after 30 idle minutes, so it must not be read as "process gone").
- **Subagents:** `SubagentStart`/`SubagentStop` with `agent_id`, `agent_type`.
- **Can't tell:** when a prompt was answered (no event until `PostToolUse`); a denial (probably no `PostToolUse`,
  **unverified**).

### GitHub Copilot CLI

Sources: [hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference),
[hooks tutorial](https://docs.github.com/en/copilot/tutorials/copilot-cli-hooks),
[config dir reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference),
[releases](https://github.com/github/copilot-cli/releases).

- **Hooks:** camelCase events `sessionStart`, `userPromptSubmitted`, `preToolUse`, `permissionRequest`,
  `postToolUse`, `postToolUseFailure`, `agentStop`, `subagentStart`, `subagentStop`, `notification`, `errorOccurred`,
  `preCompact`, `sessionEnd`. A PascalCase alias (`Stop`, `PreToolUse`, …) switches the payload to Claude Code's
  snake_case.
- **Payload:** `sessionId`, `timestamp`, `cwd` on every event; `toolName`, `toolArgs`; `transcriptPath` only on
  `agentStop`, subagent events and `preCompact`. `notification` has `notification_type`: `permission_prompt`,
  `elicitation_dialog`, `agent_idle`, `agent_completed`, `shell_completed`, `shell_detached_completed`. Events inside
  a subagent carry `agentId`, `agentType`, `parentAgentId`.
- **Invocation:** JSON on stdin; `bash`, `command`, or `exec` + `args` (no shell); `timeoutSec` (default 30).
  **`preToolUse` is fail-closed:** any non-zero exit denies the tool. Timeouts fail open.
- **Files:** user hooks in `~/.copilot/hooks/*.json` (`{"version": 1, "hooks": {…}}`) or `hooks` in
  `~/.copilot/settings.json` (strict: one bad entry rejects all inline hooks). Sessions in
  `~/.copilot/session-state/<id>/events.jsonl` (undocumented format). `COPILOT_HOME` moves all of it.
- **Cross-talk:** Copilot also runs repo-level `.claude/settings.json` hooks. Ours are user level, so they aren't
  picked up; reading `~/.claude/settings.json` is not documented (**unverified**).
- **Process:** `copilot`; the npm package ships a native binary per platform. Whether a `node` loader sits in
  between, and the exact `comm`, are **unverified**.
- **States:** busy: `userPromptSubmitted`, tool events. Permission: `notification` `permission_prompt`
  (`permissionRequest` fires even when the call is then auto-approved, so not alone). Question: `notification`
  `elicitation_dialog` (whether the built-in ask tool uses it is **unverified**). Idle: `agentStop`, or `agent_idle`.
- **Subagents:** `subagentStart`/`subagentStop`, but not for the built-in general-purpose agent.
- **Can't tell:** answers to prompts; Esc (no event documented).

### opencode

Sources: [plugins](https://opencode.ai/docs/plugins/), [server](https://opencode.ai/docs/server/),
[troubleshooting](https://opencode.ai/docs/troubleshooting/), [V2 plugins](https://opencode.ai/v2/docs/build/plugins/server),
[V1 migration](https://opencode.ai/v2/docs/build/plugins/migrate-v1); source of
[anomalyco/opencode](https://github.com/anomalyco/opencode) (formerly sst/opencode) at tag v1.19.4:
`packages/plugin/src/index.ts`, `packages/opencode/src/plugin/index.ts`, SDK `types.gen.ts`.

- **Two lines.** 1.19.x is "latest". A 2.x line (tags up to 2.1.4) has a new plugin API, and its installer
  replaces the 1.x binary. 1.x plugins don't load in 2.x; a package can ship both entry points (1.x from 1.18.29).
- **1.x plugin:** a JS/TS file in `~/.config/opencode/plugins/` (or `plugin/`), run in process by Bun. The `event`
  hook gets every bus event, fire and forget. Events: `session.status` (`idle`, `busy`, `retry`), `session.idle`,
  `permission.asked` / `permission.replied` (older SDKs: `permission.updated`), `question.asked` /
  `question.replied` / `question.rejected`, `session.created` / `session.deleted` (with `parentID` for child
  sessions), `session.error`. The typed `permission.ask` hook has been dead code since 1.3.0.
- **Process:** the TUI runs its server in a worker thread of the same `opencode` process, so `process.pid` in the
  plugin is the TUI. Under `opencode serve`, `web` or the desktop app it is a server with no terminal. The TUI opens
  no TCP port by default, so an outside SSE listener can't see ordinary sessions: the plugin is the only channel.
- **2.x:** one shared daemon (`opencode serve --service`, found via `~/.local/state/opencode/service.json`) serves
  every TUI. A plugin's pid is the daemon, so there is no per-terminal pid. Which event names 2.x plugins receive is
  **unverified**.
- **Files:** SQLite at `~/.local/share/opencode/opencode.db`; no transcript file. Config
  `~/.config/opencode/opencode.json(c)`.
- **States (1.x):** busy: `session.status` busy. Permission: `permission.asked` until `permission.replied`. Question:
  `question.asked` until replied or rejected. Idle: `session.idle`. All four are explicit, the best of any agent.
- **Subagents:** child sessions with `parentID`; their events carry the child's ID.
- **Can't tell:** a terminal for server or desktop sessions; `cwd` isn't in events (the plugin's `directory` is).
- **Must:** print nothing (stdout corrupts the TUI).

### Google Gemini CLI

Sources: [hooks](https://geminicli.com/docs/hooks/), [hooks reference](https://geminicli.com/docs/hooks/reference/),
[extensions](https://geminicli.com/docs/extensions/reference/); source of
[google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli): `packages/core/src/hooks/`,
`packages/cli/src/utils/relaunch.ts`, `services/chatRecordingService.ts`.

- **Status:** Google is moving Gemini CLI to the closed-source Antigravity CLI; consumer tiers stopped on 2026-06-18
  ([announcement](https://developers.googleblog.com/en/an-important-update-transitioning-gemini-cli-to-antigravity-cli/)).
  Paid API and enterprise users keep it. Antigravity's hook format was not researched.
- **Hooks:** `BeforeAgent`, `AfterAgent`, `BeforeTool`, `AfterTool`, `BeforeModel`, `AfterModel`,
  `BeforeToolSelection`, `SessionStart`, `SessionEnd`, `Notification`, `PreCompress`. Settings shape like Claude
  Code's, with `name` and a timeout in milliseconds (default 60000).
- **Payload:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`. `Notification` has
  `notification_type: "ToolPermission"` and `details.type`: `edit`, `exec`, `mcp`, `info`, or `ask_user` for a
  question.
- **Invocation:** `bash -c` with JSON on stdin and a sanitized environment (whether `HERDR_PANE_ID` survives is
  **unverified**). Hooks are synchronous and block the agent. **Any stdout or stderr is shown to the user.**
- **Trust:** settings hooks, user level included, are skipped in folders the user hasn't trusted. Extension hooks
  run regardless.
- **Files:** transcripts `~/.gemini/tmp/<project>/chats/session-<time>-<id8>.jsonl` (append-only, with `$set` and
  `$rewindTo` records); approvals and questions aren't recorded.
- **Process:** `node`, relaunched as a child `node` (two processes). Walk up to the first `node` whose arguments
  mention gemini.
- **States:** busy: `BeforeAgent`, tool and model events. Permission: `Notification` with `details.type` other than
  `ask_user`. Question: `details.type == "ask_user"`. Idle: `AfterAgent` (end of turn). Esc fires nothing: a
  cancelled turn stays busy until C5.
- **Subagents:** exist, but payloads carry no subagent ID.

### Cursor (IDE agent and `cursor-agent`)

Sources: [hooks](https://cursor.com/docs/agent/hooks), [third-party hooks](https://cursor.com/docs/reference/third-party-hooks),
forum threads on CLI hooks ([Jan 2026](https://forum.cursor.com/t/cursor-cli-hooks/148511),
[Aug 2026](https://forum.cursor.com/t/cursor-cli-omits-beforesubmitprompt-afteragentresponse-and-stop-hooks-loses-token-usage-and-emits-inconsistent-generation-id-values/169059),
[Sep 2026](https://forum.cursor.com/t/cursor-cli-does-not-run-enterprise-or-team-beforesubmitprompt-hooks/173219)).

- **Hooks:** `~/.cursor/hooks.json`, `{"version": 1, "hooks": {"<event>": [{command, timeout, matcher}]}}`. Events
  include `sessionStart`, `sessionEnd`, `beforeSubmitPrompt`, `preToolUse`, `postToolUse`, `afterShellExecution`,
  `afterMCPExecution`, `afterFileEdit`, `afterAgentResponse`, `stop` (status completed, aborted, error),
  `subagentStart`, `subagentStop`.
- **Payload:** `conversation_id` (the reliable key), `generation_id`, `hook_event_name`, `cursor_version`,
  `workspace_roots[]`, `transcript_path`, `user_email`. Env `CURSOR_VERSION`, `CURSOR_PROJECT_DIR`.
- **Blocking:** permission-type hooks (`preToolUse`, `beforeShellExecution`, `beforeMCPExecution`,
  `subagentStart`, …) block the action if they print invalid JSON, so we should not register on them.
- **CLI:** documented as the same as the IDE, but forum reports show gaps that vary by build: `-p` mode omits
  `beforeSubmitPrompt`, `afterAgentResponse` and `stop`; some Linux builds ran no hooks. Test the installed build.
- **Claude Code import (affects us today):** Cursor runs hooks from `~/.claude/settings.json` too, on by default
  (Settings › Agents › Third-Party Imports), mapping `Stop` → `stop`, `PreToolUse` → `preToolUse` and so on.
  `Notification` is not mapped. So the Cursor IDE probably already calls our `asb hook`. Whether it translates the
  payload to Claude Code's field names is **unverified**. If it sends `hook_event_name: "stop"`, `HookEvents.apply`
  ignores it; if it translates, Cursor sessions show up as Claude Code sessions with no pid.
- **Process:** IDE hooks run under Cursor's helper processes, with no terminal; `cursor-agent` is probably `node`
  with `cursor-agent` in its arguments (**unverified**).
- **States:** busy and idle (`beforeSubmitPrompt`, tool events, `stop`). **No signal for a permission prompt or a
  question.**

### Amp

Sources: [plugins](https://ampcode.com/docs/customize/plugins), [plugin API](https://ampcode.com/docs/plugin-api),
[settings](https://ampcode.com/docs/cli/settings), [streaming JSON](https://ampcode.com/docs/cli/streaming-json).

- **No shell hooks.** `amp.notifications.enabled` only plays a sound.
- **Plugins:** TS/JS run by Bun from `~/.config/amp/plugins/`. Events `session.start`, `agent.start`, `tool.call`
  (blocking), `tool.result`, `agent.end` (status done, error, cancelled). Better: `PluginThread.state` is an
  observable of `idle`, `running`, `awaiting-approval`, `error`. Threads have IDs (`T-…`) and `parentThreadID()`.
- **Limits:** no session end event; no question state; threads may run on remote executors where local file writes
  land elsewhere. Whether one plugin process serves several CLI processes is **unverified**, so the pid isn't
  usable.
- **Process:** `amp` (a Bun-compiled binary in `~/.amp/bin`).

### Aider

Sources: [notifications](https://aider.chat/docs/usage/notifications.html),
[options](https://aider.chat/docs/config/options.html), `aider/io.py` and `aider/coders/base_coder.py` on main
(last commit 2026-05-22).

- **Only `notifications_command`:** a fixed command string, run synchronously through `sh -c` once, at the first
  prompt after the model ran. No arguments or payload. That prompt is either a confirmation ("Run shell command?") or
  the main input, and the command can't tell which. After a confirmation, the later return to the main input fires
  nothing.
- **No session ID;** identity is the process and its git root. Chat history in `.aider.chat.history.md`.
- **Process:** a Python interpreter with `aider` in its arguments; the command is its grandchild (aider → sh →
  command).
- **Install:** `notifications: true` and `notifications_command` in `~/.aider.conf.yml`: a single slot that may
  already hold the user's own notifier.

### Others, briefly

| Agent | What it has | Fit |
| --- | --- | --- |
| Qwen Code | Claude Code-shaped hooks with `PermissionRequest` ("when a permission dialog is shown"), `Notification`, `Stop`, subagent events ([docs](https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/)) | Good; settings path unconfirmed |
| Kimi Code CLI | `[[hooks]]` in `~/.kimi-code/config.toml`: `PermissionRequest`, `Interrupt`, `Stop`, `SubagentStart/Stop`, `Notification` ([docs](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html)); unknown keys break loading | Good; TOML merge needed |
| Crush | `PermissionRequest`, `PermissionResult`, `TurnStart`, `TurnEnd`, `Interrupt`; env `CRUSH_SESSION_ID` ([docs](https://raw.githubusercontent.com/charmbracelet/crush/main/docs/hooks/README.md)) | Good; config file unclear |
| Factory droid | Claude Code-compatible hooks in `~/.factory/settings.json`, including `Notification` ([docs](https://docs.factory.ai/guides/hooks/notifications)) | Likely good; payload unverified |
| Kiro CLI | `~/.kiro/hooks/*.json`, `SessionStart`, `UserPromptSubmit`, tool events, `Stop`; no permission event ([docs](https://kiro.dev/docs/hooks/)) | Busy and idle only |
| Goose | Plugin hooks in `~/.agents/plugins/<name>/hooks/hooks.json`; no permission event ([post](https://goose-docs.ai/blog/2026/05/14/goose-hooks)) | Busy and idle only |
| Cline | File hooks now point to TS SDK plugins ([docs](https://docs.cline.bot/sdk/plugins.md)); CLI support **unverified** | Unclear |

### What the research means for the design

1. **Most agents copied Claude Code's hook model.** Codex, Copilot (PascalCase form), Qwen Code, Kimi, Crush and
   Factory use the same idea, often the same names: session start, prompt, tool, permission, stop, subagents, end.
   One table-driven adapter can cover them; only names and fields differ.
2. **The agent must say who it is.** Payloads carry no agent field, and some agents run other agents' hooks (Cursor
   runs `~/.claude/settings.json`; Copilot runs repo `.claude/settings.json`). The command each integration installs
   must name the agent (`asb hook --agent codex`).
3. **Plugin agents (opencode, Amp) can't run a hook command per event for free,** but they can spawn `asb` for the
   few events that change state. A small, documented input format for that keeps one writer of state files.
4. **"Silent" means more elsewhere.** Gemini shows any output; Codex feeds stdout to the model; Copilot denies a tool
   on a non-zero exit; Cursor blocks on invalid JSON from permission hooks. `asb hook` already prints nothing and
   exits 0; it must also never register where a reply is required.
5. **Hooks are slower and synchronous elsewhere.** Gemini and Aider block the agent; Codex starts a login shell.
   Our 10 ms budget matters more there, not less.
6. **Installs differ:** a hooks directory where we can drop our own file (Copilot, opencode, Amp, Gemini extension)
   is cleaner than merging into a shared file (Codex, Cursor), and much cleaner than a single slot (Aider).
7. **Process liveness (C1) mostly works** with a per-agent pid walk. It fails where the agent is a shared server or
   an IDE (opencode 2.x, Cursor IDE, Amp), and those must rely on end events and C5.

## Part 3: Proposal

### Provider abstraction

A **provider** is everything `ASBCore` knows about one agent. It lives in `Sources/ASBCore/Providers/`, Foundation
only, one file per agent, and is listed in one registry (`Providers.all`), so adding an agent touches no shared code.

```swift
public protocol AgentProvider: Sendable {
    /// Stable ID, written to state files: "claude-code", "codex", "copilot", "opencode", ...
    var id: String { get }
    /// "Claude Code", "Codex"; and the short name for sentences: "Claude", "Codex".
    var displayName: String { get }
    var shortName: String { get }
    /// SF Symbol for the agent badge; nil = text badge only.
    var symbol: String? { get }

    /// Turns one hook call into events. `input` holds stdin, extra arguments and the environment.
    /// `current` is the state file (some agents need it, e.g. Claude Code's lastTool rule).
    func events(_ input: HookInput, current: [String: Any]?) -> [AgentEvent]
    /// Walk from the hook's parent to the agent process; nil = none (C1 and C4 then don't apply).
    func findProcess(from pid: Int32, inspector: any ProcessInspector) -> Int32?
    /// interactive, headless, ide or desktop.
    func kind(environment: [String: String], arguments: String?) -> String

    /// Which checks apply to its sessions.
    var checks: CheckSet { get }               // .liveness, .registry, .turnEnd, .approvedTool, .staleness
    /// C3: how a transcript tail says the turn ended; nil = C3 off.
    func turnEnd(_ tail: Data) -> Transcript.TurnEnd?
    /// C4: child processes that don't count as a tool (Claude Code: caffeinate).
    var ignoredChildren: Set<String> { get }
    /// Tools during which a parent with subagents counts as waiting on them (Claude Code: Task, Agent).
    var subagentTools: Set<String> { get }
    /// herdr's `agent` value for its sessions, for titles; nil = none.
    var herdrName: String? { get }

    /// How it is installed; nil = no automatic install (manual steps in the docs).
    var integration: (any Integration)? { get }
}
```

`AgentEvent` is the small vocabulary every agent maps to:

| Event | State change (same rules as today) |
| --- | --- |
| `started(source)` | idle, record metadata; `resume`/`compact` keep the state |
| `prompt(text, fromUser)` | busy; preview and `promptAt` when `fromUser` |
| `tool(name)` | busy, `lastTool` |
| `toolDone` | busy |
| `waiting(reason, message)` | waiting, `permission` or `question` |
| `turnEnded(interrupted)` | idle |
| `subagentStarted(id, type)`, `subagentStopped(id, running)` | the `subagents` map |
| `ended` | delete the file |

`AgentEvents.apply` is today's `HookEvents.apply` with event names replaced by these cases. The newer-wins rule,
`stamped`, the lock and the atomic write are unchanged and shared. The Claude Code provider maps its payload to
these events, including the `AskUserQuestion`, `<task-notification>`, `compact`, empty-`agent_type` and
`background_tasks` rules (A4 to A7). Its unit tests in `tests/ASBCoreTests/` are the oracle for that refactor.

**A table-driven provider for Claude Code-shaped hooks.** `HookShapedProvider` takes a table (event name → event,
notification type → reason, field names for session ID, cwd, transcript, tool, agent ID). Codex, Copilot (PascalCase
form), Qwen Code, Kimi and Factory become a table each, plus a process name. Claude Code keeps its own provider
because of its special rules.

**The plugin input format.** For agents with plugins (opencode, Amp) and anything else that can run a command, `asb
hook --agent <id> --events` reads one normalized event on stdin:

```json
{"event":"waiting","sessionId":"ses_7Hq2","cwd":"/Users/alex/code/api-gateway","pid":48213,"reason":"question","message":"Which database?"}
```

The plugin sends only state changes (a handful per turn, not every streamed token), never waits for `asb` to exit,
and never prints. This keeps `asb hook` the only writer of state files, with one set of writer rules.

### How `asb hook` learns who called it

- Each integration installs a command that names its agent: `'<asb>' hook --agent codex # agentic-status-bar`.
- **No `--agent` means Claude Code,** so today's installed hooks keep working without a reinstall.
- An unknown `--agent` value exits 0 silently, as bad input does today.
- **Guard against borrowed hooks:** on the Claude Code path, a call with `CURSOR_VERSION` in the environment comes
  from Cursor's import of `~/.claude/settings.json` and is ignored. Cursor sessions are recorded only through the
  Cursor integration. This guard is worth shipping before any other provider, since it may already matter (Part 2 ›
  Cursor).

### State file changes

| Change | Detail |
| --- | --- |
| New optional field `agent` | String, a provider ID. **Missing means `claude-code`.** The Claude Code hook keeps not writing it, so its files stay byte for byte as today; every other provider always writes it. |
| `pid` | "PID of the agent process" instead of "the `claude` process"; found by the provider's walk |
| `kind` | Same four values; the provider decides (`codex exec`, `gemini -p`, `cursor-agent -p` → headless) |
| `transcriptPath` | Any agent's transcript; C3 reads it only when the provider has a `turnEnd` reader |
| File name | Still `<sessionId>.json`. Codex, Gemini, Copilot and Cursor IDs are UUIDs, opencode's are `ses_…` and Amp's `T-<uuid>`, so they don't collide. A provider whose IDs aren't globally unique prefixes them (Aider has none: `aider-<pid>-<start epoch>`). |
| Stale files at start | Only files with the same `pid` **and** the same agent are deleted (A10) |

**No version bump.** The schema's rule is "changes that readers could misread need a new version number; adding an
optional field does not." An old reader that doesn't know `agent` shows a Codex session as a Claude Code session:
the state, reason and times are still right, and C2 and C3 find nothing to act on (no registry entry; the Claude
Code parser finds no prompt or turn marker in a Codex rollout). The app and the `asb` copy the hooks run are always
the same version (the app keeps the copy in sync), so this only affects third-party readers. Bumping to `v: 2` would
turn every new session into the warning state on old readers, which is worse.

**New reader rules:**

6. A missing `agent` is `claude-code`. An `agent` the reader doesn't know is shown with its ID as the name, and only
   the generic checks (C1, C5) apply.
7. Readers apply only the checks the session's provider lists (table below).

**Checks per provider:**

| Check | Claude Code | Codex | Copilot | opencode 1.x | Gemini | Cursor | Amp | Aider |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 liveness | ✓ | ✓ | ✓ | ✓ | ✓ | CLI only | ✗ | ✓ |
| C2 registry | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| C3 turn ended | ✓ | ✓ (rollout `task_complete`/`turn_aborted`) | ✗ (format undocumented) | ✗ | ✗ | ✗ | ✗ | ✗ |
| C4 approved tool | ✓ (ignores `caffeinate`) | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ |
| C5 staleness | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

The engine change is small: `Engine.reconcile` runs each check as today, and each check skips sessions whose
provider doesn't list it. For sessions without `agent` every check runs, which is exactly today's behavior.

### Snapshot changes

- `sessions[]` gains an optional `agent` (string): the state file's `agent`, **absent when the file has none**.
  Readers treat absent as `claude-code`. Snapshot version stays `1` (an optional field; readers ignore unknown
  fields). All 80 conformance cases keep their `expected.json`.
- No display name in the snapshot: names belong to the providers, and the schema doc lists the IDs and names.
- `HerdrTitles.parse` keys titles by agent and session ID, taking each provider's `herdrName` (which names herdr uses
  for other agents is **unverified**).

### UI

- **Rows:** when the snapshot holds sessions of more than one agent, each row gets a small secondary badge after the
  project (`api-gateway · Codex — Add rate limiting`); with one agent the row looks as today. The state icon and
  color stay per state, never per agent, so the meaning of red and yellow doesn't change.
- **Notifications:** the body names the agent: "Codex needs your permission to continue.", "Codex has a question for
  you.", from `shortName`. Claude Code sessions keep today's text.
- **Empty state:** "No agent sessions" instead of "No Claude Code sessions".
- **Settings › Agents** (a new tab, or a section of General): one row per provider with whether the agent is found
  on this Mac (its binary or config dir), whether its integration is installed, Install / Remove…, a one-line note on
  what it can show ("busy and idle only: Cursor reports no permission prompts"), and a Show toggle. Claude Code's
  row replaces today's "Claude Code hooks" section.
- **Config:** one key per provider, `show_agent_<id>` (`1` by default), filtered like the session kinds. The value
  rules allow these keys; a comma list would not pass `Config.isValid`.
- **First run:** lists the agents found and installs Claude Code's hooks as today; others are opt-in checkboxes,
  with the agent-specific step spelled out (Codex: "approve the hooks once with `/hooks`").
- **Help:** a short table of what each agent can report.

### Installing integrations

| Kind | Agents | Install | Uninstall |
| --- | --- | --- | --- |
| Merge into a shared JSON file | Claude Code, Codex (`~/.codex/hooks.json`), Cursor (`~/.cursor/hooks.json`) | Back up, append our entries tagged with the marker, keep everything else in order (today's `HookSettings`, generalized by entry shape) | Back up, remove marked entries and what they leave empty |
| A file of our own | Copilot (`~/.copilot/hooks/asb.json`), opencode 1.x (`~/.config/opencode/plugins/agentic-status-bar.js`), Amp (`~/.config/amp/plugins/agentic-status-bar.ts`), Gemini (an extension in `~/.gemini/extensions/agentic-status-bar/`) | Write the file atomically | Delete it, only if it still carries our marker |
| Single slot | Aider (`~/.aider.conf.yml`) | Not automatic. Documented manual step only | — |

`Integration` has `status()` (not found, not installed, installed, needs a step from the user), `install(asb:)`
and `uninstall()`. `Installer` loops over the enabled providers' integrations, and `asb install --agent codex`
installs one. Every edit is backed up first, as today, and a file that doesn't parse is never changed.

Agent-specific notes: Codex hooks run only after the user trusts them (we append, never insert, so the user's trust
keys don't move; writing `trusted_hash` ourselves is left for later). Gemini settings hooks don't run in untrusted
folders, which is why the extension route is preferred. Cursor: register only on `sessionStart`,
`beforeSubmitPrompt`, `postToolUse`, `afterShellExecution`, `afterMCPExecution`, `afterAgentResponse`, `stop`,
`subagentStop` and `sessionEnd`, never on permission-type events.

### Feasibility

✓ works from documented events; partial: works with gaps or depends on unverified behavior; ✗ not possible today.
"Focus" means a herdr pane can be recorded (the hook or plugin sees `HERDR_PANE_ID`).

| Agent | Busy | Waiting: permission | Waiting: question | Idle | Subagents | Process liveness | Focus |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Code (today) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Codex CLI | ✓ | ✓ `PermissionRequest` | partial (`request_user_input`, Plan mode) | ✓ `Stop`, `Interrupt`, C3 | ✓ | ✓ | ✓ |
| Copilot CLI | ✓ | ✓ `permission_prompt` | partial (`elicitation_dialog`) | ✓ `agentStop` | partial (not general-purpose) | partial (process name) | ✓ |
| opencode 1.x | ✓ | ✓ `permission.asked` | ✓ `question.asked` | ✓ `session.idle` | ✓ child sessions | ✓ TUI; ✗ server, desktop | ✓ TUI |
| opencode 2.x | partial (event names) | partial | partial | partial | partial | ✗ shared daemon | ✗ |
| Gemini CLI | ✓ | ✓ `ToolPermission` | ✓ `ask_user` | partial (no event on Esc) | ✗ no IDs | ✓ | partial (sanitized env) |
| Cursor CLI | partial (varies by build) | ✗ | ✗ | partial (no `stop` with `-p`) | ✓ | partial | partial |
| Cursor IDE | ✓ | ✗ | ✗ | ✓ `stop` | ✓ | ✗ no terminal | ✗ |
| Amp | ✓ thread state | ✓ `awaiting-approval` | ✗ | ✓ | partial (child threads) | ✗ | partial |
| Aider | ✗ | partial (one ambiguous ping) | ✗ | partial | — (none) | ✓ | ✓ |
| Qwen, Kimi, Crush, Factory | ✓ | ✓ | partial | ✓ | partial | partial (unverified names) | ✓ |

### Recommended order

| Step | What | Why |
| --- | --- | --- |
| 0 | The Cursor guard on the Claude Code path | Cheap, and may fix wrong rows today |
| 1 | Provider abstraction with Claude Code only | No behavior change; the conformance suite and unit tests prove it |
| 2 | **Codex** | Hooks almost identical to Claude Code's, all four states, subagents, C1 and a usable C3 from rollouts. The trust step is a one-time user action |
| 3 | **Copilot CLI** | Claude Code-like hooks, permission and question from notification types, and the cleanest install (our own file) |
| 4 | **opencode 1.x** | The most explicit states of any agent; needs the plugin input format and a JS file. Wait for 2.x to settle before supporting it |
| 5 | Qwen Code, Kimi, Crush, Factory | One table each once `HookShapedProvider` exists; do them on request |
| 6 | Gemini CLI | Good signals, but the product is being replaced by Antigravity CLI for most users |
| 7 | Cursor | Busy and idle only, and CLI hooks vary by build; useful but can never turn the menu bar red |
| 8 | Amp | Plugin only, no question state, no pid, remote threads |
| — | Aider | Not recommended: one ambiguous ping, no session ID, a single config slot |

### Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Formats churn (CLIs release weekly; opencode 2.x, Codex `notify` slated for removal, Gemini to Antigravity) | A provider silently stops reporting | Fixtures of real payloads per agent and version in `tests/fixtures/<agent>/`; lenient parsing (unknown events ignored); C5 bounds the damage; Settings shows "installed" from the config file, not from events |
| Another agent runs our Claude Code hook (Cursor import, Copilot repo hooks) | Wrong or duplicate rows | `--agent` on every non-Claude command; the `CURSOR_VERSION` guard |
| Hook budget: Codex starts a login shell, Gemini and Aider wait for the hook | The user feels a slower agent | `asb hook` stays under 10 ms (`tests/bench.sh` per provider); no process walk except at session start or backfill, as today; plugins don't wait for `asb` |
| Output where none is allowed (Gemini shows it, Codex feeds it to the model, Copilot fails closed, Cursor blocks on bad JSON) | Visible noise, or blocked tools | No output, exit 0, as today; no registration on events that need a reply; a test per provider that runs `asb hook` and checks empty stdout and stderr |
| Privacy: payloads carry prompts, tool input, the last assistant message, Cursor's `user_email` | Data on disk | Keep only what today keeps (an 80-character preview, the notification text); never log payloads; `store_prompt_preview=0` applies to every provider |
| Install damages a user's config (TOML, YAML, JSONC, trust keys by position) | Lost settings or untrusted hooks | Back up first; only JSON files and files of our own in the first steps; append, never insert; never touch a file that doesn't parse |
| Shared servers (opencode 2.x, Cursor IDE, Amp) have no session pid | Dead sessions stay listed | End events plus C5; such rows can't be "exact" and the docs say so |
| Snapshot cost grows with more readers per check | Over the 30 ms budget | Checks stay per session and only for busy or waiting files, as today; transcripts still capped at 8 KB |

### Migration

1. A state file without `agent` is Claude Code, and the Claude Code hook keeps writing exactly today's files.
2. Hooks installed today (`asb hook` without `--agent`) keep working; no reinstall is needed.
3. The snapshot leaves `agent` out for those files, so all 80 conformance cases pass unchanged, and the runner
   needs no change. New cases (`codex-*.case.json`, `agent-*.case.json`) add other agents.
4. The Claude Code refactor to `AgentEvent` lands first, alone, with every existing unit test unchanged.
5. UI text changes ("No agent sessions", the agent in notifications) are in the app only, not in the snapshot.
6. The state dir stays `~/.claude/agentic-status-bar/` for now (see open questions).

### Tasks

Each task fits in under 10 minutes for an agent, keeps the suite green, and lists the files it touches.

| # | Task | Type | Files | Depends on |
| --- | --- | --- | --- | --- |
| 1 | Ignore Claude Code hook calls that carry `CURSOR_VERSION` in the environment; unit test | feature | `Sources/asb/Hook.swift`, `tests/ASBCoreTests/` | — |
| 2 | Document `agent` (optional, default `claude-code`), reader rules 6 and 7, the provider ID table | docs | `doc/state-file-schema.md` | — |
| 3 | Document the optional `sessions[].agent` | docs | `doc/snapshot-schema.md` | 2 |
| 4 | `StateFile.parse` reads `agent`; `agentId` defaults to `claude-code`; unit tests | feature | `Sources/ASBCore/StateFile.swift`, tests | 2 |
| 5 | `Snapshot.Session.agent` (optional), set from the file in `MenuModel.row`; conformance stays green | feature | `Sources/ASBCore/Snapshot.swift`, `MenuModel.swift` | 3, 4 |
| 6 | Conformance case: a state file with `agent: "codex"` shows `agent` in its row | test | `tests/conformance/agent-field.case.json` | 5 |
| 7 | Add `AgentProvider`, `CheckSet`, `Providers.all` and `ClaudeCodeProvider` wrapping `findClaude`, `kind` and the constants (no callers changed yet) | refactor | `Sources/ASBCore/Providers/AgentProvider.swift`, `ClaudeCode.swift` | 4 |
| 8 | Add `AgentEvent` and `AgentEvents.apply` (today's rules on the new cases); unit tests copied from `HookEvents` tests | refactor | `Sources/ASBCore/AgentEvents.swift`, tests | 7 |
| 9 | `ClaudeCodeProvider.events` maps a payload to `AgentEvent`s; `HookEvents.apply` calls it plus `AgentEvents.apply`; every existing test unchanged | refactor | `Sources/ASBCore/HookEvents.swift`, `Providers/ClaudeCode.swift` | 8 |
| 10 | `asb hook --agent <id>`: no flag = Claude Code; unknown = silent exit; `agent` written for non-Claude providers | feature | `Sources/asb/Hook.swift` | 9 |
| 11 | Stale-file cleanup at session start matches agent as well as pid; unit test | feature | `Sources/ASBCore/HookMetadata.swift`, tests | 4 |
| 12 | Checks skip sessions whose provider doesn't list them; unknown agent gets C1 and C5 only; unit tests | feature | `Sources/ASBCore/Checks.swift`, `Registry.swift`, `Transcript.swift`, `Engine.swift` | 7 |
| 13 | C4 and the subagent rule take `ignoredChildren` and `subagentTools` from the provider | refactor | `Sources/ASBCore/Checks.swift` | 12 |
| 14 | Conformance case: an unknown agent's waiting session isn't turned busy by C4 or idle by C3 | test | `tests/conformance/agent-unknown-checks.case.json` | 12 |
| 15 | Plugin input format: `asb hook --agent <id> --events` parses one normalized event; unit tests | feature | `Sources/ASBCore/AgentEvents.swift`, `Sources/asb/Hook.swift` | 10 |
| 16 | `HookShapedProvider`: table-driven mapping of Claude Code-shaped payloads; unit tests with a made-up table | feature | `Sources/ASBCore/Providers/HookShaped.swift`, tests | 8 |
| 17 | Spike: record real Codex hook payloads (each event, a permission, an interrupt, a subagent) and a rollout tail | test | `tests/fixtures/codex/`, `tests/fixtures/README.md` | — |
| 18 | `CodexProvider` table and process walk (`codex`, or `node` running codex; `codex exec` → headless) | feature | `Sources/ASBCore/Providers/Codex.swift` | 16, 17 |
| 19 | Codex C3: turn ended when the last `event_msg` after `task_started` is `task_complete` or `turn_aborted` | feature | `Sources/ASBCore/Providers/Codex.swift`, tests | 18 |
| 20 | Codex: `SessionStart` for a subagent (same `session_id`, file busy) doesn't reset the state; unit test | feature | `Sources/ASBCore/Providers/Codex.swift` | 18 |
| 21 | Conformance cases for Codex: permission, interrupt by rollout, dead process | test | `tests/conformance/codex-*.case.json` | 19 |
| 22 | `Integration` protocol; `HookSettings` generalized by file and entry shape; Claude Code conforms; tests unchanged | refactor | `Sources/ASBCore/Settings.swift`, `Installer.swift` | 7 |
| 23 | Codex integration: append marked entries to `~/.codex/hooks.json` with a backup; status "needs trust"; tests in a temp home | feature | `Sources/ASBCore/Providers/Codex.swift`, `Installer.swift` | 22 |
| 24 | `asb install --agent <id>` and `asb uninstall --agent <id>` | feature | `Sources/asb/Install.swift` | 23 |
| 25 | Config keys `show_agent_<id>`; `Filters` by agent; conformance case for a hidden agent | feature | `Sources/ASBCore/Config.swift`, `Filters.swift`, `tests/conformance/filters-hidden-agent.case.json` | 7 |
| 26 | Notification text from the provider's `shortName`; Claude Code text unchanged; tests | feature | `App/Sources/NotificationRules.swift`, app tests | 5 |
| 27 | Row agent badge when the snapshot holds more than one agent | feature | `App/Sources/SessionRow.swift`, `PopoverView.swift` | 5 |
| 28 | "No agent sessions" and other agent-neutral text | refactor | `App/Sources/StatusItemController.swift`, `PopoverView.swift`, `HelpView.swift`, `AboutPanel.swift`, `Sources/asb/ASB.swift` | — |
| 29 | Settings › Agents: per provider status, Install / Remove…, Show toggle | feature | `App/Sources/SettingsView.swift`, `HookInstaller.swift` | 24, 25 |
| 30 | First run lists found agents; others opt-in, with Codex's trust step explained | feature | `App/Sources/FirstRunView.swift` | 29 |
| 31 | `HerdrTitles` keyed by provider `herdrName` and session ID; Claude Code cases unchanged | feature | `Sources/ASBCore/MenuModel.swift` | 7 |
| 32 | Spike: record Copilot CLI payloads (camelCase), the process tree and `comm` | test | `tests/fixtures/copilot/` | — |
| 33 | `CopilotProvider` table (`notification_type` → reason; `agentStop` → idle) and process walk | feature | `Sources/ASBCore/Providers/Copilot.swift` | 16, 32 |
| 34 | Copilot integration: write and remove `~/.copilot/hooks/asb.json` | feature | `Sources/ASBCore/Providers/Copilot.swift` | 22, 33 |
| 35 | opencode 1.x plugin file: send `session.status`, `permission.*`, `question.*`, `session.idle`, `session.deleted` to `asb hook --events`, silently | feature | `Sources/ASBCore/Resources/opencode-plugin.js` | 15 |
| 36 | `OpencodeProvider` (process `opencode`; checks C1, C4, C5) and its integration (write and remove the plugin file) | feature | `Sources/ASBCore/Providers/Opencode.swift` | 22, 35 |
| 37 | Bench: `asb hook` per provider stays under 10 ms; empty stdout and stderr | test | `tests/bench.sh`, tests | 18, 33 |
| 38 | PRD and README: agents supported, what each can show | docs | `doc/PRD.md`, `README.md` | 30 |

Later steps (Gemini extension, Cursor, Amp, the Qwen/Kimi/Crush/Factory tables) follow the same pattern: a fixture
spike, a provider, an integration, conformance cases.

## Open questions

1. **State dir:** keep `~/.claude/agentic-status-bar/` (no move, odd name for other agents) or move to
   `~/Library/Application Support/agentic-status-bar/state` with a one-time migration like the SwiftBar rename?
2. **Codex trust:** leave the `/hooks` approval to the user (proposed), or write `trusted_hash` ourselves from
   Codex's undocumented hashing?
3. **Cursor today:** does Cursor translate imported Claude Code hook payloads? A quick check with the IDE decides
   whether the guard in step 0 fixes a visible bug or only prevents one.
4. **Busy-and-idle-only agents** (Cursor, Kiro, Goose): worth showing, given they can never show "waiting"? Proposed:
   yes, with the Settings note, since idle is half the value.
5. **opencode 2.x:** wait for it to settle, or support the shared daemon now through its event stream (outside the
   hook model)?
6. **Antigravity CLI:** does it keep Gemini CLI's hooks? If yes, Gemini support may be worth more than step 6.
7. **Codex `SessionStart` for subagents:** confirm in the spike (task 17) that it carries the parent's `session_id`;
   task 20 depends on it.
