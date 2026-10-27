#!/bin/sh
# Print a Sparkle appcast with one item: the release zip, signed with the EdDSA private key.
#
#   SPARKLE_KEY_FILE=<private key file> scripts/appcast.sh <version> <build> <zip>
#
# The appcast is attached to the GitHub release; the app reads the one on the latest published release
# (SUFeedURL), so publishing a draft release is what offers the update.
set -eu
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/appcast.sh <version> <build> <zip>}"
build="${2:?usage: scripts/appcast.sh <version> <build> <zip>}"
zip="${3:?usage: scripts/appcast.sh <version> <build> <zip>}"
key="${SPARKLE_KEY_FILE:?SPARKLE_KEY_FILE must name the EdDSA private key file}"

# sign_update comes with the Sparkle package that xcodebuild resolved.
sign_update="$(find .build/release-xcode/SourcePackages/artifacts -type f -path '*/Sparkle/bin/sign_update' | head -n 1)"
[ -x "$sign_update" ] || { echo "sign_update not found: build the app first (scripts/package.sh)" >&2; exit 1; }

# Prints: sparkle:edSignature="..." length="..."
signature="$("$sign_update" --ed-key-file "$key" "$zip")"
repo="https://github.com/hakanserce/agentic-status-bar"
date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Agentic Status Bar</title>
    <link>$repo</link>
    <item>
      <title>Version $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$repo/releases/tag/v$version</sparkle:releaseNotesLink>
      <enclosure url="$repo/releases/download/v$version/$(basename "$zip")" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
EOF
