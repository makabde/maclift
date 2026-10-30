#!/usr/bin/env bash
#
# Unit tests for lib/install.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
for f in core conf catalog ui dotfiles asdf install; do
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$f.sh"
done

export MACLIFT_DIR="$PROJECT_ROOT"
export MACLIFT_BREW="$PROJECT_ROOT/tests/stubs/brew"
export MACLIFT_ASDF="$PROJECT_ROOT/tests/stubs/asdf"

fresh_home() {
  MACLIFT_HOME="$(mktemp -d)"
  export MACLIFT_HOME HOME="$MACLIFT_HOME"
  MACLIFT_STUB_DIR="$(mktemp -d)"
  export MACLIFT_STUB_DIR
  unset MACLIFT_RUN_ID MACLIFT_LOG
  MACLIFT_FAILED=""
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
  : >"$MACLIFT_STUB_DIR/brew.calls"
}

test_failure_continues() {
  test_suite "failure does not stop the run"
  fresh_home
  local rc=0
  install_run 0 brew:bat brew:fail-me brew:jq >"$MACLIFT_STUB_DIR/out" 2>&1 || rc=$?
  assert_equals "1" "$rc" "returns 1"
  assert_equals "brew:fail-me" "$MACLIFT_FAILED" "failed ids"
  assert_command_succeeds "grep -q '^install -- jq' '$MACLIFT_STUB_DIR/brew.calls'" "jq still installed"
  assert_command_succeeds "grep -q 'brew:fail-me' '$MACLIFT_CONFIG_DIR/logs/$MACLIFT_RUN_ID.log'" "log has failure"
  assert_command_succeeds "grep -q 'stub: boom' '$MACLIFT_CONFIG_DIR/logs/$MACLIFT_RUN_ID.log'" "log has command output"
  assert_command_fails "grep -q 'stub:' '$MACLIFT_STUB_DIR/out'" "screen has no install output"
  assert_command_succeeds "grep -q '✗' '$MACLIFT_STUB_DIR/out'" "fail status shown"
}

test_rerun() {
  test_suite "re-run only installs what is missing"
  fresh_home
  install_run 0 brew:bat brew:fail-me brew:jq >/dev/null 2>&1 || true
  : >"$MACLIFT_STUB_DIR/brew.calls"
  unset MACLIFT_RUN_ID
  MACLIFT_FAILED=""
  local out rc=0
  out="$(install_run 0 brew:bat brew:fail-me brew:jq 2>&1)" || rc=$?
  assert_equals "1" "$(grep -c '^install' "$MACLIFT_STUB_DIR/brew.calls")" "only one install call"
  assert_command_succeeds "grep -q '^install -- fail-me' '$MACLIFT_STUB_DIR/brew.calls'" "fail-me retried"
  assert_contains "$out" "already installed" "reports already installed"
  assert_contains "$out" "brew:bat" "names bat"
}

test_dry_run() {
  test_suite "dry run changes nothing"
  fresh_home
  echo jq >"$MACLIFT_STUB_DIR/brew.installed"
  local out rc=0
  out="$(install_run 1 brew:bat brew:jq asdf:nodejs 2>&1)" || rc=$?
  assert_equals "0" "$rc" "dry run ok"
  assert_equals "0" "$(grep -c '^install' "$MACLIFT_STUB_DIR/brew.calls")" "no brew install"
  assert_contains "$out" "would install brew:bat" "would install"
  assert_contains "$out" "already installed" "already installed shown"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/asdf.installed' ]" "no asdf install"
  assert_command_fails "[ -e '$MACLIFT_HOME/.tool-versions' ]" "tool-versions untouched"
}

test_dotfiles() {
  test_suite "dotfiles items"
  fresh_home
  local out
  out="$(install_run 1 dotfiles:tmux 2>&1)"
  assert_contains "$out" "would install dotfiles:tmux" "dry run would install"
  assert_equals "0" "$(find "$MACLIFT_HOME" -maxdepth 1 -type l | wc -l | tr -d ' ')" "dry run links nothing"
  install_run 0 dotfiles:tmux >/dev/null 2>&1
  assert_command_succeeds "[ -L '$MACLIFT_HOME/.tmux.conf' ]" "linked"
  assert_command_succeeds "install_is_present dotfiles:tmux" "now present"
  unset MACLIFT_RUN_ID
  out="$(install_run 0 dotfiles:tmux 2>&1)"
  assert_contains "$out" "already installed" "rerun skips"
}

