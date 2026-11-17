#!/bin/zsh
# Builds Ringo.app (GUI + bundled `ringo` CLI) into ./dist. Needs only the Xcode Command Line Tools.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
SIGNING_IDENTITY="${RINGO_SIGN_IDENTITY:--}"
VERSION="$(sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' Sources/RingoEngine/RingoEngine.swift)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/Ringo.app"

echo "→ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --product RingoApp
swift build -c "$CONFIG" --product ringo
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN/RingoApp" "$APP/Contents/MacOS/Ringo"
cp "$BIN/ringo" "$APP/Contents/Helpers/ringo"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp .build/checkouts/swift-argument-parser/LICENSE.txt "$APP/Contents/Resources/ArgumentParser-LICENSE.txt"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
if [[ ! -f build/AppIcon.icns ]]; then
  echo "→ Rendering icon…"
  swift scripts/make-icon.swift "$ICONSET" >/dev/null
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "→ Generating shell completions…"
mkdir -p "$APP/Contents/Resources/completions"
for sh in zsh bash fish; do
  "$APP/Contents/Helpers/ringo" --generate-completion-script $sh > "$APP/Contents/Resources/completions/ringo.$sh"
done

echo "→ Signing (hardened runtime)…"
mkdir -p build
SIGNING_ENTITLEMENTS="build/Ringo-signing.entitlements"
cp Resources/Ringo.entitlements "$SIGNING_ENTITLEMENTS"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  # Ad hoc signatures have no Team ID, so library validation cannot match the
  # embedded Sparkle framework. Developer ID builds retain library validation.
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$SIGNING_ENTITLEMENTS"
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$SPARKLE/Updater.app"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$SPARKLE/Autoupdate"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ringo"
codesign --force --options runtime --entitlements "$SIGNING_ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ Built $APP"
echo "  Run the app:  open $APP"
echo "  Run the CLI:  $APP/Contents/Helpers/ringo --help"
