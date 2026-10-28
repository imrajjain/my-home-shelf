#!/bin/bash
# Installs Shelf into /Applications.
#
#   curl -fsSL https://gentle-water-02c5bb500.5.azurestaticapps.net/install.sh | bash
#
# It downloads the latest release from GitHub, replaces any older copy and
# opens it. Shelf then keeps itself up to date.
set -euo pipefail

REPO="imrajjain/my-home-shelf"
APP="/Applications/Shelf.app"

if [[ "$(uname)" != "Darwin" ]]; then echo "Shelf is a Mac app." >&2; exit 1; fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 14 )); then echo "Shelf needs macOS 14 (Sonoma) or later." >&2; exit 1; fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Shelf…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/Shelf.zip" -o "$tmp/Shelf.zip"
ditto -x -k "$tmp/Shelf.zip" "$tmp"
[[ -d "$tmp/Shelf.app" ]] || { echo "The download didn't contain Shelf.app." >&2; exit 1; }

if [[ -d "$APP" ]]; then
  osascript -e 'tell application "Shelf" to quit' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$APP"
fi
mv "$tmp/Shelf.app" "$APP"
# Not notarized by Apple (that needs a paid developer account): clear the
# download mark so macOS opens it without stopping.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Shelf is in your Applications folder. Opening it…"
open "$APP"
