#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/.build/Relay.iconset"
mkdir -p "$ICONSET"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" swift "$ROOT/scripts/draw-icon.swift" "$ROOT/.build/Relay-1024.png"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/.build/Relay-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/.build/Relay-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
# Store PNG representations in a standard ICNS container. This also works in
# build environments where iconutil's image-conversion service is unavailable.
python3 - "$ICONSET" "$ROOT/.build/Relay.icns" <<'PY'
import pathlib
import struct
import sys

source, output = map(pathlib.Path, sys.argv[1:])
entries = [
    (b'icp4', 'icon_16x16.png'),
    (b'icp5', 'icon_32x32.png'),
    (b'icp6', 'icon_32x32@2x.png'),
    (b'ic07', 'icon_128x128.png'),
    (b'ic08', 'icon_256x256.png'),
    (b'ic09', 'icon_512x512.png'),
    (b'ic10', 'icon_512x512@2x.png'),
    (b'ic11', 'icon_16x16@2x.png'),
    (b'ic12', 'icon_32x32@2x.png'),
    (b'ic13', 'icon_128x128@2x.png'),
    (b'ic14', 'icon_256x256@2x.png'),
]
chunks = []
for kind, filename in entries:
    png = (source / filename).read_bytes()
    chunks.append(struct.pack('>4sI', kind, len(png) + 8) + png)
payload = b''.join(chunks)
output.write_bytes(struct.pack('>4sI', b'icns', len(payload) + 8) + payload)
PY
