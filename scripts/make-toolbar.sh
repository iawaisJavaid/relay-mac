#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" clang -dynamiclib -fobjc-arc -framework Cocoa -framework UniformTypeIdentifiers \
  -mmacosx-version-min=14.0 "$ROOT/Resources/Toolbar/RelayToolbar.m" -o "$ROOT/.build/libRelayToolbar.dylib"
codesign --force --sign - "$ROOT/.build/libRelayToolbar.dylib"
