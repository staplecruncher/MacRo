#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/MacRo.app"
DMG_PATH="$ROOT_DIR/dist/MacRo.dmg"
STAGING_DIR="$ROOT_DIR/dist/dmg-staging"
APPLICATIONS_LINK="$STAGING_DIR/Applications"

"$ROOT_DIR/Scripts/package_app.sh"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/MacRo.app"
ln -s /Applications "$APPLICATIONS_LINK"

hdiutil create \
  -volname "MacRo" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${MACRO_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$MACRO_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

rm -rf "$STAGING_DIR"
echo "Packaged: $DMG_PATH"
