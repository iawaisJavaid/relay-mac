#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/make-toolbar.sh"
clang -fobjc-arc -framework Cocoa -Wl,-export_dynamic "$ROOT/scripts/verify-toolbar-bridge.m" -o "$ROOT/.build/verify-toolbar-bridge"
"$ROOT/.build/verify-toolbar-bridge" "$ROOT/.build/libRelayToolbar.dylib"
