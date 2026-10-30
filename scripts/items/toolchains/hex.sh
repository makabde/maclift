#!/usr/bin/env bash
#
# maclift item: Hex package manager for Elixir.
#   hex.sh --check   exit 0 when mix has the hex archive
#   hex.sh           install it with mix local.hex; exit 3 (skipped) when elixir is missing
# Works through mix/elixir on PATH after toolchain_path_setup. Test overrides:
# MACLIFT_MIX, MACLIFT_ELIXIR.

set -eo pipefail

MACLIFT_DIR="${MACLIFT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=lib/core.sh
source "$MACLIFT_DIR/lib/core.sh"
# shellcheck source=lib/toolchain.sh
source "$MACLIFT_DIR/lib/toolchain.sh"
maclift_init_paths
toolchain_path_setup

if [ "${1:-}" = "--check" ]; then
  toolchain_archives 2>/dev/null | grep -q 'hex-'
  exit $?
fi

toolchain_needs elixir toolchain_elixir --version
toolchain_mix local.hex --force
