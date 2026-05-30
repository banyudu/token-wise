#!/usr/bin/env bash
#
# Publish the Developer ID / direct-distribution build to GitHub Releases and
# generate the Tauri updater feed (latest.json) so installed dev builds
# self-update. Run after `pnpm tauri:build:dev` (or via `pnpm tauri:release:dev`).
#
# Requires: gh (authenticated), jq.
set -euo pipefail

REPO="banyudu/token-wise"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

SIGNATURE="$(cat "$SIG")"
PUB_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# /latest/download/<asset> resolves to the newest release, so this URL stays valid.
ASSET_URL="https://github.com/${REPO}/releases/download/${TAG}/token-wise.app.tar.gz"

OUT_DIR="$(mktemp -d)"
LATEST_JSON="${OUT_DIR}/latest.json"
jq -n \
  --arg version "$VERSION" \
  --arg pub_date "$PUB_DATE" \
  --arg signature "$SIGNATURE" \
  --arg url "$ASSET_URL" \
  '{
    version: $version,
    pub_date: $pub_date,
    platforms: {
      "darwin-x86_64":   { signature: $signature, url: $url },
      "darwin-aarch64":  { signature: $signature, url: $url },
      "darwin-universal":{ signature: $signature, url: $url }
    }
  }' > "$LATEST_JSON"

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$REPO" --title "$TAG" \
    --notes "Dev channel release ${TAG}"
fi

UPLOADS=("$TARGZ" "$LATEST_JSON")
[[ -n "$DMG" ]] && UPLOADS+=("$DMG")
gh release upload "$TAG" "${UPLOADS[@]}" --repo "$REPO" --clobber

echo "Published dev build ${TAG}:"
echo "  https://github.com/${REPO}/releases/tag/${TAG}"
