#!/usr/bin/env bash
#
# Unit tests for lib/toolchain.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=lib/toolchain.sh
source "$PROJECT_ROOT/lib/toolchain.sh"

test_path_setup_prepends_shims() {
  test_suite "toolchain_path_setup prepends shims and local bin once"
  local t
  t="$(mktemp -d)"
  (
    export MACLIFT_HOME="$t/home" ASDF_DATA_DIR="$t/asdf" PATH=/usr/bin:/bin
    mkdir -p "$MACLIFT_HOME"
    toolchain_path_setup
    toolchain_path_setup
    case "$PATH" in
      "$t/asdf/shims:$MACLIFT_HOME/.local/bin:/usr/bin:/bin") echo ok-path ;;
      *) echo "bad-path $PATH" ;;
    esac
    [ "$(pwd -P)" = "$(cd "$MACLIFT_HOME" && pwd -P)" ] && echo ok-pwd
  ) >"$t/out"
  assert_contains "$(cat "$t/out")" "ok-path" "PATH has shims then local bin, no duplicates"
  assert_contains "$(cat "$t/out")" "ok-pwd" "cwd is MACLIFT_HOME"
}

test_needs_writes_reason() {
  test_suite "toolchain_needs records the missing runtime and exits 3"
  local t rc=0
  t="$(mktemp -d)"
  (MACLIFT_NEED_FILE="$t/need" toolchain_needs elixir false) >/dev/null || rc=$?
  assert_equals "3" "$rc" "exit 3 when the check fails"
  assert_equals "elixir" "$(cat "$t/need")" "need file holds the label"
  rc=0
  (MACLIFT_NEED_FILE="$t/need2" toolchain_needs elixir true) || rc=$?
  assert_equals "0" "$rc" "returns 0 when the check passes"
  assert_command_fails "[ -e '$t/need2' ]" "no need file on success"
}

test_has_archive() {
  test_suite "toolchain_has_archive"
  local t
  t="$(mktemp -d)"
  printf '#!/bin/sh\nprintf "Archives available in x:\\n* hex-2.2.1\\n* myhex-1.0\\n"\n' >"$t/mix"
  chmod +x "$t/mix"
  (
    set -o pipefail
    export MACLIFT_MIX="$t/mix"
    toolchain_has_archive hex && echo hex-yes
    toolchain_has_archive hex2 || echo hex2-no
  ) >"$t/out"
  assert_contains "$(cat "$t/out")" "hex-yes" "matches '* hex-2.2.1'"
  assert_contains "$(cat "$t/out")" "hex2-no" "no prefix match on a different name"
  printf '#!/bin/sh\nprintf "* myhex-1.0\\n"\n' >"$t/mix"
  assert_command_fails "MACLIFT_MIX='$t/mix' bash -c 'source \"$PROJECT_ROOT/lib/toolchain.sh\"; toolchain_has_archive hex'" "anchored: myhex-1.0 is not hex"
  printf '#!/bin/sh\nprintf "* hex-2.2.1\\nTrailer\\n"\nexit 1\n' >"$t/mix"
  assert_command_succeeds "set -o pipefail; MACLIFT_MIX='$t/mix' bash -c 'source \"$PROJECT_ROOT/lib/toolchain.sh\"; set -o pipefail; toolchain_has_archive hex'" "producer exiting 1 after the line still counts"
  printf '#!/bin/sh\nexit 1\n' >"$t/mix"
  assert_command_fails "MACLIFT_MIX='$t/mix' bash -c 'source \"$PROJECT_ROOT/lib/toolchain.sh\"; toolchain_has_archive hex'" "failing mix with no output is a miss"
}

test_path_setup_prepends_shims
test_needs_writes_reason
test_has_archive
test_summary
