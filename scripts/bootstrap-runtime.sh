#!/bin/bash
# Download an unmodified official release, verified against the upstream SHA-256.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="5.0.1"
case "$(uname -m)" in
  arm64) ARCH="aarch64"; SHA="33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b" ;;
  x86_64) ARCH="x86_64"; SHA="31a5467a9e907f162b093267cbbab1276b15c6e709c2ea8159566a8d165beb50" ;;
  *) echo "Unsupported Mac architecture." >&2; exit 1 ;;
esac
RUNTIME="$ROOT/.runtime"
mkdir -p "$RUNTIME/bin"
ARCHIVE="$RUNTIME/scrcpy.tar.gz"
if [[ ! -f "$ARCHIVE" ]] || [[ "$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)" != "$SHA" ]]; then
  curl --proto '=https' --tlsv1.2 -fL --retry 2 "https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/scrcpy-macos-$ARCH-v$VERSION.tar.gz" -o "$ARCHIVE"
fi
if [[ "$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)" != "$SHA" ]]; then
  echo "Runtime verification failed. No executable was installed." >&2
  exit 1
fi
tar -xzf "$ARCHIVE" -C "$RUNTIME/bin" --strip-components=1
echo "Verified scrcpy $VERSION ($ARCH), including ADB."
