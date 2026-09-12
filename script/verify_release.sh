#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?usage: ./script/verify_release.sh /path/to/release.dmg [VERSION]}"
VERSION="${2:-$(basename "$DMG_PATH" | sed -E 's/^Codex-Usage-Analyzer-(.*)-mac-arm64\.dmg$/\1/')}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
MOUNT_DIR="$(mktemp -d /private/tmp/codex-usage-analyzer-verify.XXXXXX)"
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_DIR" -quiet
APP_PATH="$MOUNT_DIR/Codex Usage Analyzer.app"
test -d "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE="$(codesign -dvv "$APP_PATH" 2>&1)"
printf '%s\n' "$SIGNATURE"
[[ "$SIGNATURE" == *'Authority=Developer ID Application:'* ]]
[[ "$SIGNATURE" == *'TeamIdentifier=G6JH37W285'* ]]
[[ "$SIGNATURE" == *'runtime'* ]]
[[ "$SIGNATURE" == *'Timestamp='* ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == 'com.c5vcpq5gsr.codexusageanalyzer' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(lipo -archs "$APP_PATH/Contents/MacOS/CodexUsageAnalyzer")" == arm64 ]]
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
echo "Verified app and DMG: $DMG_PATH ($VERSION, arm64)"
