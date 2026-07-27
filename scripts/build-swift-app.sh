#!/usr/bin/env bash
# Build the native Swift app (apple/) into a distributable token-wise.app.
#
# Usage:
#   scripts/build-swift-app.sh [dev|appstore]
#
#   dev       (default) — no sandbox; reads ~/.claude & ~/.codex directly.
#                         Signs with $APPLE_SIGNING_IDENTITY when set
#                         (e.g. "Developer ID Application: …"), ad-hoc otherwise.
#   appstore  — App Sandbox entitlements (folder access via the in-app grant
#               flow + security-scoped bookmarks). Requires
#               $APPLE_SIGNING_IDENTITY ("Apple Distribution: …").
#
# Output: dist-swift/token-wise.app  (plus the CLI at Contents/MacOS/token-wise)

set -euo pipefail
cd "$(dirname "$0")/.."

CHANNEL="${1:-dev}"
VERSION="$(jq -r .version package.json)"
OUT_DIR="dist-swift"
APP="$OUT_DIR/token-wise.app"

case "$CHANNEL" in
  dev)      ENTITLEMENTS="apple/Resources/Entitlements.dev.plist" ;;
  appstore) ENTITLEMENTS="apple/Resources/Entitlements.appstore.plist" ;;
  *) echo "unknown channel: $CHANNEL (want dev|appstore)" >&2; exit 1 ;;
esac

echo "==> swift build -c release (apple/)"
(cd apple && swift build -c release)

echo "==> assembling $APP (v$VERSION, $CHANNEL)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

sed "s/APP_VERSION/$VERSION/g" apple/Resources/Info.plist > "$APP/Contents/Info.plist"
cp apple/.build/release/TokenWiseApp "$APP/Contents/MacOS/TokenWiseApp"
cp apple/.build/release/token-wise "$APP/Contents/MacOS/token-wise"
cp src-tauri/icons/icon.icns "$APP/Contents/Resources/icon.icns"

IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
if [[ "$CHANNEL" == "appstore" && -z "$IDENTITY" ]]; then
  echo "appstore channel requires APPLE_SIGNING_IDENTITY" >&2
  exit 1
fi

if [[ -n "$IDENTITY" ]]; then
  echo "==> codesign ($IDENTITY)"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" \
    "$APP/Contents/MacOS/token-wise"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" \
    "$APP"
else
  echo "==> codesign (ad-hoc; set APPLE_SIGNING_IDENTITY for distribution)"
  codesign --force --sign - "$APP/Contents/MacOS/token-wise"
  codesign --force --sign - "$APP"
fi

codesign --verify --deep "$APP"
echo "==> done: $APP"
