# Developer tooling: mise for tools and tasks

Status (2026-11-01): **decided**; the tools and Xcode are pinned (T-152), the tasks are next (sprint Quality).

## Decisions

1. **mise pins the tools.** `mise.toml` at the root lists every tool the checks need, at exact versions: `xcodegen` and
   `shellcheck` now; `tmux`, `zellij`, `bun`, `swiftformat`, `xcbeautify` when a task first needs one. CI installs the
   same versions with `jdx/mise-action`, so a Homebrew or runner update can't change a result without a commit.
   `min_version` in `mise.toml` and the action's `version` pin mise itself.
2. **mise runs the tasks.** The scripts become mise file tasks in `mise-tasks/`, and `mise run <task>` is the one way
   to run a check, locally, in CI and for agents. `mise tasks` lists them with their descriptions.
3. **The scripts stay POSIX `sh`.** A file task is an executable script with `#MISE` and `#USAGE` header comments;
   mise drops the `.sh` from the name (`mise-tasks/lint.sh` is `lint`, `mise-tasks/app/test.sh` is `app:test`). They
   stay shellcheck clean and run directly too. Nothing is rewritten.
4. **Xcode is pinned too.** A committed `.xcode-version` names the Xcode CI selects, instead of the newest one on the
   runner. mise doesn't manage Xcode or the Swift toolchain on macOS.
5. **Only development changes.** Users install the app as before; the PRD's "no Homebrew" is about running the app.
   Contributors install mise once (`brew install mise`), then `mise trust` and `mise install` in the clone.

## Why

The project is about to grow (`agent-providers.md`, `focus-targets.md`):

- Integration tests against tmux, WezTerm and Zellij in CI, where behavior depends on the version.
- Plugin files in JS/TS run by Bun (opencode, Amp): a second language to lint and test.
- More checks (coverage, integration, maybe formatting) and one command that runs what CI runs.
- Agents that work through tasks need one stable, listed command surface.

Today every CI job runs `brew install` without a version and selects the newest Xcode (the same line in three jobs),
and each script checks for its own tools.

## Options considered

| Option | Verdict | Why |
| --- | --- | --- |
| **mise** | **Chosen** | Pins versions and runs tasks, in one tool; file tasks keep our `sh` scripts. Tuist does the same: its `mise.toml` pins `swiftlint`, `swiftformat`, `xcodes`, `node` and more, and its tasks are shell scripts in `mise/tasks/`. |
| Shell scripts only | Kept inside mise | No way to pin versions; discovery depends on docs; every combination is another script. swift-nio runs on a `scripts/` folder, but with the Swift team's CI matrix pinning toolchains. |
| Makefile | Discarded | A list of phony targets in practice (swift-composable-architecture's targets are `xcodebuild`, `format`, …); SwiftPM and `xcodebuild` already build incrementally; flags are awkward (`ARGS=…`); macOS ships GNU Make 3.81; no version pinning. |
| just | Discarded | The best command syntax, but no version pinning, so two tools; rare in Swift projects. |
| Taskfile | Discarded | Checksum-based up-to-date checks, which mise tasks have too (`sources`, `outputs`); verbose YAML; no version pinning. |
| Tuist (instead of XcodeGen) | Later | Worth it when the app splits into several modules; one app target and one test target don't need it. |
| Bazel, fastlane, SwiftPM command plugins | Discarded | Bazel is for very large monorepos; fastlane brings Ruby while `package.sh` already works; command plugins are sandboxed and slow, and poor at running `xcodebuild`. |

## Layout

| Task | File | Was |
| --- | --- | --- |
| `lint` | `mise-tasks/lint.sh` | `tests/lint.sh` |
| `test` | `mise-tasks/test.sh` (`--summary`, `--filter <suite>`) | `tests/swift.sh` |
| `app:build`, `app:test`, `app:run`, `app:quit` | `mise-tasks/app/*.sh` (shared code in a non-executable `mise-tasks/app/lib.sh`) | `tests/app.sh` and its flags |
| `bench` | `mise-tasks/bench.sh` | `tests/bench.sh` |
| `coverage` | `mise-tasks/coverage.sh` | new (T-147) |
| `check` | `mise.toml` (`depends` on `lint`, `test`, `app:test`, `coverage`) | new |
| `release:package`, `release:appcast`, `release:cask` | `mise-tasks/release/*.sh` | `scripts/package.sh`, `appcast.sh`, `homebrew-cask.sh` (a later task) |

`tests/` keeps the tests, fixtures and conformance cases; `scripts/` keeps the Swift helper scripts. Tasks run from the
repository root, which mise sets as their working directory.

## Open points

- The release scripts move last, in their own task, checked with an unsigned `release:package 0.0.0` dry run.
- The agents' permission allowlist (`.claude/settings.json`) moves from script paths to `mise run *`; the user makes
  that change.

## References

- mise file tasks: https://mise.jdx.dev/tasks/file-tasks.html
- mise registry: https://mise.jdx.dev/registry.html
- jdx/mise-action: https://github.com/jdx/mise-action
- Tuist `mise.toml`: https://github.com/tuist/tuist/blob/main/mise.toml, tasks: https://github.com/tuist/tuist/tree/main/mise/tasks
- swift-composable-architecture Makefile: https://github.com/pointfreeco/swift-composable-architecture/blob/main/Makefile
- swift-nio scripts: https://github.com/apple/swift-nio/tree/main/scripts
