#!/usr/bin/env bash
#
# maclift item: default Python, managed by uv.
#   python.sh --check   exit 0 when the Python for the chosen mode is in place
#   python.sh           install it; exit 3 (skipped) when uv is missing
# uv mode (default): uv python install --default, then pin that version
# globally. asdf mode (python in the maclift pins or ~/.tool-versions): only install a
# uv Python for uv's own use; the asdf Python is never touched.
# Test overrides: MACLIFT_UV.

set -eo pipefail

MACLIFT_DIR="${MACLIFT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=lib/core.sh
source "$MACLIFT_DIR/lib/core.sh"
# shellcheck source=lib/conf.sh
source "$MACLIFT_DIR/lib/conf.sh"
# shellcheck source=lib/catalog.sh
source "$MACLIFT_DIR/lib/catalog.sh"
# shellcheck source=lib/asdf.sh
source "$MACLIFT_DIR/lib/asdf.sh"
# shellcheck source=lib/toolchain.sh
source "$MACLIFT_DIR/lib/toolchain.sh"
maclift_init_paths
toolchain_path_setup

# In a sandbox keep uv's files under MACLIFT_HOME.
if [ "$MACLIFT_HOME" != "$HOME" ]; then
  export UV_PYTHON_INSTALL_DIR="$MACLIFT_HOME/.local/share/uv/python"
  export UV_PYTHON_BIN_DIR="$MACLIFT_HOME/.local/bin"
  export XDG_CONFIG_HOME="$MACLIFT_HOME/.config"
fi
bin="${UV_PYTHON_BIN_DIR:-$HOME/.local/bin}"
pinfile="${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version"

if toolchain_python_asdf_chosen; then
  if [ "${1:-}" = "--check" ]; then
    [ -n "$(toolchain_uv python list --only-installed 2>/dev/null)" ]
    exit $?
  fi
  toolchain_needs uv toolchain_uv --version
  toolchain_uv python install
  exit 0
fi

if [ "${1:-}" = "--check" ]; then
  "$bin/python" --version >/dev/null 2>&1 && [ -e "$pinfile" ]
  exit $?
fi

toolchain_needs uv toolchain_uv --version
toolchain_uv python install --default
if [ ! -x "$bin/python" ]; then
  echo "uv did not create $bin/python; check uv python install --default on this uv version" >&2
  exit 1
fi
v="$("$bin/python" -c 'import platform; print(platform.python_version())')"
if ! _pins_version_ok "$v"; then
  echo "unexpected Python version from $bin/python: $v" >&2
  exit 1
fi
toolchain_uv python pin --global "$v"
