# Contributing

## Requirements

- macOS 14 or later, Xcode 16 or later (Swift 6)
- `brew install bats-core shellcheck` for the end-to-end tests

## Checks

```sh
tests/swift.sh             # build the Swift package and run its tests (or: tests/swift.sh --filter ConfigTests)
tests/swift.sh --summary   # the same, printing only failures and totals
tests/run.sh               # build asb, then the bats end-to-end tests (or: tests/run.sh tests/hook.bats)
tests/lint.sh              # shellcheck on the shell scripts left (the SwiftBar plugin, test scripts)
tests/run.sh --bench       # timing: plugin < 150 ms, asb hook < 10 ms, asb snapshot < 30 ms
```

The Swift package (`Package.swift`): `ASBCore` (the logic, Foundation only), the `asb` CLI, and tests in
`tests/ASBCoreTests`. The conformance cases in `tests/conformance/` pin the snapshot engine's behavior as data (see
their README); the bats tests check `asb` end to end through the SwiftBar plugin and `asb hook`.

The hook runs on every tool call and the plugin every few seconds; check `--bench` after changing either.

CI runs the same commands (lint and bats in one job, Swift in another). Tests run in a temporary `HOME`, so they
never touch your real `~/.claude` or config.

`tests/test_helper.bash` provides:

- `stub_command NAME [BODY]`: a fake command on `PATH` that records its arguments.
- `stub_ps` and `add_process`: a fake process table (`asb` reads it through `ASB_PS_TABLE`).
- `run_hook FIXTURE`: feeds `tests/fixtures/payloads/FIXTURE.json` to `asb hook`.

Payload fixtures and what they showed are described in `tests/fixtures/README.md`.

## Trying it

```sh
swift build -c release
.build/release/asb install          # hooks + SwiftBar link (backs up ~/.claude/settings.json)
.build/release/asb snapshot --json --pretty
```

State files appear in `~/.claude/agentic-status-bar/`, one per session. `asb uninstall` removes everything
`asb install` added.

## Layout

| Path | What |
| --- | --- |
| `Sources/ASBCore/` | State files, checks C1–C5, mutes, themes, menu model, hook events, install |
| `Sources/asb/` | The CLI: `hook`, `snapshot`, `swiftbar`, `action`, `install`, `uninstall` |
| `swiftbar/agentic-status-bar.5s.sh` | The SwiftBar plugin: runs `asb swiftbar` and `asb action` |
| `doc/PRD.md` | Product requirements |
| `doc/state-file-schema.md`, `doc/snapshot-schema.md` | The file and snapshot formats |
| `doc/design/future-architecture.md` | Where this is going |
