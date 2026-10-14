#!/usr/bin/env bash
# Renders the browser extension's toolbar icons from Support/Shelf.icon,
# so they always match the app. Usage: ./scripts/extension_icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
xcrun actool Support/Shelf.icon --compile "$TMP" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon Shelf --output-partial-info-plist "$TMP/p.plist" >/dev/null
iconutil -c iconset "$TMP/Shelf.icns" -o "$TMP/Shelf.iconset"
OUT=../../extensions/browser/icons
for size in 16 32 48 128; do
  sips -z $size $size "$TMP/Shelf.iconset/icon_128x128@2x.png" --out "$OUT/icon-$size.png" >/dev/null
done
rm -rf "$TMP"
echo "Wrote $OUT/icon-{16,32,48,128}.png"