test_asdf_fresh_mac() {
  test_suite "asdf items on a Mac without the plugin"
  fresh_home
  : >"$MACLIFT_STUB_DIR/asdf.plugins"
  local out
  out="$(install_run 1 asdf:nodejs 2>&1)"
  assert_contains "$out" "would pin nodejs to its latest version" "dry run says it would pin"
  assert_command_fails "grep -Eq '^(plugin add|latest)' '$MACLIFT_STUB_DIR/asdf.calls'" "dry run: no plugin add, no latest"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/tool-versions' ]" "dry run: no pin"
  : >"$MACLIFT_STUB_DIR/asdf.calls"
  unset MACLIFT_RUN_ID
  install_run 0 asdf:nodejs >/dev/null 2>&1
  assert_equals "24.5.1" "$(pins_get nodejs)" "pinned after adding the plugin"
  assert_equals "plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git" "$(grep -m1 -E '^(plugin add|latest)' "$MACLIFT_STUB_DIR/asdf.calls")" "plugin added before latest"
  assert_command_succeeds "grep -q '^install nodejs 24.5.1' '$MACLIFT_STUB_DIR/asdf.calls'" "installed"
  assert_equals "1" "$(grep -c '^plugin add' "$MACLIFT_STUB_DIR/asdf.calls")" "plugin added once, not again by the item"
  unset MACLIFT_RUN_ID
  local before
  before="$(cat "$MACLIFT_CONFIG_DIR/tool-versions")"
  echo python >>"$MACLIFT_STUB_DIR/asdf.plugins"
  out="$(install_run 1 asdf:nodejs asdf:python 2>&1)"
  assert_contains "$out" "would pin python 3.13.5" "dry run says what it would pin"
  assert_equals "$before" "$(cat "$MACLIFT_CONFIG_DIR/tool-versions")" "dry run leaves the pins file alone"
  unset MACLIFT_RUN_ID
}

test_asdf() {
  test_suite "asdf items"
  fresh_home
  : >"$MACLIFT_STUB_DIR/asdf.plugins"
  install_run 0 asdf:nodejs >/dev/null 2>&1
  assert_command_succeeds "grep -q '^plugin add nodejs https' '$MACLIFT_STUB_DIR/asdf.calls'" "plugin added"
  assert_command_succeeds "grep -q '^install nodejs 24.5.1' '$MACLIFT_STUB_DIR/asdf.calls'" "installed pinned"
  assert_equals "nodejs 24.5.1" "$(grep nodejs "$MACLIFT_HOME/.tool-versions")" "pins applied"
  : >"$MACLIFT_STUB_DIR/asdf.calls"
  unset MACLIFT_RUN_ID
  local out
  out="$(install_run 0 asdf:nodejs 2>&1)"
  assert_contains "$out" "already installed" "rerun skips"
  assert_command_fails "grep -q '^install' '$MACLIFT_STUB_DIR/asdf.calls'" "no second asdf install"
}

test_order() {
  test_suite "install order"
  fresh_home
  install_run 1 asdf:nodejs cask:raycast brew:bat >"$MACLIFT_STUB_DIR/out" 2>&1
  assert_equals "brew:bat cask:raycast asdf:nodejs" "$(grep -o 'would install .*' "$MACLIFT_STUB_DIR/out" | sed 's/would install //' | tr '\n' ' ' | sed 's/ $//')" "order"
}

test_brewfile_local() {
  test_suite "Brewfile.local extras"
  fresh_home
  cat >"$MACLIFT_CONFIG_DIR/Brewfile.local" <<'EOT'
# my extras
brew "htop"

tap "x/y"
cask "firefox"
mas "Things", id: 904280696
EOT
  local ids
  ids="$(install_brewfile_local 2>"$MACLIFT_STUB_DIR/err")"
  assert_equals "brew:htop
cask:firefox
mas:904280696" "$ids" "ids on stdout"
  assert_contains "$(cat "$MACLIFT_STUB_DIR/err")" "tap" "warns about tap"
  assert_command_fails "grep -q 'my extras' '$MACLIFT_STUB_DIR/err'" "comments silent"
  # session state: must be set in the current shell
  install_brewfile_local >/dev/null 2>&1
  local out
  out="$(install_run 1 brew:htop mas:904280696 2>&1)"
  assert_contains "$out" "would install brew:htop" "extra brew works"
  assert_contains "$out" "Things" "mas name shown"
  echo htop >"$MACLIFT_STUB_DIR/brew.installed"
  assert_command_succeeds "install_is_present brew:htop" "extra present"
  assert_command_fails "install_is_present mas:904280696" "mas never present"
}

test_option_like() {
  test_suite "Brewfile.local rejects option-like names"
  fresh_home
  printf 'brew "--force"\ncask "-v"\nbrew "ok"\n' >"$MACLIFT_CONFIG_DIR/Brewfile.local"
  local ids
  ids="$(install_brewfile_local 2>"$MACLIFT_STUB_DIR/err")"
  assert_equals "brew:ok" "$ids" "only the safe entry"
  assert_equals "2" "$(grep -c warning "$MACLIFT_STUB_DIR/err")" "two warnings"
  assert_equals "0" "$(wc -l <"$MACLIFT_STUB_DIR/brew.calls" | tr -d ' ')" "no brew calls"
}

