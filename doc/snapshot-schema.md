# Snapshot schema, version 1

A snapshot is what every front end shows: the sessions after the reconciliation checks, filters and mutes, in display
order, plus the menu-bar header. `asb snapshot --json` prints one; the app computes the same with `ASBCore`; the
SwiftBar renderer and the conformance suite (`tests/conformance/`) are built on it. The Swift types are in
`Sources/ASBCore/Snapshot.swift`.

Inputs are the state files described in [state-file-schema.md](state-file-schema.md), Claude Code's session
registry, transcripts, the process table, herdr's agent list, the config and the mutes file.

JSON is encoded with sorted keys; optional fields are left out when absent. Readers must ignore unknown fields.

## Top level

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | integer | `1` |
| `generatedAt` | integer, epoch ms | When the snapshot was made; every `detail` text is relative to it |
| `invalidFiles` | integer | State files that couldn't be read (shown as a warning) |
| `activeMutes` | integer | Muted projects, with or without a running session (drives "Unmute all") |
| `header` | object | The menu-bar item (below) |
| `sessions` | array | Rows in display order (below) |

## `header`

The most urgent state over the sessions that aren't muted, checked in this order:

| `state` | When | `count` |
| --- | --- | --- |
| `warning` | `invalidFiles > 0` | all sessions |
| `waiting` | any waiting (muted ones included: waiting breaks through mutes) | waiting sessions |
| `idle` | any idle | idle sessions |
| `uncertain` | any uncertain | uncertain sessions |
| `busy` | any session left (busy or waiting on subagents) | those sessions |
| `muted` | sessions exist but all are muted | absent |
| `none` | no sessions | absent |

| Field | Type | Meaning |
| --- | --- | --- |
| `state` | string | As above |
| `symbol` | string | SF Symbol name from the theme |
| `color` | string | `#RRGGBB,#RRGGBB` (light, dark) from the theme |
| `count` | integer | Absent for `muted` and `none` |

## `sessions[]`

Sorted by rank (waiting 0, idle 1, uncertain 2, busy and subagents 3, muted 5), then by `since`, oldest first.
Sessions of hidden kinds (filters) are left out entirely.

| Field | Type | Meaning |
| --- | --- | --- |
| `sessionId` | string | |
| `project` | string | Last component of `cwd`, or `unknown` |
| `title` | string | herdr terminal title, else a user-given session name, else the prompt preview; `""` when none |
| `cwd` | string | Absent when unknown |
| `kind` | string | `interactive`, `headless`, `ide` or `desktop` |
| `shown` | string | `waiting`, `idle`, `uncertain`, `busy` or `subagents` (after checks C1–C5) |
| `reason` | string | `permission` or `question` when waiting |
| `since` | integer, epoch ms | Since when the session is in `shown` |
| `label` | string | `project — title` (or `project`), `\|` replaced by `│`, `:name:` broken with a zero-width space, cut to 48 characters with `…` or padded with spaces to 48 |
| `word` | string | `permission`, `question`, `idle`, `no activity`, `waiting on N subagent(s)` or `working` |
| `detail` | string | Time in state (`12s`, `4m`, `2h`, `3d`), or `muted today` / `muted until HH:MM` (local time) when muted |
| `muted` | boolean | Muted and not waiting |
| `muteUntil` | integer, epoch ms | When the project's mute ends; present whenever the project is muted, also while waiting |
| `muteToday` | boolean | Present with `muteUntil` |
| `herdrPane`, `termBundleId`, `transcriptPath` | string | From the state file, when known |
| `focusable` | boolean | herdr is installed and the session has a pane |
| `symbol`, `color` | string | The theme's symbol and color for the row's state (`muted` when muted) |
| `subagents` | array | Running subagents, oldest first: `{id, type, since, detail}`; empty when `show_subagents=0` |
