#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-universal-app.sh"
APP="$ROOT/.build/universal/Relay.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG_STAGE="$(mktemp -d "$ROOT/.build/relay-dmg.XXXXXX")"
trap 'rm -rf "$DMG_STAGE"' EXIT
ditto "$APP" "$DMG_STAGE/Relay.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$ROOT/Resources/DMG/Install Relay.txt" "$DMG_STAGE/Install Relay.txt"
cp "$ROOT/.build/Relay.icns" "$DMG_STAGE/.VolumeIcon.icns"
xcrun SetFile -a C "$DMG_STAGE"
mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/Relay-$APP_VERSION-universal.dmg"
hdiutil create -volname "Relay $APP_VERSION" -srcfolder "$DMG_STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
hdiutil verify "$DMG"
(
  cd "$ROOT/dist"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)
echo "Installer ready: $DMG"