test_skip_if_app() {
  test_suite "skip-if-app honours MACLIFT_APP_ROOT"
  fresh_home
  local root
  root="$(mktemp -d)"
  export MACLIFT_APP_ROOT="$root"
  assert_command_fails "install_is_present cask:visual-studio-code" "empty root: falls through to brew, not installed"
  mkdir -p "$root/Applications/Visual Studio Code.app"
  assert_command_succeeds "install_is_present cask:visual-studio-code" "app under the root counts as installed"
  echo visual-studio-code >"$MACLIFT_STUB_DIR/brew.installed"
  rm -rf "$root/Applications"
  assert_command_succeeds "install_is_present cask:visual-studio-code" "empty root: brew stub says installed"
  unset MACLIFT_APP_ROOT
  rm -rf "$root"
}

test_notes() {
  test_suite "install_run exports MACLIFT_NOTES; install_notes lists them"
  fresh_home
  unset MACLIFT_NOTES
  install_run 0 brew:bat >/dev/null 2>&1
  assert_equals "$MACLIFT_CONFIG_DIR/logs/$MACLIFT_RUN_ID.notes" "${MACLIFT_NOTES:-}" "notes path for this run"
  assert_command_fails "[ -e '$MACLIFT_NOTES' ]" "no notes file up front"
  assert_equals "" "$(install_notes)" "nothing to show"
  maclift_note "first note"
  maclift_note "second note"
  assert_equals "$(printf '  • first note\n  • second note')" "$(install_notes)" "one bullet per note"
  printf '\nthird note\n\n' >>"$MACLIFT_NOTES"
  local rc=0 out
  out="$(install_notes)" || rc=$?
  assert_equals "0" "$rc" "returns 0 when the file ends with a blank line"
  assert_equals "$(printf '  • first note\n  • second note\n  • third note')" "$out" "blank lines skipped"
  printf 'no newline' >>"$MACLIFT_NOTES"
  assert_contains "$(install_notes)" "  • no newline" "last line without a newline is shown"
  unset MACLIFT_NOTES
}

# fake_script_dir: prints a temp MACLIFT_DIR whose catalog has script items
# a, b (a first) and x. a and b append their name to $MACLIFT_STUB_DIR/order;
# x reports that it needs elixir.
fake_script_dir() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/catalog" "$d/scripts/items"
  printf '@id x\n@title X\n@description X\n@default off\n@required off\n' >"$d/catalog/50-x.tsv"
  printf 'script\ta\toff\tItem a\ta.sh\nscript\tb\toff\tItem b\tb.sh\nscript\tx\toff\tItem x\tx.sh\n' >>"$d/catalog/50-x.tsv"
  printf '#!/usr/bin/env bash\n[ "$1" = --check ] && exit 1\necho a >>"$MACLIFT_STUB_DIR/order"\n' >"$d/scripts/items/a.sh"
  printf '#!/usr/bin/env bash\n[ "$1" = --check ] && exit 1\necho b >>"$MACLIFT_STUB_DIR/order"\n' >"$d/scripts/items/b.sh"
  printf '#!/usr/bin/env bash\n[ "$1" = --check ] && exit 1\necho elixir >"$MACLIFT_NEED_FILE"\nexit 3\n' >"$d/scripts/items/x.sh"
  printf '%s\n' "$d"
}

test_needs_skip_not_failed() {
  test_suite "needs-skip is not a failure"
  fresh_home
  local d rc=0 saved="$MACLIFT_DIR"
  d="$(fake_script_dir)"
  MACLIFT_DIR="$d"
  install_run 0 script:x >"$MACLIFT_STUB_DIR/out" 2>&1 || rc=$?
  MACLIFT_DIR="$saved"
  assert_equals "0" "$rc" "install_run returns 0"
  assert_command_succeeds "grep -q 'skipped script:x (needs elixir)' '$MACLIFT_STUB_DIR/out'" "skip line shown"
  assert_command_fails "grep -q '✗' '$MACLIFT_STUB_DIR/out'" "no fail line"
  assert_equals "" "$MACLIFT_FAILED" "not failed"
  assert_equals "script:x:elixir" "$MACLIFT_NEEDS" "needs recorded"
  assert_command_succeeds "grep -q 'SKIPPED script:x (needs elixir)' '$MACLIFT_CONFIG_DIR/logs/$MACLIFT_RUN_ID.log'" "log has skip"
}

test_script_catalog_order() {
  test_suite "scripts run in catalog order"
  fresh_home
  local d saved="$MACLIFT_DIR"
  d="$(fake_script_dir)"
  MACLIFT_DIR="$d"
  install_run 0 script:b script:a >/dev/null 2>&1 || true
  MACLIFT_DIR="$saved"
  assert_equals "a b" "$(tr '\n' ' ' <"$MACLIFT_STUB_DIR/order" | sed 's/ $//')" "a then b"
}

test_failure_continues
test_needs_skip_not_failed
test_script_catalog_order
test_skip_if_app
test_notes
test_asdf_fresh_mac
test_rerun
test_dry_run
test_dotfiles
test_asdf
test_order
test_brewfile_local
test_option_like
test_summary
