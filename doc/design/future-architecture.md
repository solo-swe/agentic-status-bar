# Future architecture: SwiftBar plugin, standalone app, or atm integration

Status: proposal for discussion. The direction is agreed (see Decisions); the tech choices and phasing are proposals.

## Decisions so far

| Question | Answer |
| --- | --- |
| Audience | No user base yet. Not aimed at SwiftBar users: a standalone app is preferred |
| Apple Developer account (signing, notarization) | Fine to pay for |
| Calling `atm` from another tool | Fine |
| Notifications | In scope for the future architecture |

## Where we are

Minimalist Claude Code Statusbar has two halves:

- **Hooks** (`hooks/state-hook.sh`, 372 lines of POSIX sh with embedded jq) write one JSON state file per Claude Code session to `~/.claude/swiftbar-claudecode-minimal/`. They know nothing about SwiftBar.
- **The SwiftBar plugin** (`swiftbar/swiftbar-claudecode-minimal.5s.sh`, 759 lines, mostly jq programs held in shell strings) reads those files every 5 seconds or on a hook's refresh request, corrects them with checks C1 to C5, applies filters, mutes and themes, and prints SwiftBar's text menu format.

Shared code is in `lib/common.sh` (178 lines), plus `install.sh` and `uninstall.sh`. The tests are about 2,000 lines of bats in 203 tests, with fixtures of real hook payloads and transcripts.

The state file is the contract between the two halves: schema `v: 1`, described in the PRD. Every option below keeps that contract. What changes is the language the logic is written in and what draws the UI.

What SwiftBar costs us:

- **Colors:** SwiftBar colors only symbols written inline in the text (`:symbol:`), not images, and has no other styling.
- **Start at login:** a plugin can't change SwiftBar's own preference, so we write our own LaunchAgent.
- **No live UI:** every change re-runs a shell script and rebuilds the whole menu. There are no hover states, no buttons inside rows, no text input and no notifications.
- **Installs:** a user installs SwiftBar, then the plugin, then the hooks.
- **Refresh cost:** each refresh starts `awk`, `stat`, `tail`, `ps` and `jq` and takes about 100 ms.

## Is shell + jq maintainable?

It works, and the test suite keeps it honest. But it gets harder to maintain with every feature. The evidence from building it:

| Area | Fit | Why |
| --- | --- | --- |
| Hooks | Good | Small and stable: parse a payload, merge a few fields, write a file. Startup speed matters (budget 20 ms; now 19 to 20 ms), and a POSIX sh script with two `jq` calls meets it. No build step, and nothing to install on macOS 15+ (it ships `jq`). |
| Install and uninstall | Good | Short, linear scripts. |
| Reconciler and menu (checks C1 to C5, mutes, themes, rows) | Poor, and getting worse | The logic is about 400 lines of jq inside single-quoted shell strings, joined at run time. Quoting tricks (`'"'"'`) appear inside the jq code. jq has no types, and mistakes fail silently. We hit `label` as a reserved word, `false // true` returning `true`, and a `def` that referenced a later binding. Errors are swallowed on purpose so the menu never breaks, so a bug shows up as a wrong menu rather than an error. Mutes and themes added about 250 lines in one day. |
| Portability details | Fragile | macOS ships bash 3.2 (no negative array indexes) and BSD `stat` and `date`; awk counts bytes, not characters. Each of these cost a debugging round. |

**Can a human maintain it?** Someone fluent in jq and POSIX shell can, with the tests as a guide. But that's a rare skill combination, and the reconciler is the part most likely to change (Claude Code's hook payloads, registry and transcript format are undocumented and drift). A human reader would find the same logic much easier to follow in a typed language with a debugger and named data types.

**Conclusion:** keep shell for thin edges (install scripts, possibly a hook shim). Move the reconciler, and anything that grows, into a real language before adding the app, notifications and atm features, because each would add to the hardest part.

## The language for the core

The "core" is everything except drawing: the state model, hook handling, checks C1 to C5, mutes, filters, themes, and later the atm join and the notification rules.

