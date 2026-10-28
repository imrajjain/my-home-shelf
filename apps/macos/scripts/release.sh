#!/usr/bin/env bash
# Builds a universal Shelf.app, signs it for Sparkle and publishes it on
# GitHub Releases with an updated appcast, so installed copies update
# themselves.
#
#   ./scripts/release.sh 0.2.0            build + sign + appcast in dist/
#   ./scripts/release.sh 0.2.0 --publish  …and create the GitHub release
#
# Needs the Sparkle signing key in your login keychain (one-time setup):
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account shelf
# and its public key in Support/Info.plist (SUPublicEDKey).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
PLIST=Support/Info.plist
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
REPO=imrajjain/my-home-shelf

if [[ -z "$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" "$PLIST")" ]]; then
  echo "✗ SUPublicEDKey is empty in $PLIST. Run generate_keys first (see the top of this script)." >&2
  exit 1
fi

# Version: the marketing number you pass, and a build number that always grows.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD" "$PLIST"

UNIVERSAL=1 ./scripts/bundle.sh

UPDATES=dist/updates
mkdir -p "$UPDATES"
ZIP="$UPDATES/Shelf-$VERSION.zip"
# Only the newest release goes in the feed: older downloads live under their
# own tags, so one URL prefix can't describe them all.
rm -f "$UPDATES"/*.zip "$UPDATES"/*.delta
# ditto keeps the bundle's signature and metadata intact (zip -r doesn't).
ditto -c -k --sequesterRsrc --keepParent dist/Shelf.app "$ZIP"

# The appcast describes the release in dist/updates, signed with the EdDSA
# key from the keychain, pointing at its download on GitHub.
"$SPARKLE_BIN/generate_appcast" --account shelf \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  -o "$UPDATES/appcast.xml" "$UPDATES"

echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1)), build $BUILD, appcast at $UPDATES/appcast.xml"

if [[ "$PUBLISH" == "--publish" ]]; then
  # The feed lives at releases/latest/download/appcast.xml, so the newest
  # release always carries it.
  # Shelf.zip: a fixed name, for the one-line installer (…/latest/download/Shelf.zip).
  cp "$ZIP" "$UPDATES/Shelf.zip"
  gh release create "v$VERSION" "$ZIP" "$UPDATES/Shelf.zip" "$UPDATES/appcast.xml" -R "$REPO" \
    --title "Shelf $VERSION" --generate-notes
  echo "✓ Published v$VERSION — installed copies will pick it up within a day, or via Shelf ▸ Check for Updates…"

  # Homebrew: point the cask at this release.
  SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
  CASK="../../packaging/homebrew/Casks/shelf.rb"
  sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
  TAP="$(mktemp -d)"
  if gh repo clone imrajjain/homebrew-tap "$TAP" -- -q 2>/dev/null; then
    mkdir -p "$TAP/Casks" && cp "$CASK" "$TAP/Casks/shelf.rb"
    git -C "$TAP" add Casks/shelf.rb
    git -C "$TAP" commit -qm "Shelf $VERSION" && git -C "$TAP" push -q
    echo "✓ Homebrew tap updated: brew upgrade --cask shelf"
  else
    echo "• Homebrew tap not found (imrajjain/homebrew-tap); skipped." >&2
  fi
  rm -rf "$TAP"
fi
