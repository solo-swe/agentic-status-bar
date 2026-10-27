#!/bin/sh
# Build the app for release, sign it and the embedded asb, notarize and staple, and package
# dist/agentic-status-bar-<version>.zip (only the .app) and dist/agentic-status-bar-<version>.dmg.
#
#   scripts/package.sh <version>
#
# IDENTITY: the signing identity, default "-" (ad-hoc: no notarization, for a local dry run).
# With a Developer ID identity, notarization needs NOTARY_KEY (path of the .p8 API key),
# NOTARY_KEY_ID and NOTARY_ISSUER. See scripts/notarize.md.
# SPARKLE_PUBLIC_KEY: the EdDSA public key built into the app, so it can update itself (empty: no updates).
set -eu
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/package.sh <version>}"
identity="${IDENTITY:--}"

# One version for the app, asb and the tag: ASBVersion.current. A signed release must match it.
source_version="$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/ASBCore/Version.swift)"
if [ "$identity" != "-" ] && [ "$version" != "$source_version" ]; then
  echo "Version $version doesn't match ASBVersion.current ($source_version) in Sources/ASBCore/Version.swift" >&2
  exit 1
fi
# A signed release updates itself: it needs both halves of the Sparkle key.
if [ "$identity" != "-" ] && { [ -z "${SPARKLE_PUBLIC_KEY:-}" ] || [ ! -s "${SPARKLE_KEY_FILE:-}" ]; }; then
  echo "A signed release needs SPARKLE_PUBLIC_KEY and SPARKLE_KEY_FILE (CONTRIBUTING.md › Releases)" >&2
  exit 1
fi
if [ -n "${SPARKLE_PUBLIC_KEY:-}" ] && [ -s "${SPARKLE_KEY_FILE:-}" ]; then
  swift scripts/check-sparkle-key.swift "$SPARKLE_KEY_FILE" "$SPARKLE_PUBLIC_KEY"
fi
name="agentic-status-bar-$version"
dist="dist"
derived=".build/release-xcode"
app="$derived/Build/Products/Release/Agentic Status Bar.app"

xcodegen generate --spec App/project.yml --quiet
# Built ad-hoc; signed below, so asb is signed before the app that contains it.
xcodebuild -project App/AgenticStatusBar.xcodeproj -scheme AgenticStatusBar -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$derived" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" CODE_SIGN_IDENTITY=- \
  -quiet build
if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
  plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$app/Contents/Info.plist"
fi

# Extra codesign options (--preserve-metadata=...) come after the path.
sign() {
  path="$1"
  shift
  if [ "$identity" = "-" ]; then
    codesign --force --sign - "$@" "$path"
  else
    codesign --force --options runtime --timestamp --sign "$identity" "$@" "$path"
  fi
}

# Inside out: Sparkle's helpers, the framework, asb, then the app (Sparkle's documented order).
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle/XPCServices/Installer.xpc"
sign "$sparkle/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign "$app/Contents/Helpers/asb"
sign "$app"
codesign --verify --strict --deep --verbose=1 "$app"

notarize() {
  if [ "$identity" = "-" ]; then
    echo "Ad-hoc signed: skipping notarization of $1"
    return
  fi
  xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
}

rm -rf "$dist"
mkdir -p "$dist"

# The app: zip for notarization, staple the ticket to the app, zip again for the release.
ditto -c -k --keepParent "$app" "$dist/$name.zip"
notarize "$dist/$name.zip"
if [ "$identity" != "-" ]; then
  xcrun stapler staple "$app"
  rm "$dist/$name.zip"
  ditto -c -k --keepParent "$app" "$dist/$name.zip"
fi

# The disk image: the app and a link to Applications.
staging="$derived/dmg"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$app" "$staging/Agentic Status Bar.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Agentic Status Bar" -srcfolder "$staging" -format UDZO -ov "$dist/$name.dmg"
sign "$dist/$name.dmg"
notarize "$dist/$name.dmg"
if [ "$identity" != "-" ]; then
  xcrun stapler staple "$dist/$name.dmg"
fi

echo "Packaged $dist/$name.zip and $dist/$name.dmg"

# The appcast, when there's a key to sign the update with.
if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
  scripts/appcast.sh "$version" "${BUILD_NUMBER:-1}" "$dist/$name.zip" > "$dist/appcast.xml"
  echo "Wrote $dist/appcast.xml"
fi
