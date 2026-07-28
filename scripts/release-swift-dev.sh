#!/usr/bin/env bash
#
# Dev / direct-distribution channel for the native Swift app:
# notarized DMG published to public object storage (assets.banyudu.com,
# via the local S3 mount).
#
# The Swift app has no in-app updater, so this publishes a versioned DMG + a
# stable `latest-dmg.json` pointer that the
# website / users can link to.
#
# Run after scripts/build-swift-app.sh dev (release-all.sh does both).
# Requires: jq, curl, notarytool creds (APPLE_API_KEY_PATH/APPLE_API_KEY_ID/
# APPLE_API_ISSUER), and the S3 mount at $TOKENWISE_S3_ASSETS_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_URL="${TOKENWISE_UPDATER_BASE_URL:-https://assets.banyudu.com/token-wise}"
S3_ASSETS_DIR="${TOKENWISE_S3_ASSETS_DIR:-$HOME/Library/CloudStorage/S3-S3/assets}"
DEST_ROOT="${S3_ASSETS_DIR}/token-wise"

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v${VERSION}"

APP="dist-swift/token-wise.app"
DMG="dist-swift/token-wise_${VERSION}_universal.dmg"

[[ -d "$APP" ]] || { echo "error: $APP missing — run scripts/build-swift-app.sh dev first." >&2; exit 1; }
[[ -d "$S3_ASSETS_DIR" ]] || {
  echo "error: S3 assets mount not found at ${S3_ASSETS_DIR}" >&2
  echo "       set TOKENWISE_S3_ASSETS_DIR to your mounted bucket's assets dir." >&2
  exit 1
}

# 1. DMG with the standard drag-to-Applications layout.
echo "==> creating $DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Token Wise" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# 2. Notarize + staple (Developer ID builds are gate-kept without this).
echo "==> notarizing"
xcrun notarytool submit "$DMG" \
  --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" \
  --wait
xcrun stapler staple "$DMG"

# 3. Copy into the versioned S3 folder.
DEST="${DEST_ROOT}/${TAG}"
mkdir -p "$DEST"
cp -f "$DMG" "${DEST}/$(basename "$DMG")"
DMG_URL="${BASE_URL}/${TAG}/$(basename "$DMG")"

# 4. Wait until the DMG is publicly reachable BEFORE publishing the pointer,
#    so latest-dmg.json never points at a not-yet-uploaded artifact (the S3
#    mount uploads asynchronously).
wait_public() {
  local url="$1" label="$2" code
  for _ in $(seq 1 60); do
    code="$(curl -fsSL -o /dev/null -w '%{http_code}' -I "$url" 2>/dev/null || true)"
    [[ "$code" == "200" ]] && { echo "  ${label} live (HTTP 200)"; return 0; }
    sleep 5
  done
  echo "  warning: ${label} not public yet (last HTTP ${code:-?}); S3 mount may still be uploading." >&2
  return 1
}

echo "Publishing ${TAG} to ${BASE_URL} ..."
wait_public "$DMG_URL" "dmg" || true

# 5. Stable pointer for the website / download links.
jq -n \
  --arg version "$VERSION" \
  --arg pub_date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg url "$DMG_URL" \
  '{ version: $version, pub_date: $pub_date, url: $url }' \
  > "${DEST_ROOT}/latest-dmg.json"

wait_public "${BASE_URL}/latest-dmg.json" "pointer" || true

echo "Published dev build ${TAG}:"
echo "  dmg:     ${DMG_URL}"
echo "  pointer: ${BASE_URL}/latest-dmg.json"
