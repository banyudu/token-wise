# Sourced (not executed) by release scripts. Exports signing / notarization /
# updater env from the macOS Keychain + on-disk keys. Reads nothing from
# committed files.
#
#   source scripts/load-release-env.sh
#
# Every value honors a pre-set env var (so CI or a one-off override wins over
# the Keychain). Returns non-zero with an actionable message if a required
# secret is missing.

_kc() { security find-generic-password -s "token-wise-release" -a "$1" -w 2>/dev/null; }

# --- App Store Connect API key (notarization + altool upload) ---------------
: "${APPLE_API_KEY_PATH:=$HOME/.appstoreconnect/private_keys/AuthKey_CJ28PU73CA.p8}"
# Key ID is encoded in the AuthKey_<ID>.p8 filename.
_p8_id="$(basename "$APPLE_API_KEY_PATH")"; _p8_id="${_p8_id#AuthKey_}"; _p8_id="${_p8_id%.p8}"
: "${APPLE_API_KEY:=$_p8_id}"        # read by tauri notarization
: "${APPLE_API_KEY_ID:=$_p8_id}"     # read by the altool upload script
: "${APPLE_API_ISSUER:=$(_kc APPLE_API_ISSUER)}"
export APPLE_API_KEY_PATH APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER

# --- Dev channel updater signing --------------------------------------------
: "${TAURI_SIGNING_PRIVATE_KEY_FILE:=$HOME/.tauri/token-wise.key}"
if [[ -z "${TAURI_SIGNING_PRIVATE_KEY:-}" && -f "$TAURI_SIGNING_PRIVATE_KEY_FILE" ]]; then
  TAURI_SIGNING_PRIVATE_KEY="$(cat "$TAURI_SIGNING_PRIVATE_KEY_FILE")"
fi
: "${TAURI_SIGNING_PRIVATE_KEY_PASSWORD:=$(_kc TAURI_SIGNING_PRIVATE_KEY_PASSWORD)}"
export TAURI_SIGNING_PRIVATE_KEY TAURI_SIGNING_PRIVATE_KEY_PASSWORD

# --- App Store installer identity (not secret) ------------------------------
: "${MAC_INSTALLER_IDENTITY:=3rd Party Mac Developer Installer: Yudu Ban (RYLS8UDY5D)}"
export MAC_INSTALLER_IDENTITY

# --- Validation -------------------------------------------------------------
_missing=()
[[ -f "$APPLE_API_KEY_PATH" ]] || _missing+=("APPLE_API_KEY_PATH ($APPLE_API_KEY_PATH not found)")
[[ -n "$APPLE_API_ISSUER" ]]   || _missing+=("APPLE_API_ISSUER (run scripts/setup-release-secrets.sh)")
[[ -n "${TAURI_SIGNING_PRIVATE_KEY:-}" ]] || _missing+=("TAURI_SIGNING_PRIVATE_KEY ($TAURI_SIGNING_PRIVATE_KEY_FILE not found — run 'pnpm tauri signer generate -w $TAURI_SIGNING_PRIVATE_KEY_FILE')")
[[ -n "$TAURI_SIGNING_PRIVATE_KEY_PASSWORD" ]] || _missing+=("TAURI_SIGNING_PRIVATE_KEY_PASSWORD (run scripts/setup-release-secrets.sh)")

if (( ${#_missing[@]} > 0 )); then
  echo "Missing release configuration:" >&2
  printf '  - %s\n' "${_missing[@]}" >&2
  return 1 2>/dev/null || exit 1
fi
