#!/bin/bash
# Build, sign, notarize, and package MacTyper as a DMG.
#
# One-time setup (requires an Apple Developer ID):
#   1. Install your "Developer ID Application: ..." certificate in Keychain.
#   2. xcrun notarytool store-credentials mactyper-notary \
#        --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>
#   3. Set SIGN_IDENTITY below (or export it).
#
# Without a Developer ID this script still produces an UNSIGNED dmg
# (ad-hoc signature); users must right-click → Open past Gatekeeper.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=MacTyper
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | awk '{print $2}' | tr -d '"')
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mactyper-notary}"
OUT=build/release

xcodegen generate
rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild -project $APP.xcodeproj -scheme $APP -configuration Release \
  -derivedDataPath build archive -archivePath "$OUT/$APP.xcarchive" \
  ${SIGN_IDENTITY:+CODE_SIGN_IDENTITY="$SIGN_IDENTITY"} \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="${TEAM_ID:-}"

APP_PATH="$OUT/$APP.xcarchive/Products/Applications/$APP.app"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime \
    --entitlements MacTyper/Resources/MacTyper.entitlements \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$OUT/$APP.zip"
  xcrun notarytool submit "$OUT/$APP.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
fi

# DMG
DMG="$OUT/$APP-$VERSION.dmg"
STAGE="$OUT/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --sign "$SIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built: $DMG"
echo "Publish with: gh release create v$VERSION $DMG --title 'MacTyper $VERSION'"
