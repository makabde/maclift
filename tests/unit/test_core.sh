#!/usr/bin/env bash
#
# Unit tests for lib/core.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"

test_paths() {
  test_suite "maclift_init_paths"
  (
    MACLIFT_HOME=/tmp/x
    maclift_init_paths
    echo "$MACLIFT_CONFIG_DIR"
  ) >"$TMP_OUT"
  assert_equals "/tmp/x/.config/maclift" "$(cat "$TMP_OUT")" "config dir derives from MACLIFT_HOME"

  (
    unset MACLIFT_HOME
    maclift_init_paths
    echo "$MACLIFT_HOME"
  ) >"$TMP_OUT"
  assert_equals "$HOME" "$(cat "$TMP_OUT")" "MACLIFT_HOME defaults to HOME"

  (
    maclift_init_paths
    echo "$MACLIFT_VERSION"
  ) >"$TMP_OUT"
  assert_equals "$(cat "$PROJECT_ROOT/VERSION")" "$(cat "$TMP_OUT")" "version read from VERSION"

  (
    unset MACLIFT_DIR
    maclift_init_paths
    echo "$MACLIFT_DIR"
  ) >"$TMP_OUT"
  assert_equals "$PROJECT_ROOT" "$(cat "$TMP_OUT")" "MACLIFT_DIR is the repo"
}

test_guard() {
  test_suite "maclift_guard_real_home"
  local err rc
  maclift_init_paths
  MACLIFT_VERSION=0.9.0
  MACLIFT_HOME="$HOME"
  err="$(maclift_guard_real_home 0 0 2>&1 >/dev/null)" && rc=0 || rc=$?
  assert_equals "2" "$rc" "real home, no flags -> exit 2"
  assert_contains "$err" "pass --for-real" "guard message mentions --for-real"

  MACLIFT_HOME="$HOME/"
  maclift_guard_real_home 0 0 2>/dev/null && rc=0 || rc=$?
  assert_equals "2" "$rc" "trailing slash on real home -> exit 2"
  ln -s "$HOME" "$TMP_DIR/homelink"
  MACLIFT_HOME="$TMP_DIR/homelink"
  maclift_guard_real_home 0 0 2>/dev/null && rc=0 || rc=$?
  assert_equals "2" "$rc" "symlink to real home -> exit 2"
  MACLIFT_HOME="$HOME"

  assert_command_succeeds "maclift_guard_real_home 1 0" "dry-run allowed on real home"
  assert_command_succeeds "maclift_guard_real_home 0 1" "--for-real allowed on real home"
  MACLIFT_HOME=/tmp/x
  assert_command_succeeds "maclift_guard_real_home 0 0" "other home allowed"
  MACLIFT_HOME="$HOME"
  MACLIFT_VERSION=1.0.0
  assert_command_succeeds "maclift_guard_real_home 0 0" "1.0: real home, no flags allowed"
}

test_guard_cdpath() {
  test_suite "guard is not fooled by CDPATH"
  local rc fakehome savedhome="$HOME"
  fakehome="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$fakehome/cd/sub"
  ln -s "$fakehome" "$fakehome/cd/sub/h"
  HOME="$fakehome"
  maclift_init_paths
  MACLIFT_VERSION=0.9.0
  # A relative MACLIFT_HOME that CDPATH would resolve (and print) via cd.
  MACLIFT_HOME="sub/h"
  rc=0
  (cd "$fakehome/cd" && CDPATH="$fakehome/cd" maclift_guard_real_home 0 0 2>/dev/null) || rc=$?
  assert_equals "2" "$rc" "relative path to HOME with CDPATH set -> exit 2"
  assert_equals "$fakehome" "$(cd "$fakehome/cd" && CDPATH="$fakehome/cd:$fakehome" maclift_real_path sub/h)" "real path has no cd output"
  HOME="$savedhome"
  MACLIFT_HOME=/tmp/x
}

test_log_and_die() {
  test_suite "log_line and die"
  local log="$TMP_DIR/run.log"
  MACLIFT_LOG="$log"
  log_line "hello"
  assert_contains "$(cat "$log")" "hello" "log_line appends text"
  unset MACLIFT_LOG
  assert_command_succeeds "log_line quiet" "log_line is a no-op without MACLIFT_LOG"

  local out rc
  out="$( (die "boom") 2>&1 )" && rc=0 || rc=$?
  assert_equals "1" "$rc" "die exits 1"
  assert_contains "$out" "✗ boom" "die prints message"
}

test_missing_version_under_set_e() {
  test_suite "missing VERSION falls back to 0.0.0 under set -e"
  local nover="$TMP_DIR/nover" out
  mkdir -p "$nover"
  out="$(
    bash -c 'set -e; source "$1/lib/core.sh"; MACLIFT_DIR="$2" MACLIFT_HOME="$3" maclift_init_paths
      echo "$MACLIFT_VERSION"
      MACLIFT_HOME="$HOME"; maclift_guard_real_home 0 0 2>/dev/null || echo guard-refused' _ "$PROJECT_ROOT" "$nover" "$TMP_DIR/home" 2>&1
  )" || true
  assert_contains "$out" "0.0.0" "version falls back to 0.0.0"
  assert_contains "$out" "guard-refused" "guard still treats it as development"
}

TMP_DIR="$(mktemp -d)"
TMP_OUT="$TMP_DIR/out"
trap 'rm -rf "$TMP_DIR"' EXIT
export MACLIFT_HOME="$TMP_DIR/home"
mkdir -p "$MACLIFT_HOME"

test_paths
test_guard
test_guard_cdpath
test_missing_version_under_set_e
test_log_and_die
test_summary
