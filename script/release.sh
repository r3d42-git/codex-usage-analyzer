#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: ./script/release.sh VERSION}"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Team ID.}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Usage Analyzer"
ARCHIVE_PATH="$ROOT_DIR/.release/$APP_NAME.xcarchive"
RELEASE_DIR="$ROOT_DIR/.release/$VERSION"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
DMG_NAME="Codex-Usage-Analyzer-$VERSION-mac-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
STAGE_DIR="$RELEASE_DIR/stage"

rm -rf "$ARCHIVE_PATH" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR" "$STAGE_DIR"

swift test -c release
xcodebuild \
  -project "$ROOT_DIR/CodexUsageAnalyzer.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  ARCHS=arm64 \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  archive

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "Release artifact: $DMG_PATH"
