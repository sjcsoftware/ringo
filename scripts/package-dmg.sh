#!/bin/zsh
# Build and package a release app with a drag-to-Applications installer.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release
APP="dist/Ringo.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
DMG="dist/Ringo-$VERSION-$ARCH.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/ringo-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/Ringo.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/LICENSE"
hdiutil create -volname Ringo -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
echo "✓ Created $DMG"
