#!/usr/bin/env bash
#
# Unit tests for lib/update.sh
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
# shellcheck source=lib/update.sh
source "$PROJECT_ROOT/lib/update.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
mkdir -p "$MACLIFT_CONFIG_DIR"
STUB="$(mktemp -d)"
export MACLIFT_STUB_DIR="$STUB" MACLIFT_BREW="$PROJECT_ROOT/tests/stubs/brew" MACLIFT_GIT="$PROJECT_ROOT/tests/stubs/git" MACLIFT_PLAIN=1

reset_stub() {
  rm -f "$STUB"/brew.* "$STUB"/git.*
}

test_pull() {
  test_suite "update_pull"
  reset_stub
  local out rc=0
  : >"$STUB/git.notrepo"
  out="$(update_pull 0)"
  assert_contains "$out" "is not a git clone" "not a clone is skipped"
  rm -f "$STUB/git.notrepo"

  echo " M lib/foo.sh" >"$STUB/git.dirty"
  rc=0; out="$(update_pull 0)" || rc=$?
  assert_contains "$out" "local changes" "dirty clone is skipped"
  assert_equals "0" "$rc" "dirty clone returns 0"
  assert_command_fails "grep -E 'pull|stash|reset|checkout' '$STUB/git.calls'" "dirty clone: no pull, stash, reset or checkout"
  assert_command_succeeds "grep -qx -- '--no-optional-locks status --porcelain' '$STUB/git.calls'" "status takes no optional locks"
  rm -f "$STUB/git.dirty" "$STUB/git.calls"

  : >"$STUB/git.noupstream"
  out="$(update_pull 0)"
  assert_contains "$out" "no upstream branch" "no upstream is skipped"
  assert_command_fails "grep -q pull '$STUB/git.calls'" "no upstream: no pull call"
  rm -f "$STUB/git.noupstream" "$STUB/git.calls"

  out="$(update_pull 1)"
  assert_contains "$out" "would pull" "dry run says would pull"
  assert_command_fails "grep -q pull '$STUB/git.calls'" "dry run makes no pull call"
  rm -f "$STUB/git.calls"

  UPDATE_PULLED=0
  update_pull 0 >"$STUB/out"
  assert_contains "$(cat "$STUB/out")" "✓ pulled aaa..bbb" "pull prints the range"
  assert_equals "1" "$UPDATE_PULLED" "UPDATE_PULLED set"
  assert_command_succeeds "grep -q -- 'pull --ff-only' '$STUB/git.calls'" "pull is fast-forward only"

  update_pull 0 >"$STUB/out"
  assert_contains "$(cat "$STUB/out")" "up to date" "no new commits"
  assert_equals "0" "$UPDATE_PULLED" "UPDATE_PULLED stays 0 when HEAD did not move"

  rm -f "$STUB/git.head"
  : >"$STUB/git.pullfail"
  rc=0; out="$(update_pull 0)" || rc=$?
  assert_equals "1" "$rc" "failed pull returns 1"
  assert_contains "$out" "could not fast-forward" "failed pull says so"
  rc=0; out="$(MACLIFT_LOG="$STUB/run.log" update_pull 0)" || rc=$?
  assert_contains "$out" "resolve it by hand (see $STUB/run.log)" "failed pull points at the log"
}

test_outdated() {
  test_suite "update_outdated"
  reset_stub
  printf 'bat\nhashicorp/tap/terraform\n' >"$STUB/brew.outdated"
  printf 'zoom\n' >"$STUB/brew.cask-outdated"
  local out
  out="$(update_outdated brew:bat brew:jq cask:zoom cask:bat brew:terraform brew:hashicorp/tap/terraform)"
  assert_equals "brew:bat
cask:zoom
brew:terraform
brew:hashicorp/tap/terraform" "$out" "outdated ids, tap names by base name"
}

