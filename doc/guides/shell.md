# Shell scripts

The scripts in `mise-tasks/` (the checks, as mise tasks: `doc/design/dev-tooling.md`) and `scripts/` (packaging, the
appcast, the Homebrew cask). Logic belongs in Swift; scripts glue tools together.

- **POSIX `sh`** (`#!/bin/sh`), no Bash-only features. They run on macOS runners and developer Macs alike.
- **shellcheck clean** at warning level: `mise run lint` runs `shellcheck -x -S warning -s sh` on every script, and CI
  fails on any finding. A `# shellcheck disable=` needs the reason on the same line.
- **A task is an executable script** in `mise-tasks/` with a `#MISE description="…"` line: `mise-tasks/app/test.sh`
  is the task `app:test`. Code shared by tasks goes in a non-executable file they source (`mise-tasks/app/lib.sh`).
  Arguments reach the script as `"$@"`.
- **Start from the repository root**: `cd "$(dirname "$0")/.." || exit 1` (one `..` per folder level), so a script
  also works when run directly, from anywhere.
- **A comment at the top** says what the script does and its arguments.
- **Tools come from `mise.toml`**, at pinned versions; a new tool is added there. A script that needs one checks for
  it and says `mise install` when it's missing.
- **Quote every expansion** (`"$f"`, `"$@"`); exit with the status of what failed.
- **Quiet by default**: print failures and totals, not full logs (`--summary`, the log filtered with `grep`); temp
  files go in `${TMPDIR:-/tmp}` and are removed.
- **Secrets only from the environment** the workflow provides; never echo them, never write them into the repository.
