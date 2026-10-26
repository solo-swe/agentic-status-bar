#!/bin/sh
# Generate the app's Xcode project and build it (unsigned, ad-hoc), or with --test, run its tests.
# Needs XcodeGen: brew install xcodegen
cd "$(dirname "$0")/.." || exit 1

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec App/project.yml --quiet || exit 1

build() {
  xcodebuild -project App/AgenticStatusBar.xcodeproj -scheme AgenticStatusBar -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode "$@"
}

app=".build/xcode/Build/Products/Debug/Agentic Status Bar.app"

case "${1:-}" in
  --quit)
    # Quit a running copy started by --run.
    osascript -e 'tell application id "com.hakanserce.agentic-status-bar" to quit' >/dev/null 2>&1
    exit 0
    ;;
  --run)
    # Build, then start the app (quitting a running copy first). Extra KEY=VALUE arguments are
    # passed to it as environment variables, e.g. ASB_STATE_DIR=/path/to/fixture.
    shift
    build -quiet build || exit 1
    osascript -e 'tell application id "com.hakanserce.agentic-status-bar" to quit' >/dev/null 2>&1
    sleep 1
    for pair in "$@"; do set -- "$@" --env "$pair"; shift; done
    open -n "$app" "$@"
    exit $?
    ;;
  --test) ;;
  *)
    build -quiet build
    exit $?
    ;;
esac

# Tests: print only failures and the totals.
log="${TMPDIR:-/tmp}/asb-app-test.$$.log"
build test >"$log" 2>&1
status=$?
grep -e "\.swift:[0-9]*:[0-9]*: error:" -e "failed (" -e "Executed [0-9]* test" -e "TEST SUCCEEDED" -e "TEST FAILED" "$log"
rm -f "$log"
exit "$status"
