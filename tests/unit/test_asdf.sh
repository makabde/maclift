#!/usr/bin/env bash
#
# Unit tests for lib/asdf.sh
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
# shellcheck source=lib/dotfiles.sh
source "$PROJECT_ROOT/lib/dotfiles.sh"
# shellcheck source=lib/asdf.sh
source "$PROJECT_ROOT/lib/asdf.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
export MACLIFT_ASDF="$PROJECT_ROOT/tests/stubs/asdf"

fresh_home() {
  MACLIFT_HOME="$(mktemp -d)"
  export MACLIFT_HOME HOME="$MACLIFT_HOME"
  unset MACLIFT_RUN_ID MACLIFT_STUB_LATEST_NODEJS MACLIFT_STUB_LATEST_ERLANG
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
}

test_no_glob() {
  test_suite "tool-versions lines are not glob-expanded"
  fresh_home
  local d="$MACLIFT_HOME/work"
  mkdir -p "$d"
  : >"$d/aaa"
  : >"$d/bbb"
  printf 'nodejs *\npython 3.13.1\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  printf 'nodejs 1.0.0\nrust 1.80.0\n' >"$MACLIFT_HOME/.tool-versions"
  assert_equals "*" "$(cd "$d" && _pins_read "$MACLIFT_CONFIG_DIR/tool-versions" nodejs)" "_pins_read keeps *"
  (cd "$d" && pins_apply 0 >/dev/null)
  assert_equals "nodejs *" "$(sed -n 1p "$MACLIFT_HOME/.tool-versions")" "pins_apply keeps the * version"
  printf 'rust *\n' >"$MACLIFT_HOME/.tool-versions"
  printf 'rust *\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  (cd "$d" && pins_apply 0 >/dev/null)
  assert_equals "rust *" "$(cat "$MACLIFT_HOME/.tool-versions")" "target line with * not expanded"
  case "$-" in *f*) assert_equals "on" "off" "globbing left enabled" ;; *) assert_equals "ok" "ok" "globbing left enabled" ;; esac
  set -f
  _pins_read "$MACLIFT_CONFIG_DIR/tool-versions" rust >/dev/null
  case "$-" in *f*) assert_equals "ok" "ok" "noglob stays set if it was set" ;; *) assert_equals "set" "unset" "noglob stays set if it was set" ;; esac
  set +f
}

test_resolve_fresh() {
  test_suite "pins resolve fresh"
  fresh_home
  pins_resolve erlang elixir nodejs
  assert_equals "27.3.4" "$(pins_get erlang)" "erlang"
  assert_equals "1.18.4-otp-27" "$(pins_get elixir)" "elixir matches otp"
  assert_equals "24.5.1" "$(pins_get nodejs)" "nodejs"
  assert_equals "erlang 27.3.4
elixir 1.18.4-otp-27
nodejs 24.5.1" "$(cat "$MACLIFT_CONFIG_DIR/tool-versions")" "file format"
}

test_order() {
  test_suite "pins file order"
  fresh_home
  pins_resolve python nodejs elixir erlang
  assert_equals "erlang elixir nodejs python" "$(cut -d' ' -f1 "$MACLIFT_CONFIG_DIR/tool-versions" | tr '\n' ' ' | sed 's/ $//')" "order"
}

test_adopt() {
  test_suite "pins adopt existing"
  fresh_home
  printf 'nodejs 22.1.0\npython 3.13.1 3.12.8\nrust 1.80.0\n' >"$MACLIFT_HOME/.tool-versions"
  pins_resolve erlang nodejs python
  assert_equals "22.1.0" "$(pins_get nodejs)" "nodejs adopted"
  assert_equals "3.13.1" "$(pins_get python)" "first python version adopted"
  assert_equals "27.3.4" "$(pins_get erlang)" "erlang from latest"
}

test_keep_pins() {
  test_suite "pins kept when latest changes"
  fresh_home
  pins_resolve erlang nodejs
  export MACLIFT_STUB_LATEST_NODEJS=99.0.0
  pins_resolve erlang nodejs
  assert_equals "24.5.1" "$(pins_get nodejs)" "old pin kept"
}

test_elixir_otp() {
  test_suite "elixir picks erlang major"
  fresh_home
  export MACLIFT_STUB_LATEST_ERLANG=28.0.1
  pins_resolve erlang elixir
  assert_equals "1.19.0-otp-28" "$(pins_get elixir)" "otp 28 (no rc)"
  fresh_home
  export MACLIFT_STUB_LATEST_ERLANG=26.2.5
  pins_resolve erlang elixir
  assert_equals "1.18.4-otp-26" "$(pins_get elixir)" "otp 26"
}

