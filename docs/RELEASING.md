# Releasing token-wise

The app ships through **two independent channels** from one codebase:

| Channel | Signing | Sandbox | Updates | Output |
| --- | --- | --- | --- | --- |
| **Dev** (direct) | `Developer ID Application` | no (hardened runtime) | Tauri auto-updater | DMG + `latest.json` on GitHub Releases |
| **App Store** | `Apple Distribution` | yes + provisioning profile | App Store | `.pkg` via `altool` |

Bump the version once and you can ship the **same** version to both: dev-build
users get it immediately (auto-update); App Store users get it after review.

Base `src-tauri/tauri.conf.json` is the **Dev** profile. The App Store build
layers `src-tauri/tauri.appstore.conf.json` and compiles `--no-default-features`,
so the `tauri-plugin-updater` code is entirely absent from the MAS binary.

---

## One-command release (local)

```bash
pnpm release            # both channels
pnpm release:appstore   # App Store only
pnpm release:dev        # dev channel only
```

`scripts/release-all.sh` loads secrets from the Keychain, then for App Store:
builds (sandboxed, no updater, **not** notarized) → `.pkg` → `altool` upload;
for dev: builds + notarizes the DMG + signs the updater artifact → creates the
`v<version>` GitHub Release with the DMG, `token-wise.app.tar.gz`, and
`latest.json`.

Bump the version first so both channels match:

```bash
pnpm version <new-version>   # updates package.json, Cargo.toml, tauri.conf.json
pnpm release
```

---

## Hands-off release (self-hosted runner, free)

GitHub does **not** bill Actions minutes for self-hosted runners, so this is
free even though macOS builds are otherwise expensive. The workflow is
**manual-dispatch only** — it never auto-triggers.

**One-time:** register this Mac as a runner. It must run in your logged-in
session so it can read the login Keychain for code signing.

```bash
pnpm release:runner     # downloads, registers, and starts the runner
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

### 1. Updater signing keypair (dev channel)

```bash
pnpm tauri signer generate -w "$HOME/.tauri/token-wise.key"
```

- Choose a password when prompted (store it in step 3).
- Paste the printed **public key** into `src-tauri/tauri.conf.json` →
  `plugins.updater.pubkey` (replace the `REPLACE_WITH_...` placeholder).
- `~/.tauri/token-wise.key` is **never committed**. Back it up — losing it means
  existing installs can no longer verify updates.

### 2. App Store Connect API key

Already present at `~/.appstoreconnect/private_keys/AuthKey_CJ28PU73CA.p8`
(Key ID `CJ28PU73CA`, auto-detected from the filename). If it ever changes, drop
the new `.p8` in that folder; the scripts pick up the Key ID from the name.

### 3. Store secrets in the Keychain

```bash
pnpm release:secrets
```

Prompts for and stores (service `token-wise-release`, login Keychain):

- **App Store Connect Issuer ID** (UUID, from App Store Connect → Users and
  Access → Integrations → App Store Connect API)
- **Updater key password** (from step 1)

Nothing is written to disk in plaintext. `scripts/load-release-env.sh` reads
these at build time; any value can be overridden by a pre-set env var.

### Required signing identities (in your login Keychain)

- `Apple Distribution: Yudu Ban (RYLS8UDY5D)` — App Store app
- `3rd Party Mac Developer Installer: Yudu Ban (RYLS8UDY5D)` — App Store `.pkg`
- `Developer ID Application: Yudu Ban (RYLS8UDY5D)` — dev channel app
