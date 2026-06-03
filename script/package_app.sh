#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: script/package_app.sh <path-to-XTop.app> <version> [out-dir]

Example:
  script/package_app.sh build/Build/Products/Release/XTop.app 0.1.0 out
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

APP_PATH="$1"
VERSION="$2"
OUT_DIR="${3:-out}"
APP_NAME="XTop"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at '$APP_PATH'" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

WORK_DIR="$(mktemp -d)"
STAGE_DIR="$WORK_DIR/dmg-stage"
APP_COPY_PATH="$WORK_DIR/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$VERSION.zip"
DMG_NAME="$APP_NAME-$VERSION.dmg"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
DMG_PATH="$OUT_DIR/$DMG_NAME"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Work on a copy so build outputs remain untouched.
cp -R "$APP_PATH" "$APP_COPY_PATH"

echo "Ad-hoc signing $APP_NAME.app"
codesign --force --deep --sign - --options runtime "$APP_COPY_PATH"
codesign --verify --deep --strict "$APP_COPY_PATH"

rm -f "$ZIP_PATH" "$DMG_PATH"

echo "Creating zip: $ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_COPY_PATH" "$ZIP_PATH"

mkdir -p "$STAGE_DIR"
cp -R "$APP_COPY_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "Creating dmg: $DMG_PATH"
# Detach stale mounts from previous interrupted runs.
if mount | grep -q " on /Volumes/$APP_NAME ("; then
  hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
fi
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created artifacts:"
echo "- $ZIP_PATH"
echo "- $DMG_PATH"
