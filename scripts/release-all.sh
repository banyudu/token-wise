#!/usr/bin/env bash
#
# Build + upload both distribution channels in one shot:
#   - App Store  (Apple Distribution, sandboxed, .pkg -> altool)
#   - Dev        (Developer ID, notarized DMG + updater feed -> GitHub Releases)
#
# Secrets/env come from the Keychain via scripts/load-release-env.sh.
#
#   scripts/release-all.sh [both|appstore|dev]   (default: both)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$PATH"

# shellcheck source=scripts/load-release-env.sh
source scripts/load-release-env.sh

CHANNEL="${1:-both}"
case "$CHANNEL" in
  both|appstore|dev) ;;
  *) echo "usage: release-all.sh [both|appstore|dev]" >&2; exit 1 ;;
esac

if [[ "$CHANNEL" == "both" || "$CHANNEL" == "appstore" ]]; then
  echo "==> App Store channel (Apple Distribution, sandboxed)"
  # App Store apps are NOT notarized — strip the notarization creds so the
  # bundler doesn't try (and fail) to notarize an Apple-Distribution build.
  env -u APPLE_API_KEY -u APPLE_API_KEY_PATH -u APPLE_API_ISSUER \
      -u APPLE_ID -u APPLE_PASSWORD -u APPLE_TEAM_ID \
      pnpm tauri:build:appstore
  pnpm tauri:pkg:appstore
  pnpm tauri:upload:appstore
fi

if [[ "$CHANNEL" == "both" || "$CHANNEL" == "dev" ]]; then
  echo "==> Dev channel (Developer ID, notarized, auto-update)"
  pnpm tauri:release:dev
fi

echo "Release complete: ${CHANNEL}"
