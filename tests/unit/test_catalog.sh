#!/usr/bin/env bash
#
# Unit tests for lib/catalog.sh and the public catalog files
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=lib/catalog.sh
source "$PROJECT_ROOT/lib/catalog.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
TAB="$(printf '\t')"

test_group_headers() {
  test_suite "catalog group headers"
  local f
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    local b
    b="$(basename "$f")"
    assert_command_succeeds "grep -q '^@id ' '$f'" "$b has @id"
    assert_command_succeeds "grep -q '^@title ' '$f'" "$b has @title"
    assert_command_succeeds "grep -q '^@description ' '$f'" "$b has @description"
  done
}

test_item_lines() {
  test_suite "catalog item lines"
  local f line n kind desc bad=""
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in "" | @* | "#"*) continue ;; esac
      n="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
      kind="${line%%"$TAB"*}"
      desc="$(printf '%s' "$line" | awk -F'\t' '{print $4}')"
      case "$n" in 4 | 5) ;; *) bad="$bad [fields:$line]" ;; esac
      case "$kind" in brew | cask | mas | asdf | dotfiles | script) ;; *) bad="$bad [kind:$line]" ;; esac
      if [ -z "$desc" ] || [ "${#desc}" -ge 60 ]; then bad="$bad [desc:$line]"; fi
    done <"$f"
  done
  assert_equals "" "$bad" "all item lines valid"
}

test_unique_ids() {
  test_suite "catalog ids unique"
  local all dups
  all="$(for g in $(catalog_groups); do catalog_items "$g"; done)"
  dups="$(printf '%s\n' "$all" | sort | uniq -d)"
  assert_equals "" "$dups" "no duplicate ids"
}

test_api() {
  test_suite "catalog functions"
  assert_equals "core" "$(catalog_groups | head -n1)" "first group is core"
  assert_equals "yes" "$(catalog_group_field core required)" "core required"
  assert_equals "no" "$(catalog_group_field cli required)" "cli not required"
  assert_equals "on" "$(catalog_group_field cli default)" "cli default on"
  assert_true "$(catalog_group_field core title)" "title non-empty"
  assert_true "$(catalog_item_field brew:bat description)" "bat description"
  assert_equals "cli" "$(catalog_item_field brew:bat group)" "bat group"
  assert_equals "on" "$(catalog_item_field brew:bat default)" "bat default"
  assert_contains "$(catalog_items cli)" "brew:bat" "cli items include bat"
  assert_equals "skip-if-app:/Applications/Visual Studio Code.app" \
    "$(catalog_item_field cask:visual-studio-code args)" "vscode skip arg"
  assert_equals "shell/tmux.conf" "$(catalog_item_field dotfiles:tmux args)" "tmux args"
  assert_command_succeeds "catalog_find brew:bat" "find bat"
  assert_command_fails "catalog_find cask:not-in-catalog" "unknown id absent"
}

test_catalog_table() {
  test_suite "catalog_table lists every item with its group, default and description"
  local table expected="" g id
  table="$(catalog_table)"
  for g in $(catalog_groups); do
    for id in $(catalog_items "$g"); do
      expected="$expected$g$TAB$id$TAB$(catalog_item_field "$id" default)$TAB$(catalog_item_field "$id" description)
"
    done
  done
  assert_equals "${expected%
}" "$table" "matches the per-item API, in display order"
  assert_contains "$table" "core${TAB}brew:git${TAB}on${TAB}Version control" "core git row"
  assert_equals "0" "$(printf '%s\n' "$table" | awk -F'\t' 'NF != 4' | wc -l | tr -d ' ')" "four fields per row"
}

test_dotfile_paths() {
  test_suite "dotfiles args exist"
  local id p missing=""
  for g in $(catalog_groups); do
    for id in $(catalog_items "$g"); do
      case "$id" in dotfiles:*)
        for p in $(catalog_item_field "$id" args); do
          [ -e "$MACLIFT_DIR/dotfiles/$p" ] || missing="$missing $p"
        done
        ;;
      esac
    done
  done
  assert_equals "" "$missing" "all dotfile paths exist"
}

test_group_headers
test_item_lines
test_unique_ids
test_api
test_catalog_table
test_dotfile_paths
test_summary
