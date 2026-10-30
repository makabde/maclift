#!/usr/bin/env bash
#
# maclift core: paths, development safety guard, logging, die.
# bash 3.2 compatible. Meant to be sourced.

# Sets and exports MACLIFT_DIR, MACLIFT_HOME, MACLIFT_CONFIG_DIR, MACLIFT_VERSION.
# Honors MACLIFT_DIR and MACLIFT_HOME when already set.
maclift_init_paths() {
  if [ -z "${MACLIFT_DIR:-}" ]; then
    MACLIFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  MACLIFT_HOME="${MACLIFT_HOME:-$HOME}"
  MACLIFT_CONFIG_DIR="$MACLIFT_HOME/.config/maclift"
  MACLIFT_VERSION="$(head -n1 "$MACLIFT_DIR/VERSION" 2>/dev/null || true)"
  MACLIFT_VERSION="${MACLIFT_VERSION:-0.0.0}"
  export MACLIFT_DIR MACLIFT_HOME MACLIFT_CONFIG_DIR MACLIFT_VERSION
}

# Physical, normalized path: resolves symlinks and trailing slashes. Falls
# back to the raw string without trailing slashes if the dir doesn't exist.
maclift_real_path() {
  local p="$1" r
  if r="$(CDPATH='' cd -P -- "$p" >/dev/null 2>&1 && pwd -P)"; then
    printf '%s\n' "$r"
  else
    while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    printf '%s\n' "$p"
  fi
}

# maclift_is_sandbox: 0 when MACLIFT_HOME is not the real HOME (tests, trial
# runs). Item scripts then leave the real keychain, gpg-agent and GitHub alone.
maclift_is_sandbox() {
  [ "$(maclift_real_path "$MACLIFT_HOME")" != "$(maclift_real_path "${HOME:-}")" ]
}

# maclift_gnupghome: the gpg home to use. In a sandbox always
# $MACLIFT_HOME/.gnupg, otherwise $GNUPGHOME or ~/.gnupg.
maclift_gnupghome() {
  if maclift_is_sandbox; then
    printf '%s\n' "$MACLIFT_HOME/.gnupg"
  else
    printf '%s\n' "${GNUPGHOME:-$HOME/.gnupg}"
  fi
}

# maclift_note <text>: a note for the user. Appended to $MACLIFT_NOTES when
# set (install_run shows them at the end), else printed to stdout.
maclift_note() {
  if [ -n "${MACLIFT_NOTES:-}" ]; then
    printf '%s\n' "$*" >>"$MACLIFT_NOTES"
  else
    printf '%s\n' "$*"
  fi
}

# While the major version is 0 (below 1.0), refuse to change the real home
# folder unless this is a dry run or --for-real was given.
# Usage: maclift_guard_real_home <dry_run:0|1> <for_real:0|1>
maclift_guard_real_home() {
  local dry_run="${1:-0}" for_real="${2:-0}" major
  major="${MACLIFT_VERSION%%.*}"
  [ "$major" = "0" ] || return 0
  [ "$(maclift_real_path "$MACLIFT_HOME")" = "$(maclift_real_path "$HOME")" ] || return 0
  [ "$dry_run" = "1" ] && return 0
  [ "$for_real" = "1" ] && return 0
  echo "maclift is in development: pass --for-real to change your real home folder" >&2
  return 2
}

# Appends a timestamped line to $MACLIFT_LOG, if set.
log_line() {
  [ -n "${MACLIFT_LOG:-}" ] || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$MACLIFT_LOG"
}

die() {
  echo "✗ $*" >&2
  exit 1
}
