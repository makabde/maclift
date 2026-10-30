#!/usr/bin/env bash
#
# maclift item: GPG key for signed commits, uploaded to GitHub.
#   gpg-signing.sh --check   exit 0 when MACLIFT_SIGNING_KEY is set and gpg has it
#   gpg-signing.sh           reuse or create the key; exit non-zero on failure
# Works only inside $MACLIFT_HOME/.gnupg and user.conf. Test overrides:
# MACLIFT_GPG, MACLIFT_GPGCONF, MACLIFT_BREW, MACLIFT_GH. gpg uses GNUPGHOME
# (maclift_gnupghome): in a sandbox (MACLIFT_HOME is not HOME) that is
# $MACLIFT_HOME/.gnupg, and gpgconf and gh are skipped.

set -eo pipefail

MACLIFT_DIR="${MACLIFT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=lib/core.sh
source "$MACLIFT_DIR/lib/core.sh"
# shellcheck source=lib/conf.sh
source "$MACLIFT_DIR/lib/conf.sh"
maclift_init_paths

CONF="$MACLIFT_CONFIG_DIR/user.conf"
GNUPGHOME="$(maclift_gnupghome)"
export GNUPGHOME
GPG_DIR="$GNUPGHOME"
SANDBOX=0
if maclift_is_sandbox; then SANDBOX=1; fi
gpg_bin="${MACLIFT_GPG:-gpg}"

# Fingerprint of the first usable secret key (not expired, revoked, invalid or
# disabled) with a uid, not revoked, containing exactly <$1>, from
# --with-colons on stdin.
first_fpr() {
  awk -F: -v want="<$1>" '
    function done() { if (!out && ok && hit && fpr != "") { print fpr; out = 1 } }
    $1 == "sec" { done(); ok = ($2 !~ /^[erid]$/); hit = 0; fpr = ""; seen = 0; next }
    $1 == "fpr" && !seen { fpr = $10; seen = 1; next }
    $1 == "uid" && $2 != "r" && index(tolower($10), tolower(want)) { hit = 1 }
    END { done() }'
}

if [ "${1:-}" = "--check" ]; then
  key="$(conf_get "$CONF" MACLIFT_SIGNING_KEY 2>/dev/null || true)"
  [ -n "$key" ] || exit 1
  "$gpg_bin" --list-secret-keys -- "$key" >/dev/null 2>&1
  exit $?
fi

if [ -n "${MACLIFT_GPG:-}" ]; then
  have_gpg=0; [ -x "$MACLIFT_GPG" ] && have_gpg=1
else
  have_gpg=0; command -v gpg >/dev/null 2>&1 && have_gpg=1
fi
if [ "$have_gpg" = 0 ]; then
  echo "needs gnupg (tick it in Keys & signing)"
  exit 1
fi

name="$(conf_get "$CONF" MACLIFT_NAME 2>/dev/null || true)"
email="$(conf_get "$CONF" MACLIFT_EMAIL 2>/dev/null || true)"
if [ -z "$name" ] || [ -z "$email" ]; then
  echo "name or email missing in $CONF; run maclift interactively first"
  exit 1
fi

if [ ! -d "$GPG_DIR" ]; then
  mkdir -p "$GPG_DIR"
  chmod 700 "$GPG_DIR"
fi

# pinentry-mac first, so the passphrase prompt for a new key already uses it.
agent_conf="$GPG_DIR/gpg-agent.conf"
if ! grep -q '^[[:space:]]*pinentry-program' "$agent_conf" 2>/dev/null; then
  prefix="$("${MACLIFT_BREW:-brew}" --prefix 2>/dev/null || true)"
  pinentry="$prefix/bin/pinentry-mac"
  if [ -n "$prefix" ] && [ -x "$pinentry" ]; then
    {
      [ -s "$agent_conf" ] && echo
      echo "pinentry-program $pinentry"
    } >>"$agent_conf"
    chmod 600 "$agent_conf"
    if [ "$SANDBOX" = 1 ]; then
      maclift_note "sandbox run: skipped restarting gpg-agent"
    else
      "${MACLIFT_GPGCONF:-gpgconf}" --kill gpg-agent ||
        maclift_note "Could not restart gpg-agent; run: gpgconf --kill gpg-agent"
    fi
  fi
fi

listing="$("$gpg_bin" --list-secret-keys --with-colons -- "$email" 2>/dev/null || true)"
fpr="$(printf '%s\n' "$listing" | first_fpr "$email")"
if [ -z "$fpr" ]; then
  "$gpg_bin" --quick-generate-key "$name <$email>" ed25519 sign 2y
  listing="$("$gpg_bin" --list-secret-keys --with-colons -- "$email")"
  fpr="$(printf '%s\n' "$listing" | first_fpr "$email")"
  if [ -z "$fpr" ]; then
    echo "could not read the new key's fingerprint"
    exit 1
  fi
fi

conf_set "$CONF" MACLIFT_SIGNING_KEY "$fpr"

if [ "$SANDBOX" = 1 ]; then
  maclift_note "sandbox run: skipped GitHub upload of gpg key $fpr"
  exit 0
fi

gh_bin="${MACLIFT_GH:-gh}"
if "$gh_bin" auth status >/dev/null 2>&1; then
  if ! "$gpg_bin" --armor --export "$fpr" | "$gh_bin" gpg-key add -; then
    # A rerun: GitHub already has the key (gh lists its 16-digit key id).
    on_github="$("$gh_bin" gpg-key list 2>/dev/null || true)"
    case "$on_github" in
      *"${fpr:${#fpr}-16}"*) ;;
      *) maclift_note "Could not upload the GPG key. Run: gh auth refresh -s write:gpg_key, then: gpg --armor --export $fpr | gh gpg-key add -" ;;
    esac
  fi
else
  maclift_note "Add the GPG key to GitHub later: gh auth login && gh auth refresh -s write:gpg_key, then: gpg --armor --export $fpr | gh gpg-key add -"
fi
