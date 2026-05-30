#!/usr/bin/env bash
#
# Register this Mac as a self-hosted GitHub Actions runner for token-wise.
# Self-hosted runner minutes are NOT billed by GitHub, so releases are free.
#
# The runner is installed to ~/actions-runner and MUST run in your logged-in
# session (so it can read the login Keychain for code signing). This script
# starts it in the foreground; see docs/RELEASING.md for a LaunchAgent setup
# to start it automatically at login.
#
# Requires: gh (authenticated), curl, tar.
set -euo pipefail

REPO="banyudu/token-wise"
RUNNER_DIR="$HOME/actions-runner"
LABELS="macOS"

arch="$(uname -m)"
case "$arch" in
  arm64) pkg_arch="arm64" ;;
  x86_64) pkg_arch="x64" ;;
  *) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac

echo "==> Resolving latest runner version"
ver="$(gh api repos/actions/runner/releases/latest --jq .tag_name)"
ver="${ver#v}"
url="https://github.com/actions/runner/releases/download/v${ver}/actions-runner-osx-${pkg_arch}-${ver}.tar.gz"

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
if [[ ! -x ./config.sh ]]; then
  echo "==> Downloading runner ${ver} (${pkg_arch})"
  curl -fL -o runner.tar.gz "$url"
  tar xzf runner.tar.gz
  rm -f runner.tar.gz
fi

if [[ ! -f .runner ]]; then
  echo "==> Fetching registration token"
  token="$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" --jq .token)"
  echo "==> Configuring runner"
  ./config.sh --url "https://github.com/${REPO}" --token "$token" \
    --labels "$LABELS" --name "$(hostname -s)" --unattended --replace
fi

echo "==> Starting runner in the foreground (Ctrl-C to stop)."
echo "    Keep this terminal open, or set up the LaunchAgent (see docs/RELEASING.md)."
./run.sh
