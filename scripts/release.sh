#!/usr/bin/env bash
# Builds a release with Xcode.
#
#   scripts/release.sh dmg <version> [build]        Developer ID signed, notarized and stapled DMG in build/dist
#   scripts/release.sh appstore <version> [build]   Archive and upload to App Store Connect (TestFlight)
#
# Requirements: Xcode, XcodeGen (brew install xcodegen), and signing credentials:
#   APPLE_TEAM_ID                     10-character Team ID
#   Notarization / upload, either an App Store Connect API key (recommended, used by CI):
#     ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to the AuthKey_XXXX.p8 file)
#   or a keychain profile created once with `xcrun notarytool store-credentials TronIPTV`:
#     NOTARY_PROFILE=TronIPTV          (DMG only)
# The certificates ("Developer ID Application", "Apple Distribution", "3rd Party Mac Developer Installer")
# must be in the keychain (set DEVELOPER_ID to the full identity name if you have several); Xcode's automatic signing creates provisioning profiles as needed.
set -euo pipefail

MODE="${1:?usage: release.sh dmg|appstore <version> [build]}"
VERSION="${2:?version required, e.g. 0.1.0}"
BUILD="${3:-$(git rev-list --count HEAD)}"
TEAM="${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
cd "$ROOT"

"$ROOT/scripts/fetch-vlckit.sh"
xcodegen generate --quiet

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

archive() {
  local config="$1" archive="$2"
  xcodebuild archive \
    -project TronIPTV.xcodeproj -scheme TronIPTV -configuration "$config" \
    -destination "generic/platform=macOS" -archivePath "$archive" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" DEVELOPMENT_TEAM="$TEAM" \
    -allowProvisioningUpdates "${AUTH[@]}" | xcbeautify_or_cat
}

xcbeautify_or_cat() {
  if command -v xcbeautify >/dev/null; then xcbeautify --quiet; else cat; fi
}

options_plist() {
  local method="$1" dest="$2" file="$3"
  cat > "$file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$method</string>
  <key>destination</key><string>$dest</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
}

notarize_only() {
  local file="$1"
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    xcrun notarytool submit "$file" --wait --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
  else
    xcrun notarytool submit "$file" --wait --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE or ASC_KEY_ID}"
  fi
}

notarize() {
  notarize_only "$1"
  xcrun stapler staple "$1"
}

rm -rf "$OUT"
mkdir -p "$OUT/dist"

case "$MODE" in
  dmg)
    archive Release "$OUT/TronIPTV.xcarchive"
    options_plist developer-id export "$OUT/ExportOptions.plist"
    xcodebuild -exportArchive -archivePath "$OUT/TronIPTV.xcarchive" -exportPath "$OUT/export" \
      -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates "${AUTH[@]}"
    APP="$OUT/export/TronIPTV.app"

    # Notarize the app itself first so it is stapled inside the DMG as well.
    ditto -c -k --keepParent "$APP" "$OUT/TronIPTV.zip"
    notarize_only "$OUT/TronIPTV.zip"
    xcrun stapler staple "$APP"

    DMG="$OUT/dist/TronIPTV-$VERSION-macOS.dmg"
    STAGE="$OUT/dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp LICENSE THIRD-PARTY-NOTICES.md "$STAGE/"
    hdiutil create -volname "TronIPTV $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
    codesign --sign "${DEVELOPER_ID:-Developer ID Application}" --timestamp "$DMG"
    notarize "$DMG"

    (cd "$OUT/dist" && shasum -a 256 ./*.dmg > SHA256SUMS.txt)
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    echo "DMG ready: $DMG"
    ;;

  appstore)
    archive AppStore "$OUT/TronIPTV-AppStore.xcarchive"
    options_plist app-store-connect upload "$OUT/ExportOptions-AppStore.plist"
    xcodebuild -exportArchive -archivePath "$OUT/TronIPTV-AppStore.xcarchive" -exportPath "$OUT/appstore" \
      -exportOptionsPlist "$OUT/ExportOptions-AppStore.plist" -allowProvisioningUpdates "${AUTH[@]}"
    echo "Uploaded build $VERSION ($BUILD) to App Store Connect. It appears in TestFlight after processing."
    ;;

  *)
    echo "unknown mode $MODE (use dmg or appstore)" >&2
    exit 1
    ;;
esac
