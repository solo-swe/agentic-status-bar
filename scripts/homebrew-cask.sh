#!/bin/sh
# Print the Homebrew cask for a release, for the tap solo-swe/homebrew-tap (Casks/agentic-status-bar.rb).
#
#   scripts/homebrew-cask.sh <version> <sha256 of agentic-status-bar-<version>.zip>
#
# .github/workflows/homebrew.yml runs it when a release is published and pushes the result to the tap.
set -eu

version="${1:?usage: scripts/homebrew-cask.sh <version> <sha256>}"
sha256="${2:?usage: scripts/homebrew-cask.sh <version> <sha256>}"

cat <<EOF
cask "agentic-status-bar" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/solo-swe/agentic-status-bar/releases/download/v#{version}/agentic-status-bar-#{version}.zip"
  name "Agentic Status Bar"
  desc "Menu bar status for Claude Code sessions"
  homepage "https://github.com/solo-swe/agentic-status-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself with Sparkle.
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Agentic Status Bar.app"

  # Remove the Claude Code hooks while the app is still there; state and config stay (zap removes them).
  uninstall quit:   "com.hakanserce.agentic-status-bar",
            script: {
              executable: "#{appdir}/Agentic Status Bar.app/Contents/Helpers/asb",
              args:       ["uninstall"],
            }

  zap trash: [
    "~/.claude/agentic-status-bar",
    "~/.config/agentic-status-bar",
    "~/Library/Application Support/agentic-status-bar",
    "~/Library/Caches/com.hakanserce.agentic-status-bar",
    "~/Library/HTTPStorages/com.hakanserce.agentic-status-bar",
    "~/Library/Preferences/com.hakanserce.agentic-status-bar.plist",
  ]
end
EOF
