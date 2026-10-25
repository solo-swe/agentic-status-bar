# Future architecture: SwiftBar plugin, standalone app, or atm integration

Status: proposal for discussion. Nothing here is decided.

## Where we are

Minimalist Claude Code Statusbar has two halves:

- **Hooks** (`hooks/state-hook.sh`) write one JSON state file per Claude Code session to `~/.claude/swiftbar-claudecode-minimal/`. They know nothing about SwiftBar.
- **The SwiftBar plugin** (`swiftbar/swiftbar-claudecode-minimal.5s.sh`) reads those files every 5 seconds (or on a hook's refresh request), corrects them with checks C1 to C5, and prints SwiftBar's text menu format.

The state file is the contract between them (schema `v: 1`, see the PRD). Any of the directions below keeps the hooks and the state files. They differ only in what reads the files and draws the UI.

What SwiftBar has cost us so far:

- **Colors:** SwiftBar colors only inline `:symbol:` text, not `sfimage`. We worked around it, but symbol and text weight are limited to what the text format allows.
- **Start at login:** a plugin can't change SwiftBar's own preference, so we write our own LaunchAgent.
- **No live UI:** every change is a full re-run of a shell script and a menu rebuild. There is no hover state, no animation by choice, and no text input.
- **Two installs:** users install SwiftBar, then our plugin, then the hooks.
- **Performance budget:** each refresh runs `awk`, `stat`, `tail`, `ps` and `jq` (about 100 ms). It's fine at 5 seconds, but it's a floor.

## Option A: stay a SwiftBar plugin

Keep the current design and keep improving it.

| | |
| --- | --- |
| **Enables** | Everything shipped today; fast iteration in shell and jq; no build, signing or notarization |
| **Cost** | Low. Each feature is a change to one script plus bats tests |
| **Risks** | SwiftBar's text format caps the UI (no per-row layout, limited symbol styling, menu rebuilt every refresh). It depends on a third-party app staying maintained. Shell and jq complexity keeps growing (themes and mutes added about 150 lines) |
| **Carries over** | Everything |
| **Migration** | None |

## Option B: a standalone macOS menu-bar app

A small native app (Swift, SwiftUI `MenuBarExtra`) that reads the same state files.

| | |
| --- | --- |
| **Enables** | True colors and SF Symbol rendering modes; a real popover with rows, hover, buttons and inline settings; `SMAppService` launch at login (no LaunchAgent workaround); optional notifications (the PRD said none for v1, but it becomes possible); file watching with FSEvents instead of polling, so updates are instant without `open swiftbar://`; checks run in-process, so no 100 ms per refresh |
| **Cost** | Medium to high. Write the app (UI, file watching, checks C1 to C5 ported from jq to Swift); Developer ID signing and notarization ($99/year Apple Developer account) or an unsigned build users must allow by hand; distribution (GitHub releases, a Homebrew cask, maybe Sparkle for updates); Swift unit tests and CI on macOS |
| **Risks** | Two codebases during the transition; checks C3 and C4 depend on undocumented Claude Code behavior and must be kept in sync in both; a larger surface for a "minimal" tool |
| **Carries over** | Hooks, the state file format, install of the hooks (`install.sh` or the Claude Code plugin), the test fixtures (payloads, transcripts) as Swift test inputs, the PRD's UX rules and priorities |
| **Migration** | 1. Freeze the state file schema (`v: 1`) and document it as the public contract. 2. Build the app reading the same files; ship it alongside the plugin. 3. When it matches the plugin, keep the plugin as the "no app" option or retire it |

## Option C: integrate with atm (agentic-task-manager)

atm already tracks tasks, claims and loops per project, and serves a local dashboard. Its claims name the agent as `claude:<session ID prefix>`, and our state files are keyed by the same Claude Code session ID. So a session row can be joined with the task it is working on, and the reverse.

Two shapes:

- **C-menu: tasks in the status bar.** The row title becomes the claimed task, e.g. `api-gateway — T-012 Add rate limiting`, and the submenu shows loop progress (`3 of 8 done`) and opens atm's dashboard. The plugin finds the project's `.agentic-task-manager/` from the session's `cwd` and asks `atm` for the claim, or reads the file atm documents as its public interface.
- **C-dashboard: sessions in atm's dashboard.** atm's dashboard reads our state files and shows, next to each in-progress task, whether its agent is working, idle or waiting on a permission. Attention lives where the task context already is.

| | |
| --- | --- |
| **Enables** | "Which task is this agent on?" and "which agent is stuck on my task?" answered in one place. Loop runs become visible from the menu bar: an idle loop agent is a stalled loop |
| **Cost** | C-menu: low to medium (one more input to the refresh, a cached per-project lookup). C-dashboard: medium, but in atm's code base and release cycle |
| **Risks** | Coupling two tools that are useful alone. atm's rule that only `atm` reads `tasks.json` means C-menu must call `atm` (a Python process, 50 to 100 ms) or atm must publish a cheap, stable read model. Not every session uses atm, so both must degrade to today's behavior |
| **Carries over** | Everything; it adds an optional input |
| **Migration** | Start with C-menu behind a setting (`show_atm_tasks`), using `atm status --json` cached per project for a few seconds. If it proves useful, agree a small "claims" file atm writes for readers like us, and consider C-dashboard on the atm side |

## Comparison

| | A: SwiftBar | B: standalone app | C: atm integration |
| --- | --- | --- | --- |
| UI ceiling | Low | High | Same as A or B (it's an input, not a UI) |
| Effort | Low | High | Low (C-menu) to medium (C-dashboard) |
| Install steps for users | SwiftBar + plugin + hooks | App + hooks | Adds nothing for non-atm users |
| Distribution and signing | None | Required | None |
| Refresh cost | ~100 ms per refresh | Near zero, event-driven | +atm lookup per project |
| Risk to "minimal" | Low | Medium | Low if optional |

C is not an alternative to A or B. It can sit on either.

## Recommendation

1. **Stay on SwiftBar for now (A)**, and treat the state file as a public, versioned contract. That keeps every option open at no cost.
2. **Prototype C-menu behind a setting.** It's the cheapest way to learn whether task context in the status bar is worth it, and it uses the session-ID link that already exists.
3. **Revisit B when SwiftBar's limits block a feature you want.** Candidates: notifications, a richer popover, instant updates without SwiftBar's refresh URL, or a one-step install for people who don't use SwiftBar. At that point build B as a reader of the same state files, not a rewrite of the hooks.

## Open questions

1. Is the audience mostly people who already run SwiftBar, or should a one-step install without SwiftBar matter? That decides how soon B is worth its signing and distribution cost.
2. Would you pay for an Apple Developer account for signing and notarization, or ship B unsigned (users right-click and Open the first time)?
3. For C: should the status bar show the claimed task (C-menu), should atm's dashboard show session state (C-dashboard), or both?
4. For C-menu: is calling `atm` from the plugin acceptable, or should atm publish a small read-only claims file meant for other tools?
5. Should notifications stay out for good, or are they the first reason to move to B?
