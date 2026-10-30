#!/usr/bin/env bash
#
# maclift item: create an SSH key and add it to GitHub.
#   ssh-key.sh --check   exit 0 when there is nothing to do
#   ssh-key.sh           create the key; exit non-zero on failure
# Works only inside $MACLIFT_HOME/.ssh. Test overrides: MACLIFT_SSH_KEYGEN,
# MACLIFT_SSH_ADD, MACLIFT_GH, MACLIFT_HAS_TTY (1/0). In a sandbox (MACLIFT_HOME
# is not HOME) it skips ssh-add and gh.

set -eo pipefail

MACLIFT_DIR="${MACLIFT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=lib/core.sh
source "$MACLIFT_DIR/lib/core.sh"
# shellcheck source=lib/conf.sh
source "$MACLIFT_DIR/lib/conf.sh"
maclift_init_paths

SSH_DIR="$MACLIFT_HOME/.ssh"
KEY="$SSH_DIR/id_ed25519"

if [ "${1:-}" = "--check" ]; then
  [ -e "$KEY" ]
  exit $?
fi

has_tty() {
  if [ -n "${MACLIFT_HAS_TTY:-}" ]; then [ "$MACLIFT_HAS_TTY" = 1 ]; return; fi
  { : </dev/tty; } 2>/dev/null
}

if ! has_tty; then
  echo "needs a terminal to set the key's passphrase; run maclift from a terminal"
  exit 1
fi

if [ -e "$KEY" ]; then
  # shellcheck disable=SC2088 # literal tilde for display
  echo "~/.ssh/id_ed25519 already exists; nothing to do"
  exit 0
fi
if [ -e "$KEY.pub" ]; then
  # shellcheck disable=SC2088 # literal tilde for display
  echo "~/.ssh/id_ed25519.pub exists without its private key; move it aside and run again"
  exit 1
fi

email="$(conf_get "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL 2>/dev/null || true)"
if [ -z "$email" ]; then
  echo "email missing in $MACLIFT_CONFIG_DIR/user.conf; run maclift interactively first"
  exit 1
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

"${MACLIFT_SSH_KEYGEN:-ssh-keygen}" -t ed25519 -C "$email" -f "$KEY"

if ! grep -q '^[[:space:]]*UseKeychain' "$SSH_DIR/config" 2>/dev/null; then
  [ -e "$SSH_DIR/config" ] || (umask 077 && : >"$SSH_DIR/config")
  {
    [ -s "$SSH_DIR/config" ] && echo
    echo "# added by maclift"
    echo "Host *"
    echo "  AddKeysToAgent yes"
    echo "  UseKeychain yes"
  } >>"$SSH_DIR/config"
  chmod 600 "$SSH_DIR/config"
fi

if maclift_is_sandbox; then
  maclift_note "sandbox run: skipped the keychain and GitHub upload for $KEY.pub"
  exit 0
fi

"${MACLIFT_SSH_ADD:-ssh-add}" --apple-use-keychain "$KEY"

gh_bin="${MACLIFT_GH:-gh}"
if "$gh_bin" auth status >/dev/null 2>&1; then
  title="maclift $(scutil --get ComputerName 2>/dev/null || hostname)"
  if ! "$gh_bin" ssh-key add "$KEY.pub" --title "$title"; then
    maclift_note "Could not upload the SSH key. Add it later: gh ssh-key add ~/.ssh/id_ed25519.pub"
  fi
else
  maclift_note "Add the SSH key to GitHub later: gh auth login && gh ssh-key add ~/.ssh/id_ed25519.pub"
fi
