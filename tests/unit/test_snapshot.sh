#!/usr/bin/env bash
#
# Unit tests for lib/snapshot.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=lib/conf.sh
source "$PROJECT_ROOT/lib/conf.sh"
# shellcheck source=lib/catalog.sh
source "$PROJECT_ROOT/lib/catalog.sh"
# shellcheck source=lib/selection.sh
source "$PROJECT_ROOT/lib/selection.sh"
# shellcheck source=lib/ui.sh
source "$PROJECT_ROOT/lib/ui.sh"
# shellcheck source=lib/dotfiles.sh
source "$PROJECT_ROOT/lib/dotfiles.sh"
# shellcheck source=lib/asdf.sh
source "$PROJECT_ROOT/lib/asdf.sh"
# shellcheck source=lib/install.sh
source "$PROJECT_ROOT/lib/install.sh"
# shellcheck source=lib/localbrew.sh
source "$PROJECT_ROOT/lib/localbrew.sh"
# shellcheck source=lib/snapshot.sh
source "$PROJECT_ROOT/lib/snapshot.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
mkdir -p "$MACLIFT_CONFIG_DIR"
F="$MACLIFT_CONFIG_DIR/Brewfile.local"
STUB="$(mktemp -d)"
export MACLIFT_STUB_DIR="$STUB" MACLIFT_BREW="$PROJECT_ROOT/tests/stubs/brew"
export MACLIFT_MAS="$PROJECT_ROOT/tests/stubs/mas" MACLIFT_PLAIN=1
unset MACLIFT_ASSUME_YES

reset_stub() {
  rm -f "$STUB"/brew.* "$STUB"/mas.* "$F"
  printf 'bat\nfiglet\nowner/tap/thing\n' >"$STUB/brew.leaves"
  printf 'iterm2\nzoom\n' >"$STUB/brew.cask-list"
  printf '497799835 Xcode (16.0)\n1295203466 Microsoft Remote Desktop (10.9.5)\n' >"$STUB/mas.list"
  printf 'cask "zoom"\n' >"$F"
}

EXPECTED=$'brew:figlet\tfiglet\nbrew:owner/tap/thing\towner/tap/thing\nmas:1295203466\tMicrosoft Remote Desktop\nmas:497799835\tXcode'

test_candidates() {
  test_suite "snapshot_candidates"
  reset_stub
  assert_equals "$EXPECTED" "$(snapshot_candidates)" "unknown packages, sorted"
  MACLIFT_MAS="$STUB/no-such-mas"
  assert_equals "$(printf '%s\n' "$EXPECTED" | grep -v '^mas:')" "$(snapshot_candidates)" "no mas command: no mas candidates"
  MACLIFT_MAS="$PROJECT_ROOT/tests/stubs/mas"
}

test_cmd_snapshot() {
  test_suite "cmd_snapshot"
  reset_stub
  local out before
  before="$(cat "$F")"
  out="$(cmd_snapshot 1 2>&1 </dev/null)" || true
  assert_equals "$before" "$(cat "$F")" "dry run writes nothing"
  out="$(MACLIFT_ASSUME_YES=1 cmd_snapshot 1 2>&1)"
  assert_contains "$out" 'would add to' "dry run lists what it would add"
  assert_equals "$before" "$(cat "$F")" "dry run with -y writes nothing"
  out="$(MACLIFT_ASSUME_YES=1 cmd_snapshot 0 2>&1)"
  assert_contains "$out" "Saved 4 package(s)" "reports the count"
  assert_contains "$(cat "$F")" 'brew "figlet"' "brew line"
  assert_contains "$(cat "$F")" 'brew "owner/tap/thing"' "tap line kept"
  assert_contains "$(cat "$F")" 'mas "Xcode", id: 497799835' "mas line"
  assert_contains "$(cat "$F")" 'mas "Microsoft Remote Desktop", id: 1295203466' "mas name with spaces"
  assert_contains "$(cat "$F")" 'added by maclift snapshot on' "comment"
  assert_equals "4" "$(install_brewfile_local 2>/dev/null | grep -c -e figlet -e owner/tap/thing -e mas:)" "install_brewfile_local lists them"
  out="$(MACLIFT_ASSUME_YES=1 cmd_snapshot 0 2>&1)"
  assert_contains "$out" "Nothing to save" "second run has nothing"
}

