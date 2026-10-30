#!/usr/bin/env bash
#
# Unit tests for lib/preflight.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/preflight.sh
source "$PROJECT_ROOT/lib/preflight.sh"

MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
STUBS="$(mktemp -d)"
trap 'rm -rf "$MACLIFT_HOME" "$STUBS"' EXIT

mk_stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUBS/$1"; chmod +x "$STUBS/$1"; }

# Writes df -g style output reporting $1 GB available.
mk_df() {
  mk_stub df "printf 'Filesystem 1G-blocks Used Available Capacity Mounted on\n/dev/disk3s1 460 100 $1 30%% /\n'"
}

run_pf() { # uname_out sw_vers_out df_gb
  mk_stub uname "echo $1"
  mk_stub sw_vers "echo $2"
  mk_df "$3"
  MACLIFT_UNAME="$STUBS/uname" MACLIFT_SW_VERS="$STUBS/sw_vers" MACLIFT_DF="$STUBS/df" \
    preflight_check 2>&1
}

test_preflight() {
  test_suite "preflight_check"
  local out rc

  rc=0; out="$(run_pf arm64 13.6 100)" || rc=$?
  assert_equals "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "macOS 13.6 fails"
  case "$out" in *"macOS 14 or newer"*) rc=0 ;; *) rc=1 ;; esac
  assert_equals "0" "$rc" "macOS 13.6 message says macOS 14 or newer"

  rc=0; out="$(run_pf arm64 14.2 10)" || rc=$?
  assert_equals "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "10 GB free fails"
  case "$out" in *"20 GB"*) rc=0 ;; *) rc=1 ;; esac
  assert_equals "0" "$rc" "low disk message mentions 20 GB"

  rc=0; out="$(run_pf arm64 15.1 100)" || rc=$?
  assert_equals "0" "$rc" "arm64 on macOS 15 passes"
  case "$out" in *"Apple silicon"*) rc=0 ;; *) rc=1 ;; esac
  assert_equals "0" "$rc" "arm64 prints Apple silicon"

  rc=0; out="$(run_pf x86_64 14.0 100)" || rc=$?
  assert_equals "0" "$rc" "x86_64 on macOS 14 passes"
  case "$out" in *"Intel"*) rc=0 ;; *) rc=1 ;; esac
  assert_equals "0" "$rc" "x86_64 prints Intel"
}

test_preflight
test_summary
