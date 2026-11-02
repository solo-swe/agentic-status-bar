#!/bin/sh
#MISE description="Line coverage of Sources/ASBCore and Sources/asb, per file and in total; fails below the threshold (default 99)"
# Runs the package tests with coverage on and reports line coverage of the package's sources (not the
# tests, not the app) with llvm-cov. The first argument is the threshold in percent (default 99).
# Files named *Darwin.swift hold only code tests can't run (CONTRIBUTING.md › Checks) and are left out.
# The tests run one at a time: the coverage counters aren't atomic, so tests running in parallel lose
# increments, and the counts llvm-cov derives from them can then show a line as run or missed at random.
cd "$(dirname "$0")/.." || exit 1

threshold="${1:-99}"
log="${TMPDIR:-/tmp}/asb-coverage.$$.log"

if ! swift test --enable-code-coverage --no-parallel >"$log" 2>&1; then
  grep -e "error:" -e "recorded an issue" -e "Test run with" "$log"
  rm -f "$log"
  echo "coverage: the tests failed" >&2
  exit 1
fi
rm -f "$log"

bin="$(swift build --show-bin-path)"
report="$(xcrun llvm-cov report "$bin/AgenticStatusBarPackageTests.xctest/Contents/MacOS/AgenticStatusBarPackageTests" \
  -instr-profile "$bin/codecov/default.profdata" -ignore-filename-regex 'Darwin\.swift$' Sources/ASBCore Sources/asb)" || exit 1
echo "$report"

# The TOTAL row's line coverage: the 10th column (Lines, Missed Lines, Cover come 8th to 10th).
total="$(echo "$report" | awk '$1 == "TOTAL" { sub("%", "", $10); print $10 }')"
if [ -z "$total" ]; then
  echo "coverage: no TOTAL line in the llvm-cov report" >&2
  exit 1
fi
if awk -v total="$total" -v threshold="$threshold" 'BEGIN { exit !(total >= threshold) }'; then
  echo "coverage ok: $total% of lines (threshold $threshold%)"
else
  echo "coverage FAIL: $total% of lines, below $threshold%" >&2
  exit 1
fi
