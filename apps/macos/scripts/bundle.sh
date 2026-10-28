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
# Sparkle, the updater, ships inside the app.
mkdir -p "$APP/Contents/Frameworks"
SPARKLE="$(dirname "$BIN")/Sparkle.framework"
[[ -d "$SPARKLE" ]] || SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
# Museum collections (data only; the scans load from Wikimedia on first look).
cp -R "$ROOT/Support/Museum" "$APP/Contents/Resources/Museum"

echo "→ Compiling icon (Liquid Glass + .icns fallback)"
# Support/Shelf.icon is an Icon Composer document: vector layers that macOS
# renders as glass, with dark and tinted variants. actool also writes a flat
# Shelf.icns for older systems.
xcrun actool "$ROOT/Support/Shelf.icon" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon Shelf \
  --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null

# One stable identity for every build, so macOS (keychain access) and Sparkle
# see each update as the same app. It's a self-signed certificate in the
# login keychain; without it, builds fall back to an ad hoc signature.
IDENTITY="${SHELF_SIGN_IDENTITY:-Shelf Code Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  echo "→ Signing as \"$IDENTITY\""
  codesign --force --deep --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "→ Signing (ad hoc: no \"$IDENTITY\" certificate in the keychain)"
  codesign --force --deep --sign - "$APP"
fi

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
