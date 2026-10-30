#!/usr/bin/env bash
#
# Unit tests for scripts/items/toolchains/{hex,rebar,phx_new}.sh
# (mix and elixir are stubs; nothing touches the network)
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
for f in core conf catalog ui dotfiles asdf install; do
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$f.sh"
done

export MACLIFT_DIR="$PROJECT_ROOT"
TMP_DIR="$(mktemp -d)"
ITEMS="$PROJECT_ROOT/scripts/items/toolchains"

fresh_env() {
  T="$(mktemp -d "$TMP_DIR/t.XXXXXX")"
  mkdir -p "$T/home" "$T/stub" "$T/bin"
  export MACLIFT_HOME="$T/home" HOME="$T/home" MACLIFT_STUB_DIR="$T/stub"
  export MACLIFT_MIX="$PROJECT_ROOT/tests/stubs/mix"
  export MACLIFT_ELIXIR="$PROJECT_ROOT/tests/stubs/elixir"
  export MACLIFT_NEED_FILE="$T/need" MACLIFT_NOTES="$T/notes"
  unset MACLIFT_RUN_ID MACLIFT_LOG
  : >"$T/notes"
  # A PATH with only the basic tools, so no real docker or psql shows up.
  mkdir -p "$T/tools"
  local t p
  for t in bash env grep cat dirname basename mkdir tr sed awk date uname rm ls mktemp chmod cut sort head tail wc id printf; do
    p="$(command -v "$t" 2>/dev/null || true)"
    case "$p" in /*) ln -sf "$p" "$T/tools/$t" ;; esac
  done
  ITEM_PATH="$T/bin:$T/tools"
  maclift_init_paths
}
# run_item <name> [args]: prints nothing, sets RC.
run_item() {
  RC=0
  PATH="$ITEM_PATH" bash "$ITEMS/$1" "${@:2}" >/dev/null 2>&1 || RC=$?
}

test_hex_installs_then_checks() {
  test_suite "hex.sh installs then checks"
  fresh_env
  run_item hex.sh --check
  assert_equals "1" "$RC" "check fails before"
  run_item hex.sh
  assert_equals "0" "$RC" "install exits 0"
  assert_contains "$(cat "$T/stub/mix.calls")" "local.hex --force" "ran local.hex"
  run_item hex.sh --check
  assert_equals "0" "$RC" "check passes after"
}

test_hex_needs_elixir() {
  test_suite "hex.sh needs elixir"
  fresh_env
  touch "$T/stub/no-elixir"
  run_item hex.sh --check
  assert_equals "1" "$RC" "check exits 1 (not 3) without elixir"
  run_item hex.sh
  assert_equals "3" "$RC" "exits 3"
  assert_equals "elixir" "$(cat "$T/need")" "reason is elixir"
  assert_command_fails "grep -q local.hex '$T/stub/mix.calls'" "no local.hex call"
}

test_rebar_installs_then_checks() {
  test_suite "rebar.sh installs then checks"
  fresh_env
  run_item rebar.sh --check
  assert_equals "1" "$RC" "check fails before"
  run_item rebar.sh
  assert_equals "0" "$RC" "install exits 0"
  assert_contains "$(cat "$T/stub/mix.calls")" "local.rebar --force" "ran local.rebar"
  run_item rebar.sh --check
  assert_equals "0" "$RC" "check passes after"
  fresh_env
  touch "$T/stub/no-elixir"
  run_item rebar.sh
  assert_equals "3" "$RC" "exits 3 without elixir"
  assert_equals "elixir" "$(cat "$T/need")" "reason is elixir"
  assert_command_fails "grep -q local.rebar '$T/stub/mix.calls'" "no local.rebar call"
}

test_phx_new_needs_hex() {
  test_suite "phx_new.sh needs hex"
  fresh_env
  run_item phx_new.sh
  assert_equals "3" "$RC" "exits 3"
  assert_equals "hex" "$(cat "$T/need")" "reason is hex"
  assert_command_fails "grep -q archive.install '$T/stub/mix.calls'" "no archive.install"
  fresh_env
  touch "$T/stub/no-elixir"
  run_item phx_new.sh
  assert_equals "elixir" "$(cat "$T/need")" "elixir checked first"
}

test_phx_new_installs_and_notes_postgres() {
  test_suite "phx_new.sh installs and notes Postgres"
  fresh_env
  echo "hex-2.2.1" >"$T/stub/mix.archives"
  run_item phx_new.sh --check
  assert_equals "1" "$RC" "check fails before"
  run_item phx_new.sh
  assert_equals "0" "$RC" "exits 0"
  assert_contains "$(cat "$T/stub/mix.calls")" "archive.install hex phx_new --force" "ran archive.install"
  assert_contains "$(cat "$T/notes")" "Phoenix needs Postgres" "postgres note"
  run_item phx_new.sh --check
  assert_equals "0" "$RC" "check passes after"
}

test_phx_new_no_note_with_docker() {
  test_suite "phx_new.sh no note when docker is on PATH"
  fresh_env
  echo "hex-2.2.1" >"$T/stub/mix.archives"
  printf '#!/bin/sh\nexit 0\n' >"$T/bin/docker"
  chmod +x "$T/bin/docker"
  run_item phx_new.sh
  assert_equals "0" "$RC" "exits 0"
  assert_equals "" "$(cat "$T/notes")" "no note"
}

test_elixir_chain_through_runner() {
  test_suite "elixir items chain through install_run"
  fresh_env
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
  install_run 0 script:phx_new script:rebar script:hex >/dev/null 2>&1 || true
  local order
  order="$(grep -E '^(local\.|archive\.install)' "$T/stub/mix.calls" | tr '\n' '|')"
  assert_equals "local.hex --force|local.rebar --force|archive.install hex phx_new --force|" "$order" "hex, rebar, then phx_new"
}

test_hex_installs_then_checks
test_hex_needs_elixir
test_rebar_installs_then_checks
test_phx_new_needs_hex
test_phx_new_installs_and_notes_postgres
test_phx_new_no_note_with_docker
test_elixir_chain_through_runner
test_summary
