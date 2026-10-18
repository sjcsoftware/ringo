#!/bin/zsh
# Builds Ringo.app (GUI + bundled `ringo` CLI) into ./dist. Needs only the Xcode Command Line Tools.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
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
cp "$BIN/RingoApp" "$APP/Contents/MacOS/Ringo"
cp "$BIN/ringo" "$APP/Contents/Helpers/ringo"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp .build/checkouts/swift-argument-parser/LICENSE.txt "$APP/Contents/Resources/ArgumentParser-LICENSE.txt"
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

echo "→ Signing (ad hoc, hardened runtime)…"
codesign --force --options runtime --sign - "$APP/Contents/Helpers/ringo"
codesign --force --options runtime --entitlements Resources/Ringo.entitlements --sign - "$APP"
codesign --verify --strict "$APP"

echo "✓ Built $APP"
echo "  Run the app:  open $APP"
echo "  Run the CLI:  $APP/Contents/Helpers/ringo --help"
