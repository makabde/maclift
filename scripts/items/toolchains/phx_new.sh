#!/usr/bin/env bash
#
# maclift item: Phoenix project generator (mix phx.new).
#   phx_new.sh --check   exit 0 when mix has the phx_new archive
#   phx_new.sh           install it with mix archive.install; exit 3 (skipped) when elixir is missing
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

has_archive() { toolchain_archives 2>/dev/null | grep -q "$1-"; }

if [ "${1:-}" = "--check" ]; then
  has_archive phx_new
  exit $?
fi

toolchain_needs elixir toolchain_elixir --version
toolchain_needs hex has_archive hex
toolchain_mix archive.install hex phx_new --force

if ! command -v docker >/dev/null 2>&1 && ! command -v psql >/dev/null 2>&1; then
  maclift_note "Phoenix needs Postgres: turn on Docker Desktop and use the phoenix-docker template, or brew install postgresql@17"
fi
