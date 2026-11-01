# Shell scripts

The scripts in `tests/` (checks) and `scripts/` (packaging, the appcast, the Homebrew cask). Logic belongs in Swift;
scripts glue tools together.

- **POSIX `sh`** (`#!/bin/sh`), no Bash-only features. They run on macOS runners and developer Macs alike.
- **shellcheck clean** at warning level: `tests/lint.sh` runs `shellcheck -x -S warning -s sh` on every script, and CI
  fails on any finding. A `# shellcheck disable=` needs the reason on the same line.
- **Start from the repository root**: `cd "$(dirname "$0")/.." || exit 1`, so a script works from anywhere.
- **A comment at the top** says what the script does and its arguments.
- **Check for tools** before using them, and say how to install a missing one (`brew install xcodegen`).
- **Quote every expansion** (`"$f"`, `"$@"`); exit with the status of what failed.
- **Quiet by default**: print failures and totals, not full logs (`--summary`, the log filtered with `grep`); temp
  files go in `${TMPDIR:-/tmp}` and are removed.
- **Secrets only from the environment** the workflow provides; never echo them, never write them into the repository.
