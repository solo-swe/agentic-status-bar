# Contributing

## Requirements

- macOS 15 or later (or Homebrew `jq`)
- `brew install bats-core shellcheck`
- Xcode 16 or later (Swift 6) for the Swift package

## Checks

```sh
tests/lint.sh          # shellcheck on every script
tests/run.sh           # all bats tests (or: tests/run.sh tests/hook.bats)
tests/run.sh --bench   # timing against the PRD targets (plugin < 150 ms, hook < 20 ms)
tests/swift.sh         # build the Swift package and run its tests (or: tests/swift.sh --filter VersionTests)
```

The Swift package (`Package.swift`: `ASBCore`, the `asb` CLI, tests in `tests/ASBCoreTests`) is replacing the
shell code; see `doc/design/future-architecture.md`.

The hook runs on every tool call and the plugin every few seconds, so both keep process
counts low: the hook makes two jq calls per event, and a plugin refresh does all parsing,
checks and rendering in one jq program. Check `--bench` after changing either.

CI runs the same commands (lint and bats in one job, Swift in another). Tests run in a temporary `HOME`, so they never touch your real
`~/.claude` or config.

Verify behavior with a bats test rather than by hand. `tests/test_helper.bash` provides:

- `stub_command NAME [BODY]`: a fake command on `PATH` that records its arguments.
- `stub_ps` and `add_process`: a fake process table for the PID walk and liveness checks.
- `run_hook FIXTURE`: feeds `tests/fixtures/payloads/FIXTURE.json` to the hook.

Payload fixtures and what they showed are described in `tests/fixtures/README.md`.

## Trying the hooks in Claude Code

Load the repo as a plugin for one session:

```sh
claude --plugin-dir .
```

State files then appear in `~/.claude/swiftbar-claudecode-minimal/`, one per session. Your existing hooks keep
running alongside.

## Layout

| Path | What |
| --- | --- |
| `hooks/state-hook.sh` | The hook: one state file per session |
| `hooks/hooks.json` | Hook registrations for the Claude Code plugin |
| `swiftbar/swiftbar-claudecode-minimal.5s.sh` | The SwiftBar plugin |
| `lib/common.sh` | Config, time and file helpers shared by both |
| `doc/PRD.md` | Product requirements |
