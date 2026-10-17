#!/usr/bin/env bash
# Builds Shelf.app from the Swift package: release binary + Info.plist +
# icon, ad-hoc signed. Usage: ./scripts/bundle.sh [--install]
# UNIVERSAL=1 builds for both Apple silicon and Intel (for releases).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Shelf.app"

# Always Xcode's toolchain: open-source ones (swiftly, swift.org) lack the
# SwiftData/SwiftUI macros and MapKit overlays this app needs.
SWIFT=(xcrun swift)

ARCHS=()
[[ "${UNIVERSAL:-}" == "1" ]] && ARCHS=(--arch arm64 --arch x86_64)

echo "→ Building release binary"
"${SWIFT[@]}" build -c release --product Shelf ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$("${SWIFT[@]}" build -c release --product Shelf ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Shelf"

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
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  # Only the installed copy should appear in launchers; the build copy in
  # dist/ would otherwise compete with it (and keep a stale icon around).
  "$LSREGISTER" -u "$APP" || true
  touch /Applications/Shelf.app
  "$LSREGISTER" -f /Applications/Shelf.app
  /System/Library/CoreServices/pbs -update || true
  open /Applications/Shelf.app
else
  echo "✓ Built $APP — run with: open \"$APP\""
fi
