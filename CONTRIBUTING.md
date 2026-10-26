# Contributing

## Requirements

- macOS 14 or later, Xcode 16 or later (Swift 6)
- `brew install xcodegen` for the app
- `brew install shellcheck` for `tests/lint.sh`

## Checks

```sh
tests/swift.sh             # build the Swift package and run its tests (or: tests/swift.sh --filter ConfigTests)
tests/swift.sh --summary   # the same, printing only failures and totals
tests/app.sh --test        # generate the app's Xcode project, build it and run the app's tests
tests/lint.sh              # shellcheck on the shell scripts (tests/*.sh, scripts/*.sh)
tests/bench.sh             # timing: asb hook < 10 ms, asb snapshot < 30 ms on 10 sessions
```

CI runs the same commands, in three jobs: lint, the Swift package, and the app. Tests run in a temporary `HOME`, so
they never touch your real `~/.claude` or config.

The hook runs on every tool call of every session; run `tests/bench.sh` after changing it.

## Layout

| Path | What |
| --- | --- |
| `Sources/ASBCore/` | The logic, Foundation only: state files, hook events, checks C1–C5, mutes, themes, the menu model, config, install |
| `Sources/asb/` | The `asb` CLI: `hook`, `snapshot`, `action`, `install`, `uninstall` |
| `App/` | The macOS app: `project.yml` (XcodeGen), `Sources/`, `Tests/` |
| `tests/ASBCoreTests/` | Swift Testing tests for `ASBCore` |
| `tests/conformance/` | The snapshot engine's behavior as data: input files and the expected snapshot (see its README) |
| `tests/fixtures/` | Captured Claude Code hook payloads and transcripts (see its README) |
| `scripts/package.sh` | Builds, signs, notarizes and packages a release (see `scripts/notarize.md`) |
| `doc/PRD.md` | Product requirements |
| `doc/state-file-schema.md`, `doc/snapshot-schema.md` | The file and snapshot formats |
| `doc/design/future-architecture.md` | The design behind the move to Swift and the app |

The app links `ASBCore` from the Swift package and shows what `Engine.snapshot` returns; the hook (`asb hook`) and
the app only share the state files and the config file. Keep logic in `ASBCore`, where it is tested without a UI;
the app's views read view models (`RowItem`, `StatusItemController.presentation`, `NotificationRules`) that have
their own tests.

## The app

The app's Xcode project is generated from `App/project.yml` and isn't committed. `tests/app.sh` generates it; then
open `App/AgenticStatusBar.xcodeproj` to work in Xcode. A build copies a release build of `asb` into
`Contents/Helpers`, which the app installs for the hooks. Builds land in `.build/xcode`.

```sh
tests/app.sh --run                          # build and start it (quitting a running copy first)
tests/app.sh --run ASB_SETTINGS=/tmp/s.json # with environment overrides, e.g. a scratch settings file
tests/app.sh --quit                         # quit it
```

Environment overrides, for the app and `asb`: `ASB_STATE_DIR`, `ASB_CONFIG`, `ASB_REGISTRY_DIR`, `ASB_SETTINGS`
(Claude Code's settings file), `ASB_HERDR`, `ASB_SWIFTBAR_DIR` (where `asb install` looks for an old SwiftBar link)
and `ASB_PS_TABLE` (a fake process table, for tests).

## Trying `asb`

```sh
swift build -c release
.build/release/asb install          # the hooks (backs up ~/.claude/settings.json)
.build/release/asb snapshot --json --pretty
```

State files appear in `~/.claude/agentic-status-bar/`, one per session. `asb uninstall` removes what `asb install`
added.

## Releases

Push a tag such as `v0.2.0`: `.github/workflows/release.yml` builds, signs and notarizes the app and attaches
`agentic-status-bar-<version>.zip` and `.dmg` to a draft GitHub release, which you publish. The one-time signing
setup and the secrets it needs are in [scripts/notarize.md](scripts/notarize.md). `scripts/package.sh 0.0.0` makes
an unsigned dry run locally.
