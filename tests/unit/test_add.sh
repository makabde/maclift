#!/usr/bin/env bash
#
# Unit tests for lib/add.sh
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
# shellcheck source=lib/add.sh
source "$PROJECT_ROOT/lib/add.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
mkdir -p "$MACLIFT_CONFIG_DIR"
F="$MACLIFT_CONFIG_DIR/Brewfile.local"
STUB="$(mktemp -d)"
export MACLIFT_STUB_DIR="$STUB" MACLIFT_BREW="$PROJECT_ROOT/tests/stubs/brew" MACLIFT_PLAIN=1

reset_stub() {
  rm -f "$STUB"/brew.* "$F"
  printf 'docker\nfiglet\n' >"$STUB/brew.formulae"
  printf 'docker\n' >"$STUB/brew.casks"
}

test_resolve() {
  test_suite "add_resolve"
  reset_stub
  local rc=0 out
  add_resolve -rf >/dev/null 2>&1 || rc=$?
  assert_equals "3" "$rc" "-rf invalid"
  rc=0; add_resolve $'foo\nbar' >/dev/null 2>&1 || rc=$?
  assert_equals "3" "$rc" "embedded newline invalid"
  rc=0; add_resolve $'brew:foo\nbar' >/dev/null 2>&1 || rc=$?
  assert_equals "3" "$rc" "prefixed embedded newline invalid"
  rc=0; add_resolve 'a;b' >/dev/null 2>&1 || rc=$?
  assert_equals "3" "$rc" "a;b invalid"
  rc=0; out="$(add_resolve docker 2>&1)" || rc=$?
  assert_equals "2" "$rc" "ambiguous"
  assert_contains "$out" "use brew:docker or cask:docker" "ambiguity message"
  assert_equals "cask:docker" "$(add_resolve cask:docker)" "explicit prefix"
  for out in brew:cask:docker cask:brew:docker brew:brew:figlet; do
    rc=0; add_resolve "$out" >/dev/null 2>&1 || rc=$?
    assert_equals "3" "$rc" "$out: two prefixes rejected"
  done
  rc=0; out="$(add_resolve brew:cask:docker 2>&1)" || rc=$?
  assert_contains "$out" "has two prefixes" "says why"
  : >"$STUB/brew.calls"
  assert_equals "brew:bat" "$(add_resolve bat)" "catalog formula"
  assert_command_fails "grep -q info '$STUB/brew.calls'" "no brew info call"
  assert_equals "brew:figlet" "$(add_resolve figlet)" "formula only"
  rc=0; out="$(add_resolve nope-zzz 2>&1)" || rc=$?
  assert_equals "1" "$rc" "not found"
  assert_contains "$out" "no Homebrew formula or cask named nope-zzz" "not found message"
}

test_cmd_add() {
  test_suite "cmd_add"
  reset_stub
  cmd_add 0 figlet >/dev/null 2>&1
  assert_command_succeeds "grep -Fxq figlet '$STUB/brew.installed'" "figlet installed"
  assert_command_succeeds "grep -Fxq 'brew \"figlet\"' '$F'" "line recorded"
  cmd_add 0 figlet >/dev/null 2>&1
  assert_equals "1" "$(grep -c 'brew "figlet"' "$F")" "no duplicate line"

  reset_stub
  local rc=0
  cmd_add 0 fail-me >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "failed install exits 1"
  printf 'fail-me\n' >"$STUB/brew.formulae"
  rc=0; cmd_add 0 fail-me >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "failed install with resolvable name exits 1"
  assert_command_fails "grep -q fail-me '$F'" "failed install records nothing"

  reset_stub
  rc=0
  cmd_add 0 zzz-missing figlet >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "unresolved arg exits 1"
  assert_command_succeeds "grep -Fxq figlet '$STUB/brew.installed'" "later args still processed"

  reset_stub
  cmd_add 1 figlet >/dev/null 2>&1
  assert_command_fails "[ -e '$STUB/brew.installed' ]" "dry run installs nothing"
  assert_command_fails "[ -e '$F' ]" "dry run writes no file"
}

test_cmd_add_catalog() {
  test_suite "cmd_add catalog item"
  reset_stub
  local out
  out="$(cmd_add 0 bat 2>&1)"
  assert_contains "$out" "bat is in the catalog" "catalog message"
  assert_contains "$(selection_load)" "brew:bat" "saved to selection"
  assert_command_fails "[ -e '$F' ]" "not in Brewfile.local"
}

test_cmd_add_leaves_offer_pending() {
  test_suite "cmd_add does not mark the new-defaults offer as seen"
  reset_stub
  rm -f "$MACLIFT_CONFIG_DIR/selection.conf"
  printf 'MACLIFT_GROUPS="cli languages"\nMACLIFT_ITEMS="brew:git asdf:nodejs"\n' >"$MACLIFT_CONFIG_DIR/selection.conf"
  cmd_add 0 bat >/dev/null 2>&1
  assert_contains "$(selection_load)" "brew:bat" "bat saved"
  assert_contains "$(selection_new_defaults)" "script:hex" "offer still pending"
  assert_command_fails "conf_get '$MACLIFT_CONFIG_DIR/selection.conf' MACLIFT_SEEN" "no seen list written"
}

test_cmd_add_save_fails() {
  test_suite "cmd_add when the selection cannot be saved"
  reset_stub
  local rc=0 out
  selection_save() { return 1; }
  out="$(cmd_add 0 bat 2>&1)" || rc=$?
  unset -f selection_save
  # shellcheck source=lib/selection.sh
  source "$PROJECT_ROOT/lib/selection.sh"
  assert_equals "1" "$rc" "exit 1"
  assert_equals "" "$(printf '%s\n' "$out" | grep -F 'added to your selection' || true)" "does not claim it was added"
  assert_contains "$out" "✗ brew:bat is in the catalog, but your selection could not be saved" "cross line"
}

test_cmd_add_cask_prefix() {
  test_suite "cmd_add with a cask: prefix"
  reset_stub
  local rc=0
  cmd_add 0 cask:docker >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "exit 0"
  assert_command_succeeds "grep -Fxq 'install --cask -- docker' '$STUB/brew.calls'" "installed as a cask"
  assert_command_succeeds "grep -Fxq 'cask \"docker\"' '$F'" "recorded as a cask line"
  assert_command_fails "grep -Fxq 'brew \"docker\"' '$F'" "not recorded as a formula"
}

test_cmd_add_ambiguous_among_many() {
  test_suite "cmd_add: an ambiguous name among several"
  reset_stub
  local rc=0 out
  out="$(cmd_add 0 figlet docker cask:docker 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exit 1"
  assert_contains "$out" "use brew:docker or cask:docker" "ambiguity explained"
  assert_command_succeeds "grep -Fxq 'brew \"figlet\"' '$F'" "earlier arg went through"
  assert_command_succeeds "grep -Fxq 'cask \"docker\"' '$F'" "later arg went through"
}

test_cmd_add_no_gitconfig() {
  test_suite "cmd_add leaves the gitconfig alone"
  reset_stub
  identity_render_gitconfig() { : >"$STUB/rendered"; }
  cmd_add 0 figlet >/dev/null 2>&1
  unset -f identity_render_gitconfig
  assert_command_fails "[ -e '$STUB/rendered' ]" "no gitconfig re-render"
}

test_resolve
test_cmd_add
test_cmd_add_no_gitconfig
test_cmd_add_catalog
test_cmd_add_leaves_offer_pending
test_cmd_add_save_fails
test_cmd_add_cask_prefix
test_cmd_add_ambiguous_among_many
test_summary
