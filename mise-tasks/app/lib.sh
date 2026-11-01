#!/bin/sh
# Shared by the app tasks (build, test, run, quit): sourced, not a task itself (not executable).
# Generates the app's Xcode project and builds it, unsigned (ad-hoc).
cd "$(dirname "$0")/../.." || exit 1

bundle_id="com.hakanserce.agentic-status-bar"
app=".build/xcode/Build/Products/Debug/Agentic Status Bar.app"

generate() {
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed. Install it with: mise install" >&2
    exit 1
  fi
  xcodegen generate --spec App/project.yml --quiet || exit 1
}

build() {
  xcodebuild -project App/AgenticStatusBar.xcodeproj -scheme AgenticStatusBar -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode "$@"
}

quit_app() {
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1
}

open_app() {
  open -n "$app" "$@"
}
