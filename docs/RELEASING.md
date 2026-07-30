# Releasing token-wise

The app ships from the **native Swift package** (`apple/`) through **two
independent channels**:

| Channel | Signing | Sandbox | Updates | Output |
| --- | --- | --- | --- | --- |
| **Dev** (direct) | `Developer ID Application` | no (hardened runtime) | manual (download new DMG) | notarized DMG on S3 (assets.banyudu.com) |
| **App Store** | `Apple Distribution` | yes + provisioning profile | App Store | `.pkg` via `altool` |

Both channels come out of the same `scripts/build-swift-app.sh`, which
assembles `dist-swift/token-wise.app` (SwiftUI GUI + the `token-wise` CLI in
one bundle) with the channel's entitlements:

- `apple/Resources/Entitlements.dev.plist` — no sandbox, hardened runtime.
- `apple/Resources/Entitlements.appstore.plist` — App Sandbox +
  `application-identifier`; the bundle also embeds
  `apple/Resources/embedded.provisionprofile`. Folder access at runtime goes through
  the in-app grant flow (security-scoped bookmarks).

> The Swift app has no in-app auto-updater.
> The dev channel publishes a versioned DMG plus a stable
> `token-wise/latest-dmg.json` pointer.

Bump the version once and you can ship the **same** version to both: dev-build
users download the new DMG; App Store users get it after review.

---

## One-command release (local)

```bash
scripts/release-all.sh            # both channels
scripts/release-all.sh appstore   # App Store only
scripts/release-all.sh dev        # dev channel only
```

`scripts/release-all.sh` loads secrets from the Keychain, then:

- **App Store**: `build-swift-app.sh appstore` (Apple Distribution, sandboxed,
  provisioning profile embedded, **not** notarized) → `productbuild` signed
  `.pkg` → `altool` upload.
- **Dev**: `build-swift-app.sh dev` (Developer ID, hardened runtime) →
  `release-swift-dev.sh`: DMG → `notarytool` + staple → copy to the S3 mount
  under `token-wise/v<version>/` → publish `token-wise/latest-dmg.json` once
  the DMG is publicly reachable.

> The S3 mount defaults to `~/Library/CloudStorage/S3-S3/assets` and the public
> base URL to `https://assets.banyudu.com/token-wise`; override with
> `TOKENWISE_S3_ASSETS_DIR` / `TOKENWISE_UPDATER_BASE_URL` if either changes.

Bump the version first so both channels match (the Swift bundle reads its
version from `VERSION`):

```bash
echo 0.2.0 > VERSION
scripts/release-all.sh
```

---

## Hands-off release (self-hosted runner, free)

GitHub does **not** bill Actions minutes for self-hosted runners, so this is
free even though macOS builds are otherwise expensive. The workflow is
**manual-dispatch only** — it never auto-triggers, and it needs no Node or
Rust toolchain (just Xcode + `jq`).

**One-time:** register this Mac as a runner. It must run in your logged-in
session so it can read the login Keychain for code signing.

```bash
scripts/setup-runner.sh     # downloads, registers, and starts the runner
```

To keep it running across logins, install it as a per-user LaunchAgent instead
of the foreground `run.sh`:

```bash
cd ~/actions-runner
./svc.sh install        # registers a launchd service for your user
./svc.sh start
```

**Each release:** trigger from the CLI or the GitHub UI (Actions → Release → Run
workflow):

```bash
gh workflow run release.yml -f channel=both     # or appstore / dev
```

---

## One-time setup

### 1. App Store Connect API key

Already present at `~/.appstoreconnect/private_keys/AuthKey_CJ28PU73CA.p8`
(Key ID `CJ28PU73CA`, auto-detected from the filename). If it ever changes, drop
the new `.p8` in that folder; the scripts pick up the Key ID from the name.

Used for both notarization (`notarytool`, dev channel) and the `.pkg` upload
(`altool`, App Store channel).

### 2. Store secrets in the Keychain

```bash
scripts/setup-release-secrets.sh
```

Prompts for and stores (service `token-wise-release`, login Keychain):

- **App Store Connect Issuer ID** (UUID, from App Store Connect → Users and
  Access → Integrations → App Store Connect API)

Nothing is written to disk in plaintext. `scripts/load-release-env.sh` reads
these at build time; any value can be overridden by a pre-set env var.

### Required signing identities (in your login Keychain)

- `Apple Distribution: Yudu Ban (RYLS8UDY5D)` — App Store app
- `3rd Party Mac Developer Installer: Yudu Ban (RYLS8UDY5D)` — App Store `.pkg`
- `Developer ID Application: Yudu Ban (RYLS8UDY5D)` — dev channel app

Identities can be overridden per run with `APPSTORE_SIGNING_IDENTITY` /
`DEV_SIGNING_IDENTITY`.

---
