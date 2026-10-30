#!/usr/bin/env bash
#
# Guard: no personal data in tracked files
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACLIFT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=tests/lib/leak-scan.sh
source "$SCRIPT_DIR/../lib/leak-scan.sh"

test_generic_leaks() {
  test_suite "No generic personal data in tracked files"
  local hits
  hits="$(_scan_generic "$MACLIFT_DIR")" || true
  assert_equals "" "$hits" "no foreign email, private key header or /Users/<name> path"
}

# Reads the owner's real private-patterns file (read-only) when it exists, by design.
test_owner_patterns() {
  test_suite "No owner patterns in tracked files"
  local hits rc=0
  hits="$(_scan_patterns "$MACLIFT_DIR" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 3 ]; then
    _owner_patterns_missing_notice
    return 0
  fi
  assert_not_equals "2" "$rc" "owner pattern scan did not error"
  assert_equals "" "$hits" "no owner pattern matches"
}

test_private_patterns_from_env() {
  test_suite "Private patterns come from the environment"
  local repo hits rc
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  printf 'hello zzleakzz world\n' >"$repo/f.txt"
  git -C "$repo" add f.txt
  rc=0
  hits="$(MACLIFT_PRIVATE_PATTERNS=$'zzleakzz' MACLIFT_PRIVATE_PATTERNS_FILE="$repo/none" _scan_patterns "$repo")" || rc=$?
  assert_not_equals "" "$hits" "tracked file with the pattern is a hit"
  assert_equals "1" "$rc" "hit returns 1"
  rc=0
  hits="$(MACLIFT_SCAN_DIR="$repo" MACLIFT_PRIVATE_PATTERNS=$'zzleakzz' MACLIFT_PRIVATE_PATTERNS_FILE="$repo/none" _scan_patterns)" || rc=$?
  assert_not_equals "" "$hits" "MACLIFT_SCAN_DIR override is used"
  git -C "$repo" rm -q -f f.txt
  rc=0
  hits="$(MACLIFT_PRIVATE_PATTERNS=$'zzleakzz' MACLIFT_PRIVATE_PATTERNS_FILE="$repo/none" _scan_patterns "$repo")" || rc=$?
  assert_equals "" "$hits" "no hit once the file is gone"
  assert_equals "0" "$rc" "no hit returns 0"
  rm -rf "$repo"
}

test_private_patterns_from_file() {
  test_suite "Private patterns come from the file"
  local d out
  d="$(mktemp -d)"
  printf '# comment\n\nfirstpat\nsecond.pat\n' >"$d/pats"
  out="$(unset MACLIFT_PRIVATE_PATTERNS; MACLIFT_PRIVATE_PATTERNS_FILE="$d/pats" _private_patterns)"
  assert_equals $'firstpat\nsecond.pat' "$out" "comments and blank lines ignored"
  out="$(MACLIFT_PRIVATE_PATTERNS=$'envpat' MACLIFT_PRIVATE_PATTERNS_FILE="$d/pats" _private_patterns)"
  assert_equals "envpat" "$out" "env wins over the file"
  rm -rf "$d"
}

test_private_patterns_missing_is_reported() {
  test_suite "Missing owner patterns are reported, not fatal"
  local d out rc=0
  d="$(mktemp -d)"
  out="$(unset MACLIFT_PRIVATE_PATTERNS; MACLIFT_PRIVATE_PATTERNS_FILE="$d/none" _private_patterns)"
  assert_equals "" "$out" "no source gives no patterns"
  assert_equals "owner patterns not found; only generic checks ran" "$(_owner_patterns_missing_notice)" "notice text"
  git -C "$d" init -q
  printf 'x\n' >"$d/f.txt"
  git -C "$d" add f.txt
  out="$(unset MACLIFT_PRIVATE_PATTERNS; MACLIFT_PRIVATE_PATTERNS_FILE="$d/none" _scan_patterns "$d" 2>/dev/null)" || rc=$?
  assert_equals "3" "$rc" "no patterns returns 3, not clean"
  assert_equals "" "$out" "no patterns prints no hits (empty pattern is skipped)"
  rm -rf "$d"
}

test_scan_errors_fail_closed() {
  test_suite "Scan errors are errors, not clean"
  local d rc
  d="$(mktemp -d)"
  git -C "$d" init -q
  printf 'x\n' >"$d/f.txt"
  git -C "$d" add f.txt
  rc=0
  MACLIFT_PRIVATE_PATTERNS='(unclosed' _scan_patterns "$d" >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "invalid regex returns 2"
  local np
  np="$(mktemp -d)"
  rc=0
  MACLIFT_PRIVATE_PATTERNS='x' _scan_patterns "$np" >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "non-repo dir returns 2"
  rm -rf "$np"
  rc=0
  MACLIFT_PRIVATE_PATTERNS='x' _scan_patterns "$d/../nonexistent-$$" >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "missing dir returns 2"
  rc=0
  _scan_generic "$d/../nonexistent-$$" >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "generic: missing dir returns 2"
  rm -rf "$d"
}

test_cache_stays_out_of_repo() {
  test_suite "Completion cache stays out of the repo"
  local hits
  hits="$(git -C "$MACLIFT_DIR" grep -n -F '.zsh/cache' -- dotfiles || true)"
  assert_equals "" "$hits" "no tracked dotfile references .zsh/cache"
  if git -C "$MACLIFT_DIR" check-ignore -q dotfiles/shell/zsh/cache/brew_formulae; then
    assert_equals "ignored" "ignored" "zsh cache dir is gitignored"
  else
    assert_equals "ignored" "not ignored" "zsh cache dir is gitignored"
  fi
}

test_phoenix_template_exists() {
  test_suite "Phoenix template referenced by phoenix_helpers exists"
  local ref rel
  ref="$(grep -o '\.maclift/templates/[^"]*' "$MACLIFT_DIR/dotfiles/shell/zsh/functions/phoenix_helpers" | head -n1)"
  rel="${ref#.maclift/}"
  assert_not_equals "" "$rel" "phoenix_helpers references a template"
  assert_file_exists "$MACLIFT_DIR/$rel" "template $rel exists in repo"
}

test_generic_leaks
test_owner_patterns
test_private_patterns_from_env
test_private_patterns_from_file
test_private_patterns_missing_is_reported
test_scan_errors_fail_closed
test_cache_stays_out_of_repo
test_phoenix_template_exists
test_summary
