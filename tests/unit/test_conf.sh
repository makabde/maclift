#!/usr/bin/env bash
#
# Unit tests for lib/conf.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/conf.sh
source "$PROJECT_ROOT/lib/conf.sh"

test_round_trip() {
  test_suite "conf_set / conf_get round trip"
  local f="$TMP_DIR/rt/sub/user.conf" v
  local -a values=("Seán O'Brien" 'a"b\c' "" '$(touch '"$TMP_DIR"'/pwned)' '`id` $HOME \\ "' "trailing\\")
  local i=0
  for v in "${values[@]}"; do
    conf_set "$f" "MACLIFT_V$i" "$v"
    assert_equals "$v" "$(conf_get "$f" "MACLIFT_V$i")" "round trip value $i"
    i=$((i + 1))
  done
  assert_file_exists "$f" "conf_set creates file and parent dir"
  assert_command_fails "[ -e '$TMP_DIR/pwned' ]" "round trip executed nothing"
}

test_no_execution() {
  test_suite "conf_get never executes content"
  local f="$TMP_DIR/evil.conf"
  printf '%s\n' 'MACLIFT_NAME="$(touch '"$TMP_DIR"'/pwned)"' >"$f"
  printf '%s\n' 'MACLIFT_B="`touch '"$TMP_DIR"'/pwned2`"' >>"$f"
  conf_get "$f" MACLIFT_NAME >/dev/null
  conf_get "$f" MACLIFT_B >/dev/null
  assert_command_fails "[ -e '$TMP_DIR/pwned' ]" "command substitution not run"
  assert_command_fails "[ -e '$TMP_DIR/pwned2' ]" "backticks not run"
  assert_equals "\$(touch $TMP_DIR/pwned)" "$(conf_get "$f" MACLIFT_NAME)" "value returned literally"
}

test_ignored_lines() {
  test_suite "ignored lines and comments"
  local f="$TMP_DIR/ign.conf" err
  printf '%s\n' 'rm -rf /' 'GOOD="1"' '# comment' '' 'lower="x"' 'BAD="unterminated' >"$f"
  err="$(conf_keys "$f" 2>&1 >/dev/null)"
  assert_contains "$err" "ignored line 1" "warning names line 1"
  assert_contains "$err" "ignored line 5" "lowercase key warned"
  assert_contains "$err" "ignored line 6" "unterminated warned"
  assert_equals "GOOD" "$(conf_keys "$f" 2>/dev/null)" "only valid keys listed"
  assert_equals "1" "$(conf_get "$f" GOOD 2>/dev/null)" "valid line still read"
}

test_set_existing() {
  test_suite "conf_set on existing key"
  local f="$TMP_DIR/ex.conf"
  printf '%s\n' '# head' 'A="1"' 'B="2"' 'C="3"' >"$f"
  conf_set "$f" B 'new "v"'
  assert_equals '# head
A="1"
B="new \"v\""
C="3"' "$(cat "$f")" "other lines kept in order"
  conf_set "$f" D "4"
  assert_equals "D" "$(conf_keys "$f" | tail -n1)" "new key appended"
  assert_equals "4" "$(conf_keys "$f" | wc -l | tr -d ' ')" "four keys"
}

test_missing() {
  test_suite "missing key / file"
  local f="$TMP_DIR/m.conf" rc
  printf '%s\n' 'A="1"' >"$f"
  conf_get "$f" NOPE >/dev/null && rc=0 || rc=$?
  assert_equals "1" "$rc" "missing key returns 1"
  conf_get "$TMP_DIR/none.conf" A >/dev/null && rc=0 || rc=$?
  assert_equals "1" "$rc" "missing file returns 1"
  conf_set "$f" "bad key" x 2>/dev/null && rc=0 || rc=$?
  assert_equals "1" "$rc" "invalid key rejected by conf_set"
  conf_set "$f" A "line1
line2" 2>/dev/null && rc=0 || rc=$?
  assert_equals "1" "$rc" "newline in value rejected"
  assert_equals "1" "$(conf_get "$f" A)" "value untouched after rejection"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

test_round_trip
test_no_execution
test_ignored_lines
test_set_existing
test_missing
test_summary
