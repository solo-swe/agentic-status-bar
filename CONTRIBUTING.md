# Contributing

## Requirements

- macOS 14 or later, and the Xcode named in `.xcode-version` (CI builds with that one)
- [mise](https://mise.jdx.dev) for the other tools, at the versions in `mise.toml` (XcodeGen for the app, shellcheck
  for linting): `brew install mise`, then `mise trust` and `mise install` in the clone

## Checks

The checks are mise tasks, scripts in `mise-tasks/` (`mise tasks` lists them):

```sh
mise run check             # everything CI runs: lint, test, coverage and app:test, in parallel
mise run test              # build the Swift package and run its tests (or: mise run test --filter ConfigTests)
mise run test --summary    # the same, printing only failures and totals
mise run app:test          # generate the app's Xcode project, build it and run the app's tests
mise run lint              # shellcheck on the shell scripts (mise-tasks/, scripts/)
mise run coverage          # line coverage of Sources/ASBCore and Sources/asb; fails below 99% (or: coverage 95)
mise run bench             # timing: asb hook < 10 ms, asb snapshot < 30 ms on 10 sessions
```

CI runs the same tasks, in three jobs: lint, the Swift package, and the app. A change is done when `mise run check`
passes. Tests run in a temporary `HOME`, so
they never touch your real `~/.claude` or config.

The hook runs on every tool call of every session; run `mise run bench` after changing it.

Coverage leaves out files named `*Darwin.swift`. Each holds only code a test can't run, and nothing else:

| File | Why tests can't run it |
| --- | --- |
| `Sources/ASBCore/ProcessesDarwin.swift` | The real process table (libproc, sysctl); tests use `FakeProcessInspector` or `ASB_PS_TABLE` |
| `Sources/ASBCore/SwiftBarDarwin.swift` | Reads SwiftBar's own preferences with `defaults`; tests pass a preference to `swiftBarDir(environment:home:preference:)` |
| `Sources/asb/CommandsDarwin.swift` | The commands' `run()` entry points: the process's real environment, stdin, stdout and terminal; tests call the `run` overloads with a temporary home |

The `@main` entry point (`Sources/asb/ASB.swift`) has no lines to count. Coverage runs the tests one at a time
(`--no-parallel`): the counters aren't atomic, and parallel tests make the counts vary between runs.

## Layout

| Path | What |
| --- | --- |
| `Sources/ASBCore/` | The logic, Foundation only: state files, hook events, checks C1–C6, mutes, themes, the menu model, config, install |
| `Sources/asb/` | The `asb` CLI: `hook`, `snapshot`, `action`, `install`, `uninstall` |
| `App/` | The macOS app: `project.yml` (XcodeGen), `Sources/`, `Tests/` |
| `tests/ASBCoreTests/` | Swift Testing tests for `ASBCore` |
| `tests/asbTests/` | Swift Testing tests for the `asb` commands, run against a temporary home |
| `tests/conformance/` | The snapshot engine's behavior as data: input files and the expected snapshot (see its README) |
| `tests/fixtures/` | Captured Claude Code hook payloads and transcripts (see its README) |
| `mise.toml`, `mise-tasks/` | The pinned development tools and the checks as mise tasks (`doc/design/dev-tooling.md`) |
| `mise-tasks/release/` | `release:package`, `release:appcast`, `release:cask`: build, sign, notarize and package a release; its update feed; its Homebrew cask (see `doc/RELEASING.md`) |
| `scripts/` | Swift helper scripts: the Sparkle key check, the icon and the social preview |
| `doc/README.md` | Index of the documents |
| `doc/guides/` | How code is written here: Swift, the app, the hook, shell scripts |
| `doc/PRD.md` | Product requirements |
| `doc/RELEASING.md` | How releases are built, signed, published and delivered |
| `doc/state-file-schema.md`, `doc/snapshot-schema.md` | The file and snapshot formats |
| `doc/design/future-architecture.md` | The design behind the move to Swift and the app |

The app links `ASBCore` from the Swift package and shows what `Engine.snapshot` returns; the hook (`asb hook`) and
the app only share the state files and the config file. Keep logic in `ASBCore`, where it is tested without a UI;
the app's views read view models (`RowItem`, `StatusItemController.presentation`, `NotificationRules`) that have
their own tests.

## The app

The app's Xcode project is generated from `App/project.yml` and isn't committed. `mise run app:build` generates it; then
open `App/AgenticStatusBar.xcodeproj` to work in Xcode. A build copies a release build of `asb` into
`Contents/Helpers`, which the app installs for the hooks. Builds land in `.build/xcode`.

```sh
mise run app:run                            # build and start it (quitting a running copy first)
mise run app:run ASB_SETTINGS=/tmp/s.json   # with environment overrides, e.g. a scratch settings file
mise run app:quit                           # quit it
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

In short: set `ASBVersion.current` (and `MARKETING_VERSION`), push a `v<version>` tag, check the draft release the
workflow makes, and publish it as the latest release. Publishing offers the update to installed apps and updates the
Homebrew tap. [doc/RELEASING.md](doc/RELEASING.md) has the whole process: how it flows, the one-time setup with every
secret, a checklist, how to check a release, what to do when a step fails, and replacing keys.

`mise run release:package 0.0.0` makes an unsigned dry run locally.
