#!/usr/bin/env bash
# Builds the app with SwiftPM and wraps it in a runnable .build/TronIPTV.app (ad-hoc signed, not sandboxed).
# A fast inner loop that works with only the Command Line Tools; release builds use Xcode (see CONTRIBUTING.md).
#   scripts/dev-app.sh          build and open
#   scripts/dev-app.sh --no-open
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/fetch-vlckit.sh" >/dev/null

swift build --product TronIPTV
BIN="$(swift build --show-bin-path)"
APP="$ROOT/.build/TronIPTV.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/TronIPTV" "$APP/Contents/MacOS/TronIPTV"
rsync -a --delete "$ROOT/Frameworks/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/TronIPTV" 2>/dev/null || true

VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
sed -e "s/\$(MARKETING_VERSION)/${VERSION:-0.0.0-dev}/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/1/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/mk.troniptv.app.dev/" \
    -e "s/\$(EXECUTABLE_NAME)/TronIPTV/" \
    -e "s/\$(PRODUCT_NAME)/TronIPTV/" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/" \
    -e "s/\$(DEVELOPMENT_LANGUAGE)/en/" \
    "$ROOT/App/Info.plist" > "$APP/Contents/Info.plist"
if [[ -f "$ROOT/App/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
if [[ "${1:-}" != "--no-open" ]]; then
  open "$APP"
fi
