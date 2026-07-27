#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?usage: ./script/verify_release.sh /path/to/release.dmg}"
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
APP_PATH="$(find "$MOUNT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
test -n "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
echo "Verified: $DMG_PATH"
