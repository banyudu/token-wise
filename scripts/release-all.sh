#!/usr/bin/env bash
#
# Build + upload both distribution channels of the native Swift app (apple/):
#   - App Store  (Apple Distribution, sandboxed, .pkg -> altool)
#   - Dev        (Developer ID, notarized DMG -> S3 / assets.banyudu.com)
#
# Secrets/env come from the Keychain via scripts/load-release-env.sh.
#
#   scripts/release-all.sh [both|appstore|dev]   (default: both)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/load-release-env.sh
source scripts/load-release-env.sh

CHANNEL="${1:-both}"
case "$CHANNEL" in
  both|appstore|dev) ;;
  *) echo "usage: release-all.sh [both|appstore|dev]" >&2; exit 1 ;;
esac

if [[ "$CHANNEL" == "both" || "$CHANNEL" == "appstore" ]]; then
  echo "==> App Store channel (Apple Distribution, sandboxed)"
  APPLE_SIGNING_IDENTITY="${APPSTORE_SIGNING_IDENTITY:-Apple Distribution: Yudu Ban (RYLS8UDY5D)}" \
    scripts/build-swift-app.sh appstore
  xcrun productbuild --sign "${MAC_INSTALLER_IDENTITY:?}" \
    --component dist-swift/token-wise.app /Applications token-wise.pkg
  xcrun altool --upload-app --type macos --file token-wise.pkg \
    --apiKey "${APPLE_API_KEY_ID:?}" --apiIssuer "${APPLE_API_ISSUER:?}" --use-old-altool
fi

if [[ "$CHANNEL" == "both" || "$CHANNEL" == "dev" ]]; then
  echo "==> Dev channel (Developer ID, notarized DMG)"
  APPLE_SIGNING_IDENTITY="${DEV_SIGNING_IDENTITY:-Developer ID Application: Yudu Ban (RYLS8UDY5D)}" \
    scripts/build-swift-app.sh dev
  scripts/release-swift-dev.sh
fi

echo "Release complete: ${CHANNEL}"
