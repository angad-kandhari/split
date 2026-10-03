#!/bin/sh
# Builds, signs, notarises and packages a release.
#
#   scripts/release.sh 0.1.0
#
# One-time setup:
#   - xcrun notarytool store-credentials split-notary   (Apple ID + app-specific password)
#   - the Sparkle signing key in the login keychain (created with Sparkle's generate_keys)
#   - brew install xcodegen create-dmg
#
# Set SKIP_NOTARIZE=1 to stop after signing, for a local dry run.
set -eu

VERSION=${1:?usage: scripts/release.sh <version>}
PROFILE=${NOTARY_PROFILE:-split-notary}
cd "$(dirname "$0")/.."

BUILD=$(git rev-list --count HEAD)
DIST=dist
ARCHIVE=$DIST/Split.xcarchive
APP=$DIST/export/Split.app
DMG=$DIST/Split-$VERSION.dmg
SPARKLE_BIN=$DIST/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin

rm -rf "$DIST/export" "$ARCHIVE" "$DMG" "$DIST/appcast"
mkdir -p "$DIST"

xcodegen generate
xcodebuild -project Split.xcodeproj -scheme Split -configuration Release \
    -derivedDataPath "$DIST/DerivedData" -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive
# Export re-signs Sparkle's helpers with the hardened runtime; do not sign them by hand.
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$DIST/export"
codesign --verify --deep --strict "$APP"

if [ "${SKIP_NOTARIZE:-0}" = 1 ]; then
    echo "Signed app at $APP (not notarised)."
    exit 0
fi

ditto -c -k --keepParent "$APP" "$DIST/Split.zip"
xcrun notarytool submit "$DIST/Split.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$DIST/Split.zip"

create-dmg --volname "Split" --window-size 540 380 --icon-size 110 \
    --icon "Split.app" 150 180 --app-drop-link 390 180 "$DMG" "$APP"
codesign --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

mkdir -p "$DIST/appcast"
cp "$DMG" "$DIST/appcast/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/angad-kandhari/split/releases/download/v$VERSION/" \
    "$DIST/appcast"

echo
echo "Release $VERSION is ready:"
echo "  $DMG"
echo "  $DIST/appcast/appcast.xml"
echo "Publish with:"
echo "  gh release create v$VERSION $DMG $DIST/appcast/appcast.xml --title \"Split $VERSION\""
