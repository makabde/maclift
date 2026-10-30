#!/usr/bin/env bash
#
# Guard: LICENSE, README and CONTRIBUTING say what they must
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"

README="$(cat "$PROJECT_ROOT/README.md" 2>/dev/null || true)"

test_license() {
  test_suite "LICENSE"
  local text
  text="$(cat "$PROJECT_ROOT/LICENSE" 2>/dev/null || true)"
  assert_contains "$text" "MIT License" "MIT text"
  assert_contains "$text" "Mak Abdennabi" "owner copyright"
  assert_contains "$text" "Cătălin Mariș" "upstream credit"
}

test_readme_headings() {
  test_suite "README headings"
  local h
  for h in "Install" "What you get" "Commands" "Make it yours" "Safety" "Contributing" "Credits"; do
    assert_contains "$README" $'\n## '"$h"$'\n' "has ## $h"
  done
}

test_readme_install_follows_version() {
  test_suite "README install line follows VERSION"
  local v
  v="$(tr -d '[:space:]' <"$PROJECT_ROOT/VERSION")"
  assert_contains "$README" "raw.githubusercontent.com/makabde/maclift/v$v/install" "install URL uses v$v"
}

test_readme_lists_commands() {
  test_suite "README lists every command"
  local help cmds cmd
  help="$("$PROJECT_ROOT/maclift" --help)"
  cmds="$(printf '%s\n' "$help" | awk '/^Commands:/ {on=1; next} /^[A-Za-z]/ {on=0} on && NF {print $1}')"
  assert_not_equals "" "$cmds" "found commands in --help"
  for cmd in $cmds; do
    assert_contains "$README" "maclift $cmd" "README mentions maclift $cmd"
  done
}

test_readme_install_notes() {
  test_suite "README: how to run it, custom folder, releases"
  assert_contains "$README" '`~/maclift/maclift <command>`' "says maclift runs from its folder"
  assert_contains "$README" "| MACLIFT_DIR=~/somewhere bash" "MACLIFT_DIR goes after the pipe"
  assert_contains "$README" '`maclift update` follows the `main` branch' "says update follows main"
}

test_readme_no_telemetry() {
  test_suite "README privacy line"
  assert_contains "$README" "No telemetry" "says no telemetry"
}

test_contributing() {
  test_suite "CONTRIBUTING"
  local text
  text="$(cat "$PROJECT_ROOT/CONTRIBUTING.md" 2>/dev/null || true)"
  assert_contains "$text" "catalog/" "mentions catalog/"
  assert_contains "$text" $'brew\tripgrep\ton\t' "has a tab-separated example line"
  assert_contains "$text" $'\n## Releases\n' "has ## Releases"
  assert_contains "$text" "never force-push" "main is never force-pushed"
}

test_license
test_readme_headings
test_readme_install_follows_version
test_readme_lists_commands
test_readme_install_notes
test_readme_no_telemetry
test_contributing
test_summary