test_mas_quote() {
  test_suite "cmd_snapshot skips mas names with a quote"
  reset_stub
  printf '1 Bad "Name" (1.0)\n2 Good (1.0)\n' >"$STUB/mas.list"
  printf '' >"$STUB/brew.leaves"
  : >"$STUB/brew.cask-list"
  local out
  out="$(MACLIFT_ASSUME_YES=1 cmd_snapshot 0 2>&1)"
  assert_contains "$out" "warning: skipping mas:1: name contains a quote" "warns"
  assert_contains "$(cat "$F")" 'mas "Good", id: 2' "good app saved"
  assert_command_fails "grep -q 'Bad' '$F'" "bad app not saved"
}

test_mas_missing() {
  test_suite "snapshot without mas on PATH"
  reset_stub
  local out
  out="$(unset MACLIFT_MAS; PATH=/usr/bin:/bin snapshot_candidates 2>&1 >/dev/null)"
  assert_contains "$out" "mas not found, so App Store apps were not checked" "says mas was skipped"
  out="$(unset MACLIFT_MAS; PATH=/usr/bin:/bin snapshot_candidates 2>/dev/null)"
  assert_equals "$(printf '%s\n' "$EXPECTED" | grep -v '^mas:')" "$out" "no mas candidates"
}

test_partial_selection() {
  test_suite "cmd_snapshot: pick a subset in the plain menu"
  reset_stub
  local out
  # Items: 1 brew:figlet, 2 brew:owner/tap/thing, 3 Microsoft Remote Desktop,
  # 4 Xcode, all preselected. Untick 1 and 3, then accept.
  out="$(printf '1,3\n\n' | cmd_snapshot 0 2>&1)"
  assert_contains "$out" "Saved 2 package(s)" "two saved"
  assert_equals 'cask "zoom"
# added by maclift snapshot on '"$(date +%Y-%m-%d)"'
brew "owner/tap/thing"
mas "Xcode", id: 497799835' "$(cat "$F")" "only the chosen lines are written"
}

test_mas_comma() {
  test_suite "cmd_snapshot: mas name with a comma (gum)"
  reset_stub
  : >"$STUB/brew.leaves"
  : >"$STUB/brew.cask-list"
  printf '3 Foo, Bar (1.0)\n4 Baz (1.0)\n' >"$STUB/mas.list"
  # A gum that answers with its --selected list, split on commas like gum.
  printf '#!/bin/bash\nwhile [ $# -gt 0 ]; do [ "$1" = --selected ] && { printf "%%s\\n" "$2" | tr , "\\n"; exit 0; }; shift; done\n' >"$STUB/gum"
  chmod +x "$STUB/gum"
  local out
  out="$(unset MACLIFT_PLAIN; MACLIFT_GUM="$STUB/gum" MACLIFT_ASSUME_TTY=1 NO_COLOR='' CI='' cmd_snapshot 0 2>&1)"
  assert_contains "$out" "Saved 2 package(s)" "both saved"
  assert_contains "$(cat "$F")" 'mas "Foo, Bar", id: 3' "name keeps its comma"
  assert_contains "$(cat "$F")" 'mas "Baz", id: 4' "other app saved"
}

test_all_mas_quoted() {
  test_suite "cmd_snapshot: every candidate skipped"
  reset_stub
  : >"$STUB/brew.leaves"
  : >"$STUB/brew.cask-list"
  printf '1 Bad "One" (1.0)\n2 Bad "Two" (1.0)\n' >"$STUB/mas.list"
  local out
  out="$(MACLIFT_ASSUME_YES=1 cmd_snapshot 0 2>&1)"
  assert_contains "$out" "skipped 2 App Store app(s) whose name contains a quote" "says they were skipped and why"
  assert_equals "" "$(printf '%s\n' "$out" | grep -F 'already known' || true)" "not 'already known'"
}

test_candidates
test_cmd_snapshot
test_mas_quote
test_mas_missing
test_partial_selection
test_mas_comma
test_all_mas_quoted
test_summary