| Language | Hook startup | Fit for the app UI | Notes |
| --- | --- | --- | --- |
| **Swift** | ~5 to 10 ms (native binary) | Native: the same language as the app | One language from hook to UI. Swift Package Manager builds a CLI and a library from the same code. Swift Testing and XCTest can reuse our JSON fixtures. Needs Xcode or the Command Line Tools to build. |
| Go | ~5 ms | None: the UI would still be Swift (or a Go tray library with weaker macOS integration) | A single static binary and easy CI. But two languages once the app exists. |
| Rust | ~2 to 5 ms | Only through Tauri (web UI) or bindings | Fast and safe, but the steepest learning curve, and still two languages with a Swift app. |
| Python | 50 to 100 ms | Weak (`rumps`, PyObjC) | atm is Python, but the startup cost breaks the hook budget, and shipping a Python runtime in an app is heavy. |
| TypeScript (Node, Bun) | 40 to 80 ms (Bun ~10 ms) | Only through Electron or Tauri | Familiar to the Claude Code ecosystem; heavy runtime for a menu-bar tool. |

**Recommendation: Swift.** It's the only choice where the hook, the core and a native app share one language and one test suite.

## Option A: stay a SwiftBar plugin

Unchanged from the first version of this doc. It's cheap and fully working, but it doesn't match the decisions: the audience isn't SwiftBar users, and notifications need an app. Keep it only as a stepping stone.

## Option D (new): Swift core now, SwiftBar as a thin front end

Move the logic into a Swift package before building the app, and keep the SwiftBar plugin as the first front end.

```
Package: ClaudeStatus
├── StatusCore      (library)  state model, hook event handling, checks C1–C5, mutes, filters, themes,
│                              a menu model (sorted rows with symbol, color, label, actions)
├── ccstatus        (CLI)      ccstatus hook                 ← replaces hooks/state-hook.sh
│                              ccstatus snapshot --json      ← reconciled sessions, for any reader
│                              ccstatus swiftbar             ← prints SwiftBar's format from the menu model
│                              ccstatus action mute-hour ID  ← the menu actions
└── Tests                      fixtures from tests/fixtures/ reused as Swift test inputs
```

The SwiftBar plugin file becomes one line: `exec ccstatus swiftbar`. The bats tests keep running against the CLI as end-to-end contract tests, so behavior is checked before and after the port.

