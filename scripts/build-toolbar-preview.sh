#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/make-toolbar.sh"
APP="$ROOT/.build/RelayToolbarPreview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
clang -fobjc-arc -framework Cocoa "$ROOT/scripts/toolbar-preview.m" -o "$APP/Contents/MacOS/RelayToolbarPreview"
cp "$ROOT/.build/libRelayToolbar.dylib" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RelayToolbarPreview</string>
<key>CFBundleIdentifier</key><string>local.relay.toolbar-preview</string>
<key>CFBundleName</key><string>Relay Toolbar Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
