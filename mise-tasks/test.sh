#!/bin/sh
#MISE description="Build the Swift package and run its tests (--summary: failures and totals only)"
# Extra arguments are passed to `swift test` (e.g. --filter ConfigTests).
# --summary prints only build errors, failed checks and the totals.
cd "$(dirname "$0")/.." || exit 1

if [ "${1:-}" = "--summary" ]; then
  shift
  log="${TMPDIR:-/tmp}/asb-swift-test.$$.log"
  swift build >"$log" 2>&1 && swift test "$@" >>"$log" 2>&1
  status=$?
  grep -e "error:" -e "recorded an issue" -e "Test run with" -e "with [0-9]* test cases" "$log"
  rm -f "$log"
  exit "$status"
fi

swift build && swift test "$@"
