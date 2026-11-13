#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/bootstrap-runtime.sh"
"$ROOT/scripts/make-toolbar.sh"
"$ROOT/scripts/swift.sh" build -c release
BIN_DIR="$("$ROOT/scripts/swift.sh" build -c release --show-bin-path)"
STAGING="$(mktemp -d "$ROOT/.build/relay-package.XXXXXX")"
APP="$STAGING/Relay.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/runtime"
cp "$BIN_DIR/Relay" "$APP/Contents/MacOS/Relay"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/.runtime/bin/adb" "$ROOT/.runtime/bin/scrcpy" "$ROOT/.runtime/bin/scrcpy-server" "$ROOT/.runtime/bin/LICENSE" "$ROOT/.runtime/bin/scrcpy.png" "$ROOT/.runtime/bin/disconnected.png" "$APP/Contents/Resources/runtime/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
cp "$ROOT/.build/libRelayToolbar.dylib" "$APP/Contents/Resources/runtime/"
"$ROOT/scripts/make-icon.sh"
cp "$ROOT/.build/Relay.icns" "$APP/Contents/Resources/Relay.icns"
# Local ad-hoc signing; no developer account is necessary to use your own build.
codesign --force --sign - "$APP/Contents/Resources/runtime/adb"
codesign --force --sign - "$APP/Contents/Resources/runtime/scrcpy"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/dist"
# Replace the bundle by renaming, without rewriting executables that might still
# be mapped by a running copy of Relay or the shared ADB daemon.
if [[ -d "$ROOT/dist/Relay.app" ]]; then
  PREVIOUS="$(mktemp -d "$ROOT/.build/relay-previous.XXXXXX")"
  mv "$ROOT/dist/Relay.app" "$PREVIOUS/Relay.app"
fi
mv "$APP" "$ROOT/dist/Relay.app"
rmdir "$STAGING"
APP="$ROOT/dist/Relay.app"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Relay-macOS-$(uname -m).zip"
echo "Built $APP"
