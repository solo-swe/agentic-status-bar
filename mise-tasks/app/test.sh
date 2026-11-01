#!/bin/sh
#MISE description="Build the app and run its tests, printing only failures and the totals"
# shellcheck source=mise-tasks/app/lib.sh
. "$(dirname "$0")/lib.sh"

generate
log="${TMPDIR:-/tmp}/asb-app-test.$$.log"
build test >"$log" 2>&1
status=$?
grep -e "\.swift:[0-9]*:[0-9]*: error:" -e "failed (" -e "Executed [0-9]* test" -e "TEST SUCCEEDED" -e "TEST FAILED" "$log"
rm -f "$log"
exit "$status"
