#!/usr/bin/env bash
# Renders the app's main screens to PNGs (dark + light) using a copy of
# your shelf. Usage: ./scripts/snapshot.sh [out-dir] [state,state…]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$(pwd)/.build/snapshots}"
STORE="$(mktemp -d)"
cp "$HOME/Library/Application Support/Shelf/"Shelf.store* "$STORE/" 2>/dev/null || true
# The real bundle, so asset-catalog colors (the accent) are present.
./scripts/bundle.sh >/dev/null
BIN="$(pwd)/dist/Shelf.app/Contents/MacOS/Shelf"
rm -rf "$OUT"; mkdir -p "$OUT"
SHELF_STORE_DIR="$STORE" SHELF_SNAPSHOT="$OUT" SHELF_SNAPSHOT_ONLY="${2:-}" "$BIN" >/dev/null 2>&1 || true
rm -rf "$STORE"
ls "$OUT"
