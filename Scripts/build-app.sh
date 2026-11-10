#!/usr/bin/env bash
# Builds build/MacStatus.app (menu-bar-only app bundle, ad-hoc signed).
#   Scripts/build-app.sh            # release build
#   Scripts/build-app.sh debug      # debug build
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacStatus"

APP="build/MacStatus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacStatus"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The app icon is drawn by the app itself (Views/AppLogo.swift), so it can never drift from the popup's logo.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --icon "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Ad-hoc signature: enough to run locally and to register "Launch at Login".
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with:  open $APP"
