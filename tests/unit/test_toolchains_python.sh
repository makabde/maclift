#!/usr/bin/env bash
#
# Unit tests for scripts/items/toolchains/python.sh
# (uv is a stub; nothing touches the network or a real uv)
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
  export MACLIFT_UV="$PROJECT_ROOT/tests/stubs/uv"
  export MACLIFT_NEED_FILE="$T/need" MACLIFT_NOTES="$T/notes"
  unset MACLIFT_RUN_ID MACLIFT_LOG UV_PYTHON_BIN_DIR UV_PYTHON_INSTALL_DIR XDG_CONFIG_HOME
  : >"$T/notes"
  mkdir -p "$T/tools"
  local t p
  for t in bash env grep cat dirname basename mkdir tr sed awk date uname rm ls mktemp chmod cut sort head tail wc id printf; do
    p="$(command -v "$t" 2>/dev/null || true)"
    case "$p" in /*) ln -sf "$p" "$T/tools/$t" ;; esac
  done
  ITEM_PATH="$T/bin:$T/tools"
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
}
run_item() {
  RC=0
  PATH="$ITEM_PATH" bash "$ITEMS/$1" "${@:2}" >/dev/null 2>&1 || RC=$?
}

test_python_uv_mode() {
  test_suite "python.sh uv mode"
  fresh_env
  run_item python.sh --check
  assert_equals "1" "$RC" "check fails before"
  run_item python.sh
  assert_equals "0" "$RC" "install exits 0"
  assert_contains "$(cat "$T/stub/uv.calls")" "python install --default" "installed as default"
  assert_contains "$(cat "$T/stub/uv.calls")" "python pin --global 3.14.0" "pinned the installed version"
  assert_equals "3.14.0" "$(cat "$MACLIFT_HOME/.config/uv/.python-version")" "pin file content"
  run_item python.sh --check
  assert_equals "0" "$RC" "check passes after"
}

test_python_asdf_mode() {
  test_suite "python.sh asdf mode (~/.tool-versions)"
  fresh_env
  echo "python 3.13.5" >"$MACLIFT_HOME/.tool-versions"
  run_item python.sh --check
  assert_equals "1" "$RC" "check fails before"
  run_item python.sh
  assert_equals "0" "$RC" "install exits 0"
  assert_contains "$(cat "$T/stub/uv.calls")" "python install" "ran python install"
  assert_command_fails "grep -q -e '--default' -e pin '$T/stub/uv.calls'" "no default, no pin"
  run_item python.sh --check
  assert_equals "0" "$RC" "check passes after"
}

test_python_asdf_mode_by_pin() {
  test_suite "python.sh asdf mode (pin)"
  fresh_env
  echo "python 3.13.5" >"$MACLIFT_CONFIG_DIR/tool-versions"
  run_item python.sh
  assert_equals "0" "$RC" "install exits 0"
  assert_contains "$(cat "$T/stub/uv.calls")" "python install" "ran python install"
  assert_command_fails "grep -q -e '--default' -e pin '$T/stub/uv.calls'" "no default, no pin"
}

test_python_needs_uv() {
  test_suite "python.sh needs uv"
  fresh_env
  MACLIFT_UV=/nonexistent run_item python.sh
  assert_equals "3" "$RC" "exits 3"
  assert_equals "uv" "$(cat "$T/need")" "reason is uv"
}

test_python_sandbox_paths() {
  test_suite "python.sh stays inside the sandbox"
  fresh_env
  local real="$T/realhome"
  mkdir -p "$real"
  HOME="$real" run_item python.sh
  assert_equals "0" "$RC" "install exits 0"
  assert_command_succeeds "[ -x '$MACLIFT_HOME/.local/bin/python' ]" "python under MACLIFT_HOME"
  assert_equals "" "$(ls -A "$real")" "nothing created under HOME"
}

test_python_uv_mode
test_python_asdf_mode
test_python_asdf_mode_by_pin
test_python_needs_uv
test_python_sandbox_paths
test_summary