test_upgrade() {
  test_suite "update_upgrade"
  reset_stub
  local out
  update_upgrade 0 brew:bat brew:fail-me cask:zoom >/dev/null 2>&1
  assert_command_succeeds "grep -Fxq 'upgrade -- bat' '$STUB/brew.calls'" "brew upgrade -- bat"
  assert_command_succeeds "grep -Fxq 'upgrade --cask -- zoom' '$STUB/brew.calls'" "brew upgrade --cask -- zoom"
  assert_equals "brew:fail-me" "$UPDATE_FAILED" "failed id recorded, later ids still ran"
  rm -f "$STUB/brew.calls"
  out="$(update_upgrade 1 brew:bat)"
  assert_contains "$out" "would upgrade brew:bat" "dry run message"
  assert_command_fails "[ -e '$STUB/brew.calls' ]" "dry run calls nothing"
}

test_managed() {
  test_suite "update_managed"
  reset_stub
  rm -f "$MACLIFT_CONFIG_DIR/Brewfile.local"
  selection_save brew:bat brew:jq cask:zoom asdf:nodejs >/dev/null 2>&1
  printf 'brew "bat"\nbrew "extra-tool"\ncask "extra-app"\n' >"$MACLIFT_CONFIG_DIR/Brewfile.local"
  printf 'bat\nzoom\nextra-tool\nextra-app\nnodejs\n' >"$STUB/brew.installed"
  local out
  out="$(update_managed)"
  assert_contains "$out" "brew:bat" "installed selection item listed"
  assert_contains "$out" "cask:zoom" "installed cask listed"
  assert_contains "$out" "brew:extra-tool" "installed extra listed"
  assert_contains "$out" "cask:extra-app" "installed cask extra listed"
  assert_equals "1" "$(printf '%s\n' "$out" | grep -cFx brew:bat)" "extra duplicating a selection id prints once"
  assert_equals "0" "$(printf '%s\n' "$out" | grep -cFx brew:jq || true)" "not installed: left out"
  assert_equals "0" "$(printf '%s\n' "$out" | grep -c '^asdf:' || true)" "non-brew/cask id dropped"
  rm -f "$MACLIFT_CONFIG_DIR/Brewfile.local"
}

set_pins() {
  printf '%s\n' "$@" >"$MACLIFT_CONFIG_DIR/tool-versions"
}

test_pin_candidates() {
  test_suite "update_pin_candidates"
  set_pins "erlang 26.2.5" "elixir 1.18.4-otp-26" "nodejs 24.3.0"
  export MACLIFT_ASDF="$PROJECT_ROOT/tests/stubs/asdf"
  assert_equals "erlang	26.2.5	27.3.4
nodejs	24.3.0	24.5.1" "$(update_pin_candidates)" "erlang and nodejs, no elixir"
}

test_pins_listing() {
  test_suite "update_pins listing"
  set_pins "erlang 26.2.5" "elixir 1.18.4-otp-26" "nodejs 24.3.0"
  local before out
  before="$(cat "$MACLIFT_CONFIG_DIR/tool-versions")"
  out="$(MACLIFT_ASSUME_YES=1 update_pins 0)"
  assert_contains "$out" "erlang 26.2.5 → 27.3.4" "lists erlang"
  assert_contains "$out" "Run maclift update (without -y) to choose." "hint"
  assert_equals "$before" "$(cat "$MACLIFT_CONFIG_DIR/tool-versions")" "-y leaves the pins"
  out="$(update_pins 1)"
  assert_contains "$out" "nodejs 24.3.0 → 24.5.1" "dry run lists nodejs"
  assert_equals "$before" "$(cat "$MACLIFT_CONFIG_DIR/tool-versions")" "dry run leaves the pins"
}

