#!/usr/bin/env bash
#
# Unit tests for lib/localbrew.sh
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

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
mkdir -p "$MACLIFT_CONFIG_DIR"
F="$MACLIFT_CONFIG_DIR/Brewfile.local"

test_line() {
  test_suite "localbrew_line"
  assert_equals 'brew "bat"' "$(localbrew_line brew:bat)" "brew"
  assert_equals 'cask "docker"' "$(localbrew_line cask:docker)" "cask"
  assert_equals 'mas "Xcode", id: 497799835' "$(localbrew_line mas:497799835 Xcode)" "mas"
  assert_command_fails "localbrew_line asdf:nodejs" "other kinds"
}

test_append() {
  test_suite "localbrew_append"
  printf 'brew "jq"' >"$F"
  localbrew_append 0 "added by test" 'brew "bat"'
  assert_equals "3" "$(wc -l <"$F" | tr -d ' ')" "3 lines"
  assert_equals "brew:jq
brew:bat" "$(install_brewfile_local 2>/dev/null)" "both parsed"
  assert_command_succeeds "localbrew_has brew:jq" "has jq"
  assert_command_fails "localbrew_has brew:nope" "no nope"
}

test_append_dry() {
  test_suite "localbrew_append dry run"
  printf 'brew "jq"' >"$F"
  local before out
  before="$(cat "$F")"
  out="$(localbrew_append 1 "c" 'brew "bat"')"
  assert_contains "$out" "would add to" "says would add"
  assert_equals "$before" "$(cat "$F")" "file unchanged"
  rm -f "$F"
  localbrew_append 1 "c" 'brew "bat"' >/dev/null
  assert_command_fails "[ -e '$F' ]" "no file created"
}

test_line
test_append
test_append_dry
test_summary