test_apply_backup() {
  test_suite "pins apply"
  fresh_home
  pins_resolve erlang nodejs
  printf '# mine\nnodejs 20.0.0\nrust 1.80.0\n' >"$MACLIFT_HOME/.tool-versions"
  pins_apply 1 >/dev/null
  assert_equals "nodejs 20.0.0" "$(sed -n 2p "$MACLIFT_HOME/.tool-versions")" "dry-run changes nothing"
  pins_apply 0 >/dev/null
  local f="$MACLIFT_HOME/.tool-versions"
  assert_equals "nodejs 24.5.1" "$(grep '^nodejs' "$f")" "nodejs pinned"
  assert_equals "erlang 27.3.4" "$(grep '^erlang' "$f")" "erlang added"
  assert_equals "rust 1.80.0" "$(grep '^rust' "$f")" "unrelated line kept"
  assert_equals "# mine" "$(sed -n 1p "$f")" "comment kept"
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .tool-versions | wc -l | tr -d ' ')" "old file backed up"
  pins_apply 0 >/dev/null
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .tool-versions | wc -l | tr -d ' ')" "idempotent: no new backup"
}

test_apply_fresh() {
  test_suite "pins apply without existing file"
  fresh_home
  pins_resolve erlang
  pins_apply 0 >/dev/null
  assert_equals "erlang 27.3.4" "$(cat "$MACLIFT_HOME/.tool-versions")" "created"
}

test_latest_error_text() {
  test_suite "pins_resolve never pins asdf's error text"
  fresh_home
  local rc=0 out
  export MACLIFT_STUB_LATEST_PYTHON="unable to load latest version: Plugin named python does not have a callback named list-all"
  out="$(pins_resolve python 2>&1)" || rc=$?
  unset MACLIFT_STUB_LATEST_PYTHON
  assert_equals "1" "$rc" "returns 1"
  assert_contains "$out" "could not resolve a version for python" "says so"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/tool-versions' ]" "no pin stored"
  assert_command_fails "MACLIFT_STUB_LATEST_NODEJS='not a version' pins_latest nodejs" "pins_latest rejects it too"
}

test_tool_versions_tokens() {
  test_suite "pins_resolve keeps any ~/.tool-versions token but system"
  fresh_home
  printf 'python pypy3.10-7.3.12\nelixir main-otp-27\nerlang ref:OTP-27.0\n' >"$MACLIFT_HOME/.tool-versions"
  cp "$MACLIFT_HOME/.tool-versions" "$MACLIFT_HOME/tv.before"
  pins_resolve python elixir erlang
  assert_equals "pypy3.10-7.3.12" "$(pins_get python)" "pypy kept verbatim"
  assert_equals "main-otp-27" "$(pins_get elixir)" "elixir main-otp-27 kept"
  assert_equals "ref:OTP-27.0" "$(pins_get erlang)" "ref: kept"
  pins_apply 0 >/dev/null
  assert_command_succeeds "cmp -s '$MACLIFT_HOME/tv.before' '$MACLIFT_HOME/.tool-versions'" ".tool-versions unchanged"

  fresh_home
  printf 'nodejs system\n' >"$MACLIFT_HOME/.tool-versions"
  local out
  out="$(pins_resolve nodejs 2>&1)"
  assert_equals "24.5.1" "$(pins_get nodejs)" "system: latest pinned"
  # shellcheck disable=SC2088 # literal ~ in the message
  assert_contains "$out" "~/.tool-versions says nodejs system; pinning the latest version instead" "system: visible note"
  fresh_home
  printf 'nodejs system\n' >"$MACLIFT_HOME/.tool-versions"
  MACLIFT_NOTES="$MACLIFT_HOME/notes" pins_resolve nodejs 2>/dev/null
  assert_contains "$(cat "$MACLIFT_HOME/notes")" "says nodejs system" "system: note goes to the run's notes"
}

test_dry_run_stores_nothing() {
  test_suite "pins_resolve --dry-run never stores a pin"
  fresh_home
  printf 'erlang 26.2.5\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  cp "$MACLIFT_CONFIG_DIR/tool-versions" "$MACLIFT_HOME/pins.before"
  local out
  out="$(pins_resolve --dry-run erlang elixir nodejs 2>&1)"
  assert_contains "$out" "would pin elixir 1.18.4-otp-26" "elixir from the stored erlang pin"
  assert_contains "$out" "would pin nodejs 24.5.1" "nodejs from latest"
  assert_command_succeeds "cmp -s '$MACLIFT_HOME/pins.before' '$MACLIFT_CONFIG_DIR/tool-versions'" "pins file byte-identical"
  fresh_home
  out="$(pins_resolve --dry-run elixir 2>&1)"
  assert_contains "$out" "would pin erlang 27.3.4" "erlang first"
  assert_contains "$out" "would pin elixir to its latest version for that erlang" "elixir follows"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/tool-versions' ]" "no pins file created"
}

