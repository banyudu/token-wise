#!/usr/bin/env bash
#
# One-time (re-runnable) setup: store token-wise release secrets in the macOS
# login Keychain under service "token-wise-release". Nothing is written to disk
# in plaintext. Re-run any time to update a value (press Enter to keep current).
#
# Secrets stored here:
#   - APPLE_API_ISSUER                    App Store Connect API issuer UUID
#   - TAURI_SIGNING_PRIVATE_KEY_PASSWORD  password for the updater signing key
#
# Not stored here (already on disk / derivable):
#   - the App Store Connect .p8 key (~/.appstoreconnect/private_keys/AuthKey_*.p8)
#   - the updater private key (~/.tauri/token-wise.key)
#   - signing-identity names (in your Keychain certs)
set -euo pipefail

SERVICE="token-wise-release"

store() {
  local account="$1" prompt="$2" current value
  current="$(security find-generic-password -s "$SERVICE" -a "$account" -w 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    printf '%s [Enter to keep existing]: ' "$prompt"
  else
    printf '%s: ' "$prompt"
  fi
  read -rs value
  printf '\n'
  if [[ -z "$value" ]]; then
    [[ -n "$current" ]] && { echo "  kept ${account}"; return; }
    echo "  skipped ${account} (no value)"; return
  fi
  security add-generic-password -U -s "$SERVICE" -a "$account" -w "$value"
  echo "  stored ${account}"
}

echo "Storing token-wise release secrets in Keychain (service: ${SERVICE})"
store "APPLE_API_ISSUER" "App Store Connect API Issuer ID (UUID)"
store "TAURI_SIGNING_PRIVATE_KEY_PASSWORD" "Tauri updater key password"
echo "Done. You can now run 'pnpm release'."