test_pins_accept() {
  test_suite "update_pins accept"
  set_pins "erlang 26.2.5" "elixir 1.18.4-otp-26" "nodejs 24.3.0"
  local out rc=0
  # erlang yes, then the recomputed elixir offer yes, nodejs no
  out="$(printf 'y\ny\nn\n' | update_pins 0 2>/dev/null)" || rc=$?
  assert_equals "0" "$rc" "returns 0"
  assert_contains "$out" "elixir 1.18.4-otp-26 → 1.18.4-otp-27" "elixir offered after erlang"
  assert_equals "27.3.4" "$(pins_get erlang)" "erlang upgraded"
  assert_equals "1.18.4-otp-27" "$(pins_get elixir)" "elixir upgraded"
  assert_equals "24.3.0" "$(pins_get nodejs)" "nodejs declined"
  assert_equals "27.3.4" "$(grep '^erlang' "$MACLIFT_HOME/.tool-versions" | cut -d' ' -f2)" "applied to .tool-versions"
  assert_equals "1.18.4-otp-27" "$(grep '^elixir' "$MACLIFT_HOME/.tool-versions" | cut -d' ' -f2)" "elixir applied to .tool-versions"
}

test_pins_install_fail() {
  test_suite "update_pins install failure"
  set_pins "fail-plugin 1.0.0"
  printf 'fail-plugin 1.0.0\n' >"$MACLIFT_HOME/.tool-versions"
  cp "$MACLIFT_HOME/.tool-versions" "$STUB/tv.before"
  export MACLIFT_STUB_LATEST_FAIL_PLUGIN=2.0.0
  local out rc=0
  out="$(printf 'y\n' | update_pins 0 2>/dev/null)" || rc=$?
  assert_equals "1" "$rc" "returns 1"
  assert_contains "$(cat "$STUB/tool-versions.at-failure")" "fail-plugin 2.0.0" "new pin was written mid-run"
  assert_contains "$out" "✗ fail-plugin 2.0.0 failed to install; kept 1.0.0" "says so"
  assert_equals "1.0.0" "$(pins_get fail-plugin)" "pin kept"
  assert_command_succeeds "cmp -s '$STUB/tv.before' '$MACLIFT_HOME/.tool-versions'" ".tool-versions byte-identical"
  unset MACLIFT_STUB_LATEST_FAIL_PLUGIN
}

test_pins_store_fails() {
  test_suite "update_pins when the pin cannot be stored"
  set_pins "nodejs 24.3.0"
  local out rc=0
  _pins_store() { return 1; }
  out="$(printf 'y\n' | update_pins 0 2>/dev/null)" || rc=$?
  # shellcheck source=lib/asdf.sh
  source "$PROJECT_ROOT/lib/asdf.sh"
  assert_equals "1" "$rc" "returns 1"
  assert_contains "$out" "✗ nodejs 24.5.1 could not be pinned; kept 24.3.0" "says so"
  assert_equals "24.3.0" "$(pins_get nodejs)" "pin unchanged"
  assert_command_fails "grep -q 'installing asdf:nodejs' '${MACLIFT_LOG:-/dev/null}'" "nothing installed"
}

test_pins_listed_reset() {
  test_suite "update_pins resets the listed count"
  set_pins "nodejs 24.5.1"
  UPDATE_PIN_LISTED=7
  update_pins 1 >/dev/null
  assert_equals "0" "$UPDATE_PIN_LISTED" "nothing listed: 0, not the old 7"
}

test_dry_run_box() {
  test_suite "cmd_update --dry-run summary"
  reset_stub
  set_pins "erlang 26.2.5" "nodejs 24.3.0"
  local out
  UPDATE_PIN_LISTED=9
  out="$(NO_PULL=1 cmd_update 1 2>&1)"
  assert_contains "$out" "== Would upgrade pins: 2 ==" "counts the pins it would offer"
  set_pins "nodejs 24.5.1"
  out="$(NO_PULL=1 cmd_update 1 2>&1)"
  assert_contains "$out" "== Would upgrade pins: 0 ==" "none to offer: 0"
}

test_pin_candidates
test_pins_listing
test_pins_store_fails
test_pins_listed_reset
test_dry_run_box
test_pins_accept
test_pins_install_fail
test_pull
test_outdated
test_upgrade
test_managed
test_summary
