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

1. Set the version in `Sources/ASBCore/Version.swift` (`ASBVersion.current`): it is the version of `asb`, of the app
   and of the tag. A signed build refuses a tag that doesn't match it. Set `MARKETING_VERSION` in `App/project.yml`
   to the same, for builds made in Xcode.
2. Commit, then push a tag: `git tag -a v0.2.0 -m v0.2.0 && git push origin v0.2.0`.
3. `.github/workflows/release.yml` builds, signs and notarizes the app, signs the update with the Sparkle key, and
   attaches `agentic-status-bar-<version>.zip`, `.dmg` and `appcast.xml` to a draft GitHub release.
4. Check the draft (`scripts/notarize.md` › Checking a release), edit its notes, and publish it as the latest release
   (not a pre-release). Installed apps find the update in the appcast of the latest published release, so publishing
   is what offers it.
5. Publishing also runs `.github/workflows/homebrew.yml`, which points the cask in
   [solo-swe/homebrew-tap](https://github.com/solo-swe/homebrew-tap) at the new zip (`scripts/homebrew-cask.sh`), pushing
   with the deploy key in `HOMEBREW_TAP_DEPLOY_KEY`. To redo it for a release, run the workflow by hand with its tag.

`scripts/package.sh 0.0.0` makes an unsigned dry run locally; builds without `SPARKLE_PUBLIC_KEY` don't update
themselves.

### One-time setup

- The Developer ID certificate and the notarization key: [scripts/notarize.md](scripts/notarize.md).
- The Sparkle update key, an EdDSA pair. Build the app once (`scripts/package.sh 0.0.0`) so Sparkle's tools are
  downloaded, then:

  ```sh
  bin=.build/release-xcode/SourcePackages/artifacts/sparkle/Sparkle/bin
  $bin/generate_keys                     # creates the key pair in your login keychain
  $bin/generate_keys -x sparkle.key
  gh secret set SPARKLE_ED_PRIVATE_KEY < sparkle.key
  gh variable set SPARKLE_PUBLIC_KEY --body "$($bin/generate_keys -p)"
  rm sparkle.key
  ```

  Set the variable from `generate_keys -p`, which prints only the key: the first command prints it inside an
  Info.plist snippet, and a stray `<string>` character breaks the release's key check.

  `generate_keys` keeps the private key in your login keychain; back it up. Losing it means installed copies can't
  update to a release signed with a new key.
