#!/usr/bin/env bash
# Builds Shelf.app from the Swift package: release binary + Info.plist +
# icon, ad-hoc signed. Usage: ./scripts/bundle.sh [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Shelf.app"

# Always Xcode's toolchain: open-source ones (swiftly, swift.org) lack the
# SwiftData/SwiftUI macros and MapKit overlays this app needs.
SWIFT=(xcrun swift)

echo "→ Building release binary"
"${SWIFT[@]}" build -c release --product Shelf
BIN="$("${SWIFT[@]}" build -c release --product Shelf --show-bin-path)/Shelf"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shelf"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

echo "→ Compiling icon (Liquid Glass + .icns fallback)"
# Support/Shelf.icon is an Icon Composer document: vector layers that macOS
# renders as glass, with dark and tinted variants. actool also writes a flat
# Shelf.icns for older systems.
xcrun actool "$ROOT/Support/Shelf.icon" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon Shelf \
  --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null

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
