#!/bin/bash
# Build a portable macOS 14+ app for both Apple silicon and Intel.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="5.0.1"
cd "$ROOT"

fetch_runtime() {
  local runtime_arch="$1" upstream_arch="$2" expected_sha="$3"
  local runtime_dir="$ROOT/.runtime/$runtime_arch"
  local archive="$runtime_dir/scrcpy.tar.gz"
  mkdir -p "$runtime_dir/bin"
  if [[ ! -f "$archive" ]] || [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$expected_sha" ]]; then
    if [[ -f "$ROOT/.runtime/scrcpy.tar.gz" ]] && [[ "$(shasum -a 256 "$ROOT/.runtime/scrcpy.tar.gz" | cut -d ' ' -f 1)" == "$expected_sha" ]]; then
      cp "$ROOT/.runtime/scrcpy.tar.gz" "$archive"
    else
      curl --proto '=https' --tlsv1.2 -fL --retry 2 \
        "https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/scrcpy-macos-$upstream_arch-v$VERSION.tar.gz" -o "$archive"
    fi
  fi
  if [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$expected_sha" ]]; then
    echo "Runtime verification failed for $runtime_arch." >&2; exit 1
  fi
  tar -xzf "$archive" -C "$runtime_dir/bin" --strip-components=1
  echo "Verified scrcpy $VERSION ($runtime_arch)."
}

fetch_runtime arm64 aarch64 33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b
fetch_runtime x86_64 x86_64 31a5467a9e907f162b093267cbbab1276b15c6e709c2ea8159566a8d165beb50

for build_arch in arm64 x86_64; do
  "$ROOT/scripts/swift.sh" build -c release --triple "$build_arch-apple-macosx14.0"
done
ARM_BIN="$("$ROOT/scripts/swift.sh" build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/Relay"
INTEL_BIN="$("$ROOT/scripts/swift.sh" build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/Relay"
STAGING="$(mktemp -d "$ROOT/.build/relay-universal.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Relay.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/runtime"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/Relay"
lipo -create "$ROOT/.runtime/arm64/bin/scrcpy" "$ROOT/.runtime/x86_64/bin/scrcpy" -output "$APP/Contents/Resources/runtime/scrcpy"
cp "$ROOT/.runtime/arm64/bin/adb" "$ROOT/.runtime/arm64/bin/scrcpy-server" \
  "$ROOT/.runtime/arm64/bin/LICENSE" "$ROOT/.runtime/arm64/bin/scrcpy.png" \
  "$ROOT/.runtime/arm64/bin/disconnected.png" "$APP/Contents/Resources/runtime/"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" clang -dynamiclib -fobjc-arc \
  -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -Wl,-install_name,@rpath/libRelayToolbar.dylib \
  -framework Cocoa -framework UniformTypeIdentifiers \
  "$ROOT/Resources/Toolbar/RelayToolbar.m" -o "$APP/Contents/Resources/runtime/libRelayToolbar.dylib"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
if [[ ! -f "$ROOT/.build/Relay.icns" ]]; then "$ROOT/scripts/make-icon.sh"; fi
cp "$ROOT/.build/Relay.icns" "$APP/Contents/Resources/Relay.icns"

for executable in "$APP/Contents/MacOS/Relay" "$APP/Contents/Resources/runtime/adb" \
  "$APP/Contents/Resources/runtime/scrcpy" "$APP/Contents/Resources/runtime/libRelayToolbar.dylib"; do
  lipo "$executable" -verify_arch arm64 x86_64
done
for helper in adb scrcpy libRelayToolbar.dylib; do
  codesign --force --sign - "$APP/Contents/Resources/runtime/$helper"
done
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/.build/universal"
if [[ -d "$ROOT/.build/universal/Relay.app" ]]; then
  mv "$ROOT/.build/universal/Relay.app" "$STAGING/PreviousRelay.app"
fi
mv "$APP" "$ROOT/.build/universal/Relay.app"
echo "Built universal app: $ROOT/.build/universal/Relay.app"
