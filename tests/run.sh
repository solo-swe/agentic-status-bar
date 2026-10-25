#!/bin/sh
# Run the bats test suite. Extra arguments are passed to bats (e.g. a single file).
# tests/run.sh --bench runs the performance benchmark instead.
cd "$(dirname "$0")/.." || exit 1

if [ "${1:-}" = "--bench" ]; then
  exec sh tests/bench.sh
fi

if ! command -v bats >/dev/null 2>&1; then
  echo "bats is not installed. Install it with: brew install bats-core" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  exec bats "$@"
fi
exec bats tests/*.bats
