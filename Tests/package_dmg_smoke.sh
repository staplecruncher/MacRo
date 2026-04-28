#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT_DIR/dist/MacRo.dmg"
APP_BINARY="$ROOT_DIR/dist/MacRo.app/Contents/MacOS/MacRo"
APP_INFO="$ROOT_DIR/dist/MacRo.app/Contents/Info.plist"
APP_ICON="$ROOT_DIR/dist/MacRo.app/Contents/Resources/AppIcon.icns"

rm -f "$DMG_PATH"
"$ROOT_DIR/Scripts/package_dmg.sh"
test -f "$DMG_PATH"
test -f "$APP_ICON"
test "$(plutil -extract CFBundleIconFile raw -o - "$APP_INFO")" = "AppIcon.icns"

if [[ "$(uname -m)" == "arm64" ]]; then
  lipo -info "$APP_BINARY" | rg -q 'arm64.*x86_64|x86_64.*arm64'
else
  lipo -info "$APP_BINARY" | rg -q 'x86_64'
fi