test_missing_plugin() {
  test_suite "pins_resolve adds a missing plugin before asking for latest"
  fresh_home
  local stub rc=0 out
  stub="$(mktemp -d)"
  export MACLIFT_STUB_DIR="$stub"
  printf 'erlang\n' >"$stub/asdf.plugins"
  pins_resolve nodejs
  assert_equals "24.5.1" "$(pins_get nodejs)" "pinned"
  assert_equals "plugin list
plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
latest nodejs" "$(cat "$stub/asdf.calls")" "plugin added from the catalog URL, then latest"
  : >"$stub/asdf.calls"
  pins_resolve erlang
  assert_equals "plugin list
latest erlang" "$(cat "$stub/asdf.calls")" "present plugin: not added again"

  fresh_home
  printf '' >"$stub/asdf.plugins"
  : >"$stub/asdf.calls"
  rc=0; out="$(pins_resolve --dry-run nodejs erlang elixir 2>&1)" || rc=$?
  assert_equals "0" "$rc" "dry run returns 0"
  assert_contains "$out" "would pin nodejs to its latest version" "nodejs note"
  assert_contains "$out" "would pin erlang to its latest version" "erlang note"
  assert_contains "$out" "would pin elixir to its latest version" "elixir note"
  assert_command_fails "grep -Eq '^(plugin add|latest)' '$stub/asdf.calls'" "dry run: no plugin add, no latest"
  assert_equals "" "$(cat "$stub/asdf.plugins")" "dry run: nothing added"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/tool-versions' ]" "dry run: nothing stored"

  fresh_home
  rc=0; out="$(pins_resolve fail-plugin 2>&1)" || rc=$?
  assert_equals "1" "$rc" "failed plugin add returns 1"
  assert_contains "$out" "could not add the asdf plugin fail-plugin" "says so"
  assert_command_fails "grep -q '^latest fail-plugin' '$stub/asdf.calls'" "no latest after a failed add"
  unset MACLIFT_STUB_DIR
  rm -rf "$stub"
}

test_is_newer() {
  test_suite "pins_is_newer"
  assert_command_succeeds "pins_is_newer 24.3.0 24.5.1" "newer"
  assert_command_fails "pins_is_newer 24.5.1 24.5.1" "same"
  assert_command_fails "pins_is_newer 24.10.0 24.9.9" "older (numeric compare)"
  assert_command_succeeds "pins_is_newer 24.9.9 24.10.0" "numeric, not lexical"
  assert_command_succeeds "pins_is_newer 1.18.4-otp-26 1.18.4-otp-27" "higher OTP build, same elixir"
  assert_command_fails "pins_is_newer 1.18.4-otp-27 1.18.4-otp-26" "lower OTP build is a downgrade"
  assert_command_fails "pins_is_newer 24.5.1 24.5.01" "sideways move"
  assert_command_fails "pins_is_newer 24.5.01 24.5.1" "sideways move, reversed"
  assert_command_succeeds "pins_is_newer 1.19.0-rc.1-otp-27 1.19.0-otp-27" "rc to the release is newer"
  assert_command_fails "pins_is_newer 1.19.0-otp-27 1.19.0-rc.1-otp-27" "release to its rc is a downgrade"
  assert_command_succeeds "pins_is_newer 23.9.9 24.0.0-rc.1" "an rc of higher numbers is newer"
  assert_command_fails "pins_is_newer 24.0.0-rc.1 23.9.9" "lower numbers are older than an rc"
  assert_command_succeeds "pins_is_newer 3.13.0a1 3.13.0" "letter in the core is a pre-release"
  assert_command_succeeds "pins_is_newer 2.0.0-beta 2.0.0" "-beta ranks below the release"
  assert_equals "1.19.0-otp-27" "$(printf '1.19.0-rc.1-otp-27\n1.19.0-otp-27\n1.18.4-otp-27\n' | _pins_newest)" "_pins_newest picks the release"
  assert_equals "1.19.0-otp-27" "$(printf '1.19.0-otp-27\n1.19.0-rc.1-otp-27\n' | _pins_newest)" "_pins_newest keeps the release when it comes first"
}

test_latest() {
  test_suite "pins_latest"
  fresh_home
  pins_resolve erlang
  assert_equals "27.3.4" "$(pins_latest erlang)" "asdf latest"
  assert_equals "1.18.4-otp-27" "$(pins_latest elixir)" "elixir against erlang pin"
}

test_no_glob
test_is_newer
test_latest
test_resolve_fresh
test_order
test_adopt
test_keep_pins
test_elixir_otp
test_apply_backup
test_apply_fresh
test_latest_error_text
test_tool_versions_tokens
test_dry_run_stores_nothing
test_missing_plugin
test_summary
