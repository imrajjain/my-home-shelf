#!/usr/bin/env bash
# Builds a universal Shelf.app and zips it for a GitHub release.
# Usage: ./scripts/release.sh  →  dist/Shelf-<version>.zip
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)"
ZIP="dist/Shelf-$VERSION.zip"

UNIVERSAL=1 ./scripts/bundle.sh
rm -f "$ZIP"
# ditto keeps the bundle's signature and metadata intact (zip -r doesn't).
ditto -c -k --sequesterRsrc --keepParent dist/Shelf.app "$ZIP"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
