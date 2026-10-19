#!/usr/bin/env bash
# Downloads the official VLCKit binary (LGPL-2.1) from VideoLAN into Frameworks/, verifying its SHA-256.
# The framework is ~400 MB, so it is not committed; CI and fresh clones run this once.
set -euo pipefail

VERSION="3.7.3-319ed2c0-79128878"
SHA256="019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d"
URL="https://download.videolan.org/pub/cocoapods/prod/VLCKit-${VERSION}.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Frameworks"
STAMP="$DEST/.vlckit-version"

if [[ -d "$DEST/VLCKit.xcframework" && "$(cat "$STAMP" 2>/dev/null)" == "$VERSION" ]]; then
  echo "VLCKit $VERSION already present."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading VLCKit $VERSION…"
curl --fail --location --silent --show-error --retry 3 --output "$WORK/vlckit.tar.xz" "$URL"
echo "$SHA256  $WORK/vlckit.tar.xz" | shasum -a 256 --check --status || {
  echo "error: VLCKit checksum mismatch" >&2
  exit 1
}

tar -xf "$WORK/vlckit.tar.xz" -C "$WORK"
mkdir -p "$DEST"
rm -rf "$DEST/VLCKit.xcframework"
mv "$WORK/VLCKit - binary package/VLCKit.xcframework" "$DEST/"
cp "$WORK/VLCKit - binary package/COPYING.txt" "$DEST/VLCKit-COPYING.txt"
echo "$VERSION" > "$STAMP"
echo "VLCKit installed in $DEST"
