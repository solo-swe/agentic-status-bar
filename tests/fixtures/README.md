# Test fixtures

Captured from Claude Code 2.1.310 on 2026-10-25 (spike T-003), then sanitized: session IDs, paths, prompts and tool
input are made up.

## payloads/

One hook payload per event (and per notification type). Findings:

| Event | Notes |
| --- | --- |
| `SessionStart` | `source` (`startup`, ...), `model`. The hook process's parent (`$PPID`) is the `claude` process itself. |
| `UserPromptSubmit` | Background-task results also arrive here, with `prompt` starting `<task-notification>` (see `UserPromptSubmit-task-notification.json`). Don't use those as the prompt preview. |
| `PreToolUse` / `PostToolUse` | `tool_name`; no `agent_id` on tool events, even for the `Agent` tool. |
| `PermissionRequest` | Fires right before the permission `Notification`. |
| `Notification` | `notification_type` is `permission_prompt` (message "Claude needs your permission") or `idle_prompt` ("Claude is waiting for your input", about 60 s after a turn ends). An `AskUserQuestion` question also arrives as `permission_prompt`; tell it apart by the preceding `PreToolUse` with `tool_name` `AskUserQuestion`. `elicitation_dialog` (MCP) was not captured. |
| `Stop` | Not fired when a permission is denied, or when Esc cancels a turn before any output. |
| `SubagentStart` / `SubagentStop` | Same `agent_id` on both. After every `Stop` an extra `SubagentStop` fires with `agent_type` `""` and no matching start (`SubagentStop-empty.json`): ignore it. |
| `SessionEnd` | `reason`, e.g. `prompt_input_exit`, `other` (headless). |

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
- `completed-turn.jsonl`: a normal turn ends with `system`/`turn_duration` (after `Stop` ran).
- `esc-before-output.jsonl`: Esc before any output leaves the user prompt as the last entry, with no marker and no
  hook. Only the Claude Code registry (C2) or staleness (C5) catches this case; the registry showed `idle` within
  seconds.

Esc while a tool is running prints `[Request interrupted by user]` (seen in real sessions; not re-captured here).

## Process tree

While a permission-approved Bash tool runs, the `claude` process has a `/bin/zsh` child started after the
permission prompt (C4). A `caffeinate` child is started at the beginning of each turn, before any prompt; C4 should
ignore it.
