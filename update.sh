#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl dpkg

set -euo pipefail

FLAKE_NIX="$(cd "$(dirname "$0")" && pwd)/flake.nix"
DEB_URL="https://boosteroid.com/linux/installer/boosteroid-install-x64.deb"
MD5_URL="https://boosteroid.com/linux/installer/boosteroid-install-x64.md5"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CURRENT_VERSION=$(grep 'version = ' "$FLAKE_NIX" | head -1 | sed 's/.*version = "\(.*\)".*/\1/')

echo "Checking upstream version..."
MD5_LINE=$(curl -sL --user-agent 'Mozilla/5.0' "$MD5_URL")
UPSTREAM_MD5=$(echo "$MD5_LINE" | awk '{print $1}')
# Extract version from filename: Boosteroid-1.10.12-x86_64.deb -> 1.10.12
UPSTREAM_VERSION=$(echo "$MD5_LINE" | sed 's/.*Boosteroid-\([0-9.]*\)-x86_64\.deb/\1/')

if [ -z "$UPSTREAM_VERSION" ] || [ -z "$UPSTREAM_MD5" ]; then
  echo "Error: could not parse .md5 file" >&2
  exit 1
fi

echo "Upstream: $UPSTREAM_VERSION  Current: $CURRENT_VERSION"

# The .md5 filename has no -beta suffix; strip it from current for comparison
if [ "$UPSTREAM_VERSION" = "${CURRENT_VERSION%-beta}" ]; then
  echo "Already up to date."
  exit 0
fi

echo "New version detected, downloading installer..."
curl -L --user-agent 'Mozilla/5.0' -o "$TMP/boosteroid.deb" "$DEB_URL"

echo "Verifying MD5..."
ACTUAL_MD5=$(md5sum "$TMP/boosteroid.deb" | awk '{print $1}')
if [ "$ACTUAL_MD5" != "$UPSTREAM_MD5" ]; then
  echo "Error: MD5 mismatch (expected $UPSTREAM_MD5, got $ACTUAL_MD5)" >&2
  exit 1
fi
echo "MD5 OK"

# .deb control file has the canonical version string (may include -beta)
DEB_VERSION=$(dpkg-deb --field "$TMP/boosteroid.deb" Version)
HASH=$(nix hash file --sri --type sha256 "$TMP/boosteroid.deb")

CURRENT_HASH=$(grep 'hash = ' "$FLAKE_NIX" | head -1 | sed 's/.*hash = "\(.*\)".*/\1/')

sed -i "s|version = \"$CURRENT_VERSION\"|version = \"$DEB_VERSION\"|" "$FLAKE_NIX"
sed -i "s|hash = \"$CURRENT_HASH\"|hash = \"$HASH\"|" "$FLAKE_NIX"

echo "Updated: $CURRENT_VERSION -> $DEB_VERSION"
echo "Hash:    $HASH"
