#!/usr/bin/env bash
#
# Unit tests for lib/selection.sh
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

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
TMP_DIR="$(mktemp -d)"


test_defaults() {
  test_suite "selection_defaults"
  local d core off
  d="$(selection_defaults)"
  core="$(catalog_items core)"
  assert_equals "" "$(printf '%s\n' "$core" | while read -r i; do printf '%s\n' "$d" | grep -qx "$i" || echo "$i"; done)" "defaults contain every core item"
  off=""
  local i
  for i in $(catalog_items dev-apps) $(catalog_items cli); do
    if [ -z "$off" ] && [ "$(catalog_item_field "$i" default)" = off ]; then off="$i"; fi
  done
  assert_command_succeeds "[ -n '$off' ]" "found an off item"
  assert_command_fails "printf '%s\\n' \"$d\" | grep -qx '$off'" "defaults exclude off item $off"
  assert_equals "$(printf '%s\n' "$d" | sort)" "$(selection_load | sort)" "load without file equals defaults"
}

test_new_defaults() {
  test_suite "language toolchain defaults"
  local d i
  d="$(selection_defaults)"
  for i in brew:pnpm script:hex script:rebar script:phx_new script:python; do
    assert_command_succeeds "printf '%s\\n' \"$d\" | grep -qx '$i'" "defaults contain $i"
  done
  for i in asdf:python brew:xz; do
    assert_command_fails "printf '%s\\n' \"$d\" | grep -qx '$i'" "defaults exclude $i"
  done
}

test_seen_migration_once() {
  test_suite "new default-on items are offered once to a 1.0.0 selection"
  local i out items
  rm -rf "$MACLIFT_HOME/.config"
  mkdir -p "$MACLIFT_CONFIG_DIR"
  printf 'MACLIFT_GROUPS="cli"\nMACLIFT_ITEMS="brew:git asdf:python brew:xz"\n' >"$MACLIFT_CONFIG_DIR/selection.conf"
  out="$(selection_new_defaults)"
  for i in brew:pnpm script:hex script:rebar script:phx_new script:python; do
    assert_command_succeeds "printf '%s\\n' \"$out\" | grep -qx '$i'" "offers $i"
  done
  assert_command_fails "printf '%s\\n' \"$out\" | grep -qx 'brew:rebar3'" "not brew:rebar3 (not default-on)"
  assert_command_fails "printf '%s\\n' \"$out\" | grep -qx 'brew:bat'" "nothing older than 1.0.0"
  # shellcheck disable=SC2046
  selection_save brew:git asdf:python brew:xz $(selection_new_defaults)
  assert_equals "" "$(selection_new_defaults)" "nothing offered after saving"
  items="$(conf_get "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS)"
  assert_contains "$items" "asdf:python" "asdf:python kept"
  assert_contains "$items" "brew:xz" "brew:xz kept"
  assert_contains "$items" "script:hex" "script:hex added"
}

test_no_offer_on_fresh_mac() {
  test_suite "no offer without a saved selection"
  rm -rf "$MACLIFT_HOME/.config"
  assert_equals "" "$(selection_new_defaults)" "prints nothing"
}

test_unticked_stays_unticked() {
  test_suite "an unticked new item stays unticked"
  rm -rf "$MACLIFT_HOME/.config"
  mkdir -p "$MACLIFT_CONFIG_DIR"
  printf 'MACLIFT_ITEMS="brew:git"\n' >"$MACLIFT_CONFIG_DIR/selection.conf"
  selection_save brew:git brew:pnpm
  assert_equals "" "$(selection_new_defaults)" "script:hex not offered again"
}

test_save_load() {
  test_suite "selection_save / selection_load"
  local core out
  selection_save brew:bat cask:iterm2
  core="$(catalog_items core | sort)"
  out="$(selection_load | sort)"
  assert_contains "$out" "brew:bat" "has brew:bat"
  assert_contains "$out" "cask:iterm2" "has cask:iterm2"
  assert_equals "" "$(printf '%s\n' "$core" | while read -r i; do printf '%s\n' "$out" | grep -qx "$i" || echo "$i"; done)" "required items added"
  assert_equals "$(( $(printf '%s\n' "$core" | wc -l) + 2 ))" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "no extra items"
  assert_contains "$(conf_get "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_GROUPS)" "core" "groups include core"
  assert_contains "$(conf_get "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_GROUPS)" "cli" "groups include cli"
  selection_save brew:bat
  assert_equals "" "$(selection_load | grep -x cask:iterm2 || true)" "resave replaces"
}

test_load_required() {
  test_suite "selection_load always includes required items"
  local out core
  conf_set "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS "brew:bat"
  out="$(selection_load)"
  core="$(catalog_items core)"
  assert_contains "$out" "brew:bat" "kept brew:bat"
  assert_equals "" "$(printf '%s\n' "$core" | while read -r i; do printf '%s\n' "$out" | grep -qx "$i" || echo "$i"; done)" "core items merged in"
  assert_equals "" "$(printf '%s\n' "$out" | sort | uniq -d)" "no duplicates"
}

test_import() {
  test_suite "selection_import"
  local f="$TMP_DIR/in.conf" err out
  conf_set "$f" MACLIFT_ITEMS "brew:bat cask:not-in-catalog script:x"
  err="$(selection_import "$f" 2>&1 >/dev/null)"
  out="$(selection_load)"
  assert_contains "$out" "brew:bat" "kept brew:bat"
  assert_equals "" "$(printf '%s\n' "$out" | grep -E 'not-in-catalog|script:x' || true)" "dropped unknown and script"
  assert_contains "$err" "skipped cask:not-in-catalog (not in catalog)" "warned not-in-catalog"
  assert_contains "$err" "skipped script:x (not in catalog)" "warned script:x"

  conf_set "$f" MACLIFT_ITEMS "\$(touch $TMP_DIR/pwned)"
  selection_import "$f" >/dev/null 2>&1 || true
  assert_command_fails "[ -e '$TMP_DIR/pwned' ]" "import executed nothing"

  assert_command_fails "selection_import '$TMP_DIR/missing.conf' >/dev/null 2>&1" "missing file fails"
}

test_import_url() {
  test_suite "selection_import url"
  local stub="$TMP_DIR/curl-stub"
  cat >"$stub" <<'STUB'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; esac
  shift
done
printf 'MACLIFT_ITEMS="brew:jq"\n' >"$out"
STUB
  chmod +x "$stub"
  MACLIFT_CURL="$stub" selection_import "https://example.invalid/sel.conf" >/dev/null 2>&1
  assert_contains "$(selection_load)" "brew:jq" "url import kept brew:jq"
}

test_defaults
test_new_defaults
test_seen_migration_once
test_no_offer_on_fresh_mac
test_unticked_stays_unticked
test_save_load
test_load_required
test_import
test_import_url
test_summary
