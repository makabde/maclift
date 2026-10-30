#!/usr/bin/env bash
#
# maclift item: rebar3 for Mix, to build Erlang dependencies.
#   rebar.sh --check   exit 0 when Mix has an executable rebar3
#   rebar.sh           install it with mix local.rebar; exit 3 (skipped) when elixir is missing
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
  mixhome="$(toolchain_elixir -e 'IO.puts(Mix.Utils.mix_home())' 2>/dev/null)" || exit 1
  [ -n "$mixhome" ] || exit 1
  for f in "$mixhome"/elixir/*/rebar3; do
    [ -x "$f" ] && exit 0
  done
  exit 1
fi

toolchain_needs elixir toolchain_elixir --version
toolchain_mix local.rebar --force
