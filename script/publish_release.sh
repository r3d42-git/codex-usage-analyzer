#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: ./script/publish_release.sh VERSION}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="v$VERSION"
DMG_PATH="$ROOT_DIR/.release/$VERSION/Codex-Usage-Analyzer-$VERSION-mac-arm64.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

test -f "$DMG_PATH"
test -f "$CHECKSUM_PATH"
gh release create "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" --title "$TAG" --generate-notes
DOWNLOAD_DIR="$(mktemp -d /private/tmp/codex-usage-analyzer-release.XXXXXX)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
gh release download "$TAG" --pattern "$(basename "$DMG_PATH")" --dir "$DOWNLOAD_DIR"
EXPECTED_DIGEST="$(awk '{print $1}' "$CHECKSUM_PATH")"
ACTUAL_DIGEST="$(shasum -a 256 "${DOWNLOAD_DIR}/$(basename "$DMG_PATH")" | awk '{print $1}')"
test "$EXPECTED_DIGEST" = "$ACTUAL_DIGEST"
"$ROOT_DIR/script/verify_release.sh" "${DOWNLOAD_DIR}/$(basename "$DMG_PATH")"
