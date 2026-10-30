#!/usr/bin/env bash
#
# maclift toolchain helpers for language tool items (hex, rebar, phx_new,
# python via uv). Item scripts source this after lib/core.sh. Every external
# tool is reached through an override variable so tests can use stubs.
# bash 3.2 compatible.

# toolchain_path_setup: make asdf shims and ~/.local/bin win on PATH (once
# each), and cd to $MACLIFT_HOME so the ~/.tool-versions pins resolve.
toolchain_path_setup() {
  local d
  for d in "$MACLIFT_HOME/.local/bin" "${ASDF_DATA_DIR:-$HOME/.asdf}/shims"; do
    case ":$PATH:" in
      *":$d:"*) ;;
      *) PATH="$d:$PATH" ;;
    esac
  done
  export PATH
  cd "$MACLIFT_HOME" || return 1
}

toolchain_mix() { "${MACLIFT_MIX:-mix}" "$@"; }
toolchain_elixir() { "${MACLIFT_ELIXIR:-elixir}" "$@"; }
toolchain_uv() { "${MACLIFT_UV:-uv}" "$@"; }
toolchain_pnpm() { "${MACLIFT_PNPM:-pnpm}" "$@"; }
toolchain_node() { "${MACLIFT_NODE:-node}" "$@"; }

# toolchain_needs <label> <cmd...>: when cmd fails, tell the installer this
# item is skipped for a missing runtime (name in $MACLIFT_NEED_FILE, exit 3).
toolchain_needs() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${MACLIFT_NEED_FILE:-}" ]; then
    printf '%s\n' "$label" >"$MACLIFT_NEED_FILE"
  fi
  echo "needs $label"
  exit 3
}

# toolchain_archives: installed mix archives, lines like "* hex-2.2.1".
toolchain_archives() { toolchain_mix archive; }

# toolchain_has_archive <name>: true when mix lists the archive <name>-<ver>.
# Captures the output first: a `| grep -q` closes the pipe early, mix then
# exits 1, and pipefail would turn the match into a miss. The exit status of
# mix is ignored for the same reason.
toolchain_has_archive() {
  local a
  a="$(toolchain_archives 2>/dev/null)" || true
  case "$a" in
    *"* $1-"*) return 0 ;;
  esac
  return 1
}

# toolchain_python_asdf_chosen: true when the user picked asdf for Python:
# asdf:python is in the saved selection, or python is already pinned.
# Needs lib/conf.sh, lib/catalog.sh and lib/asdf.sh sourced by the caller.
toolchain_python_asdf_chosen() {
  local items w
  items="$(conf_get "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS 2>/dev/null || true)"
  for w in $items; do
    [ "$w" = "asdf:python" ] && return 0
  done
  _pins_read "$(_pins_file)" python >/dev/null 2>&1
}
