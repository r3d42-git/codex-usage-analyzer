#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: ./script/release.sh VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Team ID.}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity.}"
: "${NOTARY_PROFILE:=codex-usage-analyzer.notary}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ "$(git branch --show-current)" == main ]] || { echo 'Release requires main' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the intended changes before release' >&2; exit 1; }
python3 - "$VERSION" <<'PY'
import re,sys,pathlib
versions=re.findall(r'MARKETING_VERSION = ([^;]+);',pathlib.Path('CodexUsageAnalyzer.xcodeproj/project.pbxproj').read_text())
assert versions and set(versions)=={sys.argv[1]}, 'Xcode version must match release version'
PY
APP_NAME="Codex Usage Analyzer"
RELEASE_DIR="$ROOT_DIR/.release/$VERSION"
[[ ! -e "$RELEASE_DIR" ]] || { echo "Release directory already exists: $RELEASE_DIR" >&2; exit 1; }
# Validate credentials before spending time on a build. No credentials are modified.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
mkdir -p "$RELEASE_DIR/stage"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
DMG_NAME="Codex-Usage-Analyzer-$VERSION-mac-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
STAGE_DIR="$RELEASE_DIR/stage"
git rev-parse HEAD > "$RELEASE_DIR/source-commit.txt"

notarize() {
  local artifact="$1" evidence="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$evidence"
  python3 - "$evidence" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])); print('Apple submission:',v.get('id'),'status:',v.get('status'))
assert v.get('status')=='Accepted', 'Notarization did not complete with Accepted; inspect submission before retrying'
PY
}

swift test -c release
python3 -m unittest discover -s Tests -p 'test_*.py'
xcodebuild -project "$ROOT_DIR/CodexUsageAnalyzer.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -archivePath "$ARCHIVE_PATH" -destination 'generic/platform=macOS' \
  ARCHS=arm64 DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" archive
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$RELEASE_DIR/app-notary.zip"
notarize "$RELEASE_DIR/app-notary.zip" "$RELEASE_DIR/app-notary.json"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -format UDZO "$DMG_PATH"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
notarize "$DMG_PATH" "$RELEASE_DIR/dmg-notary.json"
xcrun stapler staple "$DMG_PATH"
"$ROOT_DIR/script/verify_release.sh" "$DMG_PATH" "$VERSION"
(cd "$RELEASE_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "Release artifact: $DMG_PATH"
