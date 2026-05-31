#!/usr/bin/env bash
#
# Publish the Developer ID / direct-distribution build to public object storage
# (assets.banyudu.com, via the local S3 mount) and generate the Tauri updater
# feed (latest.json) so installed dev builds self-update.
#
# The repo is PRIVATE, so GitHub Releases can't serve the updater to
# unauthenticated end-user machines. We host the public binaries + feed on S3.
#
# Run after `pnpm tauri:build:dev` (or via `pnpm tauri:release:dev`).
# Requires: jq, curl, and the S3 mount at $TOKENWISE_S3_ASSETS_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_URL="${TOKENWISE_UPDATER_BASE_URL:-https://assets.banyudu.com/token-wise}"
S3_ASSETS_DIR="${TOKENWISE_S3_ASSETS_DIR:-$HOME/Library/CloudStorage/S3-S3/assets}"
DEST_ROOT="${S3_ASSETS_DIR}/token-wise"

VERSION="$(jq -r .version package.json)"
TAG="v${VERSION}"

BUNDLE_DIR="src-tauri/target/universal-apple-darwin/release/bundle"
TARGZ="${BUNDLE_DIR}/macos/token-wise.app.tar.gz"
SIG="${TARGZ}.sig"
DMG="$(ls "${BUNDLE_DIR}"/dmg/*.dmg 2>/dev/null | head -n1 || true)"

if [[ ! -f "$TARGZ" || ! -f "$SIG" ]]; then
  echo "error: updater artifacts missing — run 'pnpm tauri:build:dev' first." >&2
  echo "       expected ${TARGZ} (+ .sig)" >&2
  exit 1
fi
if [[ ! -d "$S3_ASSETS_DIR" ]]; then
  echo "error: S3 assets mount not found at ${S3_ASSETS_DIR}" >&2
  echo "       set TOKENWISE_S3_ASSETS_DIR to your mounted bucket's assets dir." >&2
  exit 1
fi

SIGNATURE="$(cat "$SIG")"
PUB_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TARGZ_URL="${BASE_URL}/${TAG}/token-wise.app.tar.gz"

# 1. Copy binaries into the versioned S3 folder.
DEST="${DEST_ROOT}/${TAG}"
mkdir -p "$DEST"
cp -f "$TARGZ" "${DEST}/token-wise.app.tar.gz"
[[ -n "$DMG" ]] && cp -f "$DMG" "${DEST}/$(basename "$DMG")"

# 2. Wait for the tarball to be publicly reachable BEFORE publishing the feed,
#    so latest.json never points at a not-yet-uploaded artifact. The S3 mount
#    uploads asynchronously, so this can lag for a 16 MB file.
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
wait_public "$TARGZ_URL" "tarball" || true

# 3. Publish the updater feed (stable URL) last.
jq -n \
  --arg version "$VERSION" \
  --arg pub_date "$PUB_DATE" \
  --arg signature "$SIGNATURE" \
  --arg url "$TARGZ_URL" \
  '{
    version: $version,
    pub_date: $pub_date,
    platforms: {
      "darwin-x86_64":   { signature: $signature, url: $url },
      "darwin-aarch64":  { signature: $signature, url: $url },
      "darwin-universal":{ signature: $signature, url: $url }
    }
  }' > "${DEST_ROOT}/latest.json"

wait_public "${BASE_URL}/latest.json" "feed" || true

echo "Published dev build ${TAG}:"
echo "  feed:    ${BASE_URL}/latest.json"
echo "  tarball: ${TARGZ_URL}"
[[ -n "$DMG" ]] && echo "  dmg:     ${BASE_URL}/${TAG}/$(basename "$DMG")"
