# Test fixtures

Captured from Claude Code 2.1.310 on 2026-10-25 (spike T-003), then sanitized: session IDs, paths, prompts and tool
input are made up.

## payloads/

One hook payload per event (and per notification type). Findings:

| Event | Notes |
| --- | --- |
| `SessionStart` | `source` (`startup`, ...), `model`. The hook process's parent (`$PPID`) is the `claude` process itself. |
| `UserPromptSubmit` | Background-task results also arrive here, with `prompt` starting `<task-notification>` (see `UserPromptSubmit-task-notification.json`). Don't use those as the prompt preview. |
| `PreToolUse` / `PostToolUse` | `tool_name`. The main agent's tool events (also the `Agent` tool) have no `agent_id`; a subagent's carry its `agent_id` and `agent_type` (`PreToolUse-subagent.json`, `PostToolUse-subagent.json`). |
| `PermissionRequest` | Fires within milliseconds of the prompt appearing, about 6 s before the permission `Notification`. A subagent's carries its `agent_id` and `agent_type` (`PermissionRequest-subagent.json`). No `tool_use_id`. Not one of the events the app installs. |
| `Notification` | `notification_type` is `permission_prompt` (message "Claude needs your permission") or `idle_prompt` ("Claude is waiting for your input", about 60 s after a turn ends). An `AskUserQuestion` question also arrives as `permission_prompt`; tell it apart by the preceding `PreToolUse` with `tool_name` `AskUserQuestion`. `elicitation_dialog` (MCP) was not captured. |
| `Stop` | Not fired when a permission is denied, or when Esc cancels a turn before any output. |
| `SubagentStart` / `SubagentStop` | Same `agent_id` on both. After every `Stop` an extra `SubagentStop` fires with `agent_type` `""` and no matching start (`SubagentStop-empty.json`): ignore it. |
| `SessionEnd` | `reason`, e.g. `prompt_input_exit`, `other` (headless). |

## A subagent waiting on a permission

Captured from Claude Code 2.1.316 on 2026-11-01 (spike T-119): two subagents started together, one hitting a Bash
permission prompt while the other kept reading files; once approved, once denied.

- `Agent` returns at once: its `PostToolUse` follows `SubagentStart` within milliseconds and the subagents run in the
  background, so the parent's `Stop` fires while the prompt is still up.
- In order: the subagent's `PreToolUse`, its `PermissionRequest` (4 ms later, with `agent_id`), the parent's `Stop`,
  then `Notification` `permission_prompt` about 6 s after the prompt appeared, **without** `agent_id`
  (`Notification-permission_prompt-subagent.json`).
- Meanwhile the other subagent's `PreToolUse`/`PostToolUse` keep coming; today each one sets the session back to
  busy, so "waiting" lasts under a second.
- No hook fires on approval or denial. Approved: the waiting subagent's own `PostToolUse` for that tool is the first
  sign (here 19 s later). Denied: no `PostToolUse` at all; the subagent gets an error tool result and either goes on
  (its next `PreToolUse`) or ends (`SubagentStop`).
- A subagent's denial is written to its own transcript, `<session>/subagents/agent-<agent_id>.jsonl` (also in
  `SubagentStop`'s `agent_transcript_path`), as an `is_error` tool result with `toolDenialKind` `user-rejected`
  (`transcripts/denied-permission-subagent.jsonl`); no `[Request interrupted by user for tool use]` marker, and
  nothing in the session's own transcript.
- While the subagent waited, the `claude` process's only child was `caffeinate`: C4 has nothing to see.

## Environment seen by hooks

| Variable | Interactive CLI | `claude -p` |
| --- | --- | --- |
| `CLAUDE_CODE_ENTRYPOINT` | `cli` | `sdk-cli` |
| `HERDR_PANE_ID` | set inside herdr (e.g. `w2:p1`) | inherited |
| `__CFBundleIdentifier` | host terminal app, e.g. `com.mitchellh.ghostty` | inherited |

## transcripts/

Minimal transcript tails for the interrupt check (C3):

- `denied-permission.jsonl`: denying a permission writes `[Request interrupted by user for tool use]`, then a
  `system`/`turn_duration` entry. No hook fires.
- `denied-permission-subagent.jsonl`: a subagent's denial, from its own transcript (see above).
- `completed-turn.jsonl`: a normal turn ends with `system`/`turn_duration` (after `Stop` ran).
- `esc-before-output.jsonl`: Esc before any output leaves the user prompt as the last entry, with no marker and no
  hook. Only the Claude Code registry (C2) or staleness (C5) catches this case; the registry showed `idle` within
  seconds.

Esc while a tool is running prints `[Request interrupted by user]` (seen in real sessions; not re-captured here).

## Process tree

While a permission-approved Bash tool runs, the `claude` process has a `/bin/zsh` child started after the
permission prompt (C4). A `caffeinate` child is started at the beginning of each turn, before any prompt; C4 should
ignore it.