| | |
| --- | --- |
| **Enables** | Typed, debuggable logic; no `jq` dependency; one process per refresh instead of five (refresh drops from about 100 ms to single-digit ms, and the hook gets more headroom); `snapshot --json` gives any future front end (the app, atm's dashboard) the same reconciled view |
| **Cost** | Medium: port about 1,100 lines of shell and jq to Swift (roughly 3 to 5 focused days, with the bats suite as the oracle); a build step; signing and notarizing the CLI binary for distribution |
| **Risks** | A build step for contributors (Xcode Command Line Tools). The hook now runs a binary that must exist at a stable path; if it's missing, hooks must still exit 0 silently (a 3-line sh shim covers this). |
| **Carries over to B** | All of it. The app links `StatusCore` directly and ships `ccstatus` inside its bundle for the hooks. |

D is not a separate destination. It's the first step of B, done in an order where the product works at every commit.

## Option B in detail: a standalone menu-bar app

### UI technology

| Choice | Pros | Cons |
| --- | --- | --- |
| **AppKit `NSStatusItem` + SwiftUI content (recommended)** | Full control of the status item: a non-template, colored image or attributed title, so colors show reliably. SwiftUI for the popover or menu rows, and for the Settings window. Mature APIs. | Two UI frameworks to know (a small AppKit layer, mostly SwiftUI) |
| SwiftUI `MenuBarExtra` (macOS 13+) | Least code; `.menuBarExtraStyle(.window)` gives a SwiftUI popover | The label is rendered as a template in practice, so colored status icons are hard; less control over click behavior and positioning |
| Tauri (Rust + web UI) | Cross-platform, web skills | A web view for a 300-pixel menu; second language; macOS integration (notifications, login items) through plugins |
| Electron | Web skills | 100+ MB for a status icon; poor fit for "minimal" |
| Go + a tray library | One small binary | Limited macOS UI; no SwiftUI views; notification and login-item support through cgo |

### Building blocks

| Need | macOS API or tool |
| --- | --- |
| Watching state files | FSEvents (or a `DispatchSource` on the directory): updates within milliseconds of a hook writing; no polling, no `swiftbar://` refresh calls |
| Process checks (C1, C4) | `libproc` (`proc_pidinfo`, `proc_listchildpids`) instead of spawning `ps` |
| Transcript tail (C3, C5) | `FileHandle` seek to the last 8 KB, and file modification times |
| Notifications | `UNUserNotificationCenter` with categories and action buttons ("Focus", "Mute 1 hour"); needs a signed app bundle |
| Start at login | `SMAppService.mainApp.register()` (macOS 13+): appears in System Settings › Login Items; no LaunchAgent file |
| Settings | A SwiftUI `Settings` scene: filters, theme with icon and color pickers (replacing hand-edited config keys), stale threshold, notification rules |
| Focus a session | `herdr agent focus` as today; later VS Code (`code` CLI or a URL scheme) and other terminals |
| Updates | Sparkle 2 (EdDSA-signed appcast on GitHub Releases) |
| Hook installation | First-run step: the app adds the hooks to `~/.claude/settings.json` (today's `install.sh` logic, backed up and reversible), pointing at `ccstatus` inside the app bundle via the shim. The Claude Code plugin route stays as an alternative. |

### Notifications

Notifications fit naturally on top of the state model:

- **When:** a session enters `waiting` (a permission prompt or a question). Optionally also `idle`, and the end of a loop when atm is integrated (C-notify below).
- **Debounce:** only after the state has lasted N seconds (default 10), so a quickly approved prompt doesn't notify.
- **Respect:** mutes (a muted project never notifies, except for waiting if you choose), the session-type filters, and macOS Focus modes (automatic).
- **Actions:** clicking focuses the session's pane; "Mute 1 hour" mutes the project.
- **Settings:** per state on or off, delay, and sound.

### Distribution

- Developer ID Application certificate, hardened runtime, `notarytool` and `stapler`, all in GitHub Actions on a macOS runner with the certificate and an App Store Connect API key as secrets.
- A DMG or zip on GitHub Releases, a Homebrew cask, and Sparkle for updates.
- Not the Mac App Store: the app must read `~/.claude`, run `herdr` and `atm`, and edit `~/.claude/settings.json`, which the App Sandbox forbids.
- Minimum macOS: 14 is a reasonable floor (SMAppService and MenuBarExtra need 13; 14 keeps the testing matrix small).

### Testing

- `StatusCore` unit tests in Swift, reusing `tests/fixtures/` (payloads and transcripts) and porting the bats cases for checks, mutes and filters.
- The bats suite stays as CLI contract tests until the SwiftBar plugin is retired.
- A small set of UI checks: snapshot tests of the row view, and a manual checklist for the status item in light and dark menu bars.

### Effort (rough)

| Step | Days |
| --- | --- |
| D: `StatusCore` + `ccstatus` CLI with the bats suite green | 3 to 5 |
| App shell: status item, popover rows, actions, FSEvents | 3 to 4 |
| Settings window, SMAppService, hook installer | 2 to 3 |
| Notifications | 1 to 2 |
| Signing, notarization, Sparkle, Homebrew cask, CI | 2 to 3 |

About 2 to 3 weeks of focused work in total, much of it suited to agent loops with the existing tests as the oracle.

## Option C in detail: atm integration

### The link

- atm's claims name the agent `claude:<first 8 characters of the session ID>`. Our state files are keyed by the full session ID, so a session and its claimed task can be joined directly. (A clash of 8 hex characters between two live sessions is negligible.)
- Each claim also records its `worktree`, which matches the session's `cwd` (or a parent of it).

### Calling atm

- `atm claims --json`: live claims (task, agent, branch, worktree, lease). About 250 ms.
- `atm status --json`: counts by status, in progress, in review, blocked, and the next task. About 230 ms.
- `atm show <id> --json`: a task's name and notes, for row titles and notifications.
- `atm paths --json`: finds the project's task folder.

At about 250 ms per call, they can't run on every refresh. Cache per project root, refresh when `.agentic-task-manager/tasks.json` changes (atm rewrites it on every status change), and otherwise every 30 seconds. In the app this runs off the main thread; with option D, `ccstatus` keeps a small cache file.

### Shapes

- **C-menu: tasks in the menu.** The row title becomes the claimed task (`api-gateway — T-012 Add rate limiting`), the row's submenu shows loop progress (`5 of 8 done`) and opens atm's dashboard (`atm serve start --open`).
- **C-attention: atm's own attention signals.** A task blocked on the user (`atm block --on user`) or waiting for review is something that needs you, like a permission prompt. It can count in the menu bar and notify.
- **C-notify: loop events.** "Loop finished: 8 of 8 done", "T-012 failed verification", "T-014 is blocked on your answer".
- **C-dashboard: sessions in atm's dashboard.** atm reads `ccstatus snapshot --json` and shows, next to each in-progress task, whether its agent is working, idle or waiting. This one lives in atm's code base.

### Risks

- atm's JSON output becomes an interface another tool depends on. Agree with atm that `claims --json` and `status --json` are stable, with a version field.
- Sessions in projects without atm, or with atm not installed, must look exactly as they do today.
- atm runs on Python 3.9+. The app should detect a missing `atm` and hide the integration rather than show errors.

## Paths compared

| | A: SwiftBar | D: Swift core + SwiftBar | B: app on the Swift core | C: atm integration |
| --- | --- | --- | --- | --- |
| Matches the decisions | No | As a step | Yes | Yes, on top of B |
| Language | sh + jq | Swift (+ sh shim) | Swift | Swift (calls atm) |
| UI ceiling | Low | Low | High | Same as its host |
| Notifications | No | No | Yes | Yes, with B |
| Refresh cost | ~100 ms, polling | single-digit ms, polling | event-driven | + cached atm calls |
| Install for users | SwiftBar + plugin + hooks | the same + a binary | one app (installs hooks) | nothing extra |
| Effort from today | none | 3 to 5 days | 2 to 3 weeks in total | 2 to 4 days on B |

## Recommendation

1. **Freeze the state file schema** (`v: 1`) and document it as a public contract. Hooks written today keep working through every step.
2. **Do D first:** port the core to Swift (`StatusCore` and the `ccstatus` CLI), with the bats suite as the oracle and SwiftBar as the throwaway front end. Stop adding features to the jq code in the meantime, except fixes.
3. **Build B on the same core:** an AppKit status item with SwiftUI rows and settings, FSEvents, `SMAppService`, notifications, Sparkle, and a first-run hook installer. Retire the SwiftBar plugin once the app does everything it does.
4. **Add C inside the app:** C-menu and C-attention first (cheapest, and they add a new kind of "needs you"), then C-notify. Propose C-dashboard to atm once `snapshot --json` exists.

If speed to a first app matters more than a working product at every step, steps 2 and 3 can merge: build `StatusCore` and the app together and skip the SwiftBar front end. The risk is losing the bats suite as an oracle partway through.

## Open questions

1. **Name and identity:** the app's name and bundle ID. "Minimalist Claude Code Statusbar" names SwiftBar's role; a standalone app may want its own name.
2. **Minimum macOS:** 14, or 13 for a wider reach?
3. **Hook in Swift or sh:** move the hook to `ccstatus hook` (no jq, faster), or keep `state-hook.sh` as the stable, dependency-light writer and port only the reader?
4. **Notification defaults:** waiting only, or idle too? Default delay before notifying?
5. **The SwiftBar plugin's future:** retire it when the app ships, or keep it as a no-app option?
6. **Distribution:** Homebrew cask from the start, or GitHub Releases with Sparkle first?
7. **atm's contract:** will atm commit to `claims --json` and `status --json` as stable, versioned output?
