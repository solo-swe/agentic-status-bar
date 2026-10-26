#!/bin/sh
# Generate the app's Xcode project and build it (unsigned, ad-hoc), or with --test, run its tests.
# Needs XcodeGen: brew install xcodegen
cd "$(dirname "$0")/.." || exit 1

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec App/project.yml --quiet || exit 1

action="build"
[ "${1:-}" = "--test" ] && action="test"
xcodebuild -project App/AgenticStatusBar.xcodeproj -scheme AgenticStatusBar -configuration Debug \
  -derivedDataPath .build/xcode -quiet "$action"
