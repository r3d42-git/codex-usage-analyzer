#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == --dry-run ]]; then DRY_RUN=true; shift; fi
VERSION="${1:?usage: ./script/publish_release.sh [--dry-run] VERSION [NOTES_FILE]}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
REPO=r3d42-git/codex-usage-analyzer
TAG="v$VERSION"
RELEASE_DIR="$ROOT_DIR/.release/$VERSION"
DMG_PATH="$RELEASE_DIR/Codex-Usage-Analyzer-$VERSION-mac-arm64.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
NOTES_FILE="${2:-$ROOT_DIR/RELEASE_NOTES/$VERSION.md}"
[[ "$(git branch --show-current)" == main ]]
[[ -z "$(git status --porcelain)" ]]
[[ "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" == "$REPO" ]]
COMMIT="$(git rev-parse HEAD)"
[[ "$(cat "$RELEASE_DIR/source-commit.txt")" == "$COMMIT" ]]
test -f "$NOTES_FILE"
EXPECTED_DIGEST="$(awk '{print $1}' "$CHECKSUM_PATH")"
[[ "$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')" == "$EXPECTED_DIGEST" ]]
"$ROOT_DIR/script/verify_release.sh" "$DMG_PATH" "$VERSION"
[[ -z "$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}")" ]] || { echo 'Remote tag already exists; do not overwrite it' >&2; exit 1; }
if git show-ref --verify --quiet "refs/tags/$TAG"; then
  [[ "$(git rev-parse "$TAG^{commit}")" == "$COMMIT" ]]
fi
if $DRY_RUN; then echo "Ready: $TAG at $COMMIT, SHA-256 $EXPECTED_DIGEST"; exit 0; fi

git push origin main
if ! git show-ref --verify --quiet "refs/tags/$TAG"; then git tag -a "$TAG" -m "Release $VERSION" "$COMMIT"; fi
git push origin "$TAG"
gh release create "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" --repo "$REPO" --verify-tag \
  --title "$TAG" --notes-file "$NOTES_FILE"
DOWNLOAD_DIR="$(mktemp -d /private/tmp/codex-usage-analyzer-release.XXXXXX)"
# Keep verification evidence available if the public gate fails.
echo "Public verification directory: $DOWNLOAD_DIR"
gh release download "$TAG" --repo "$REPO" --pattern "$(basename "$DMG_PATH")" --dir "$DOWNLOAD_DIR"
ACTUAL_DIGEST="$(shasum -a 256 "$DOWNLOAD_DIR/$(basename "$DMG_PATH")" | awk '{print $1}')"
[[ "$EXPECTED_DIGEST" == "$ACTUAL_DIGEST" ]]
gh api "repos/$REPO/releases/tags/$TAG" > "$RELEASE_DIR/github-release.json"
python3 - "$RELEASE_DIR/github-release.json" "$(basename "$DMG_PATH")" "$EXPECTED_DIGEST" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])); asset=next(a for a in v['assets'] if a['name']==sys.argv[2])
if asset.get('digest'): assert asset['digest']=='sha256:'+sys.argv[3], 'GitHub asset digest mismatch'
print('Public release:',v['html_url']); print('Asset:',asset['browser_download_url'])
PY
"$ROOT_DIR/script/verify_release.sh" "$DOWNLOAD_DIR/$(basename "$DMG_PATH")" "$VERSION"
echo "Public download verified: $EXPECTED_DIGEST"
