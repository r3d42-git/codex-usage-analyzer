#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codex Usage Analyzer"
PROCESS_NAME="CodexUsageAnalyzer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_SOURCE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
BUNDLE_ID="com.c5vcpq5gsr.codexusageanalyzer"

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/CodexUsageAnalyzer.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR"
ditto "$APP_SOURCE" "$APP_BUNDLE"
codesign --force --sign - --entitlements "$ROOT_DIR/CodexUsageAnalyzer.entitlements" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
