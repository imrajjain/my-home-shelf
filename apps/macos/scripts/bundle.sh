#!/usr/bin/env bash
# Builds Shelf.app from the Swift package: release binary + Info.plist +
# icon, ad-hoc signed. Usage: ./scripts/bundle.sh [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Shelf.app"

echo "→ Building release binary"
swift build -c release --product Shelf
BIN="$(swift build -c release --product Shelf --show-bin-path)/Shelf"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shelf"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Support/AppIcon.png" ]]; then
  echo "→ Making icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ROOT/Support/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ROOT/Support/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "→ Signing (ad hoc)"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "→ Installing to /Applications"
  rm -rf "/Applications/Shelf.app"
  cp -R "$APP" /Applications/
  # Register the URL scheme and Services menu entry.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Shelf.app
  /System/Library/CoreServices/pbs -update || true
  open /Applications/Shelf.app
else
  echo "✓ Built $APP — run with: open \"$APP\""
fi
