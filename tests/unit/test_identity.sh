#!/usr/bin/env bash
#
# Unit tests for lib/identity.sh
#

# shellcheck disable=SC2088 # literal ~/ paths are the values under test
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
# shellcheck source=lib/identity.sh
source "$PROJECT_ROOT/lib/identity.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
export MACLIFT_PLAIN=1
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
unset MACLIFT_ASSUME_YES

fresh_home() {
  MACLIFT_HOME="$(mktemp -d)"
  export MACLIFT_HOME HOME="$MACLIFT_HOME"
  unset MACLIFT_RUN_ID
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
}

test_signing_key() {
  test_suite "identity render with a signing key"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local"
  conf_set "$conf" MACLIFT_NAME "Test User"
  conf_set "$conf" MACLIFT_EMAIL "test@example.com"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "" "$(git config -f "$g" user.signingkey || true)" "no signing key by default"
  assert_equals "" "$(git config -f "$g" commit.gpgsign || true)" "no gpgsign by default"
  conf_set "$conf" MACLIFT_SIGNING_KEY "ABCDEF0123456789"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "ABCDEF0123456789" "$(git config -f "$g" user.signingkey)" "signing key rendered"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "commit.gpgsign"
  assert_equals "true" "$(git config -f "$g" tag.gpgsign)" "tag.gpgsign"
}

test_roundtrip() {
  test_suite "identity ask and render"
  fresh_home
  printf "Seán O'Brien\nsean@example.com\nsobrien\n" | identity_ask 2>/dev/null
  local conf="$MACLIFT_CONFIG_DIR/user.conf"
  assert_equals "Seán O'Brien" "$(conf_get "$conf" MACLIFT_NAME)" "name saved"
  assert_equals "sean@example.com" "$(conf_get "$conf" MACLIFT_EMAIL)" "email saved"
  assert_equals "sobrien" "$(conf_get "$conf" MACLIFT_GITHUB)" "github saved"
  identity_render_gitconfig 0 >/dev/null
  local g="$MACLIFT_HOME/.gitconfig.local"
  assert_equals "Seán O'Brien" "$(git config -f "$g" user.name)" "gitconfig name"
  assert_equals "sean@example.com" "$(git config -f "$g" user.email)" "gitconfig email"
}

test_bad_email() {
  test_suite "identity re-asks bad email"
  fresh_home
  printf "Ada Lovelace\nbad\nok@example.com\n\n" | identity_ask 2>/dev/null
  assert_equals "ok@example.com" "$(conf_get "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL)" "valid email kept"
}

test_rerun_keeps() {
  test_suite "identity re-run keeps values"
  fresh_home
  printf "Ada Lovelace\nada@example.com\nada\n" | identity_ask 2>/dev/null
  printf "\n\n\n" | identity_ask 2>/dev/null
  local conf="$MACLIFT_CONFIG_DIR/user.conf"
  assert_equals "Ada Lovelace" "$(conf_get "$conf" MACLIFT_NAME)" "name kept"
  assert_equals "ada@example.com" "$(conf_get "$conf" MACLIFT_EMAIL)" "email kept"
  assert_equals "ada" "$(conf_get "$conf" MACLIFT_GITHUB)" "github kept"
}

test_assume_yes() {
  test_suite "identity assume-yes"
  fresh_home
  local rc=0 out
  out="$(MACLIFT_ASSUME_YES=1 identity_ask </dev/null 2>&1)" || rc=$?
  assert_not_equals "0" "$rc" "fails without user.conf"
  assert_contains "$out" "run maclift once interactively first" "message"
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL "ada@example.com"
  rc=0
  MACLIFT_ASSUME_YES=1 identity_ask </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "succeeds with saved values"
}

test_escaping() {
  test_suite "identity escaping"
  fresh_home
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_NAME 'Ada "The\Countess" L'
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL "ada@example.com"
  identity_render_gitconfig 0 >/dev/null
  assert_equals 'Ada "The\Countess" L' "$(git config -f "$MACLIFT_HOME/.gitconfig.local" user.name)" "quotes and backslash"
}

test_render_backup_and_idempotent() {
  test_suite "identity render backup"
  fresh_home
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL "ada@example.com"
  local g="$MACLIFT_HOME/.gitconfig.local"
  printf '[user]\n\tname = Someone Else\n' >"$g"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "Ada Lovelace" "$(git config -f "$g" user.name)" "replaced"
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .gitconfig.local | wc -l | tr -d ' ')" "old file backed up"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .gitconfig.local | wc -l | tr -d ' ')" "identical: no new backup"
}

test_dry_run() {
  test_suite "identity render dry-run"
  fresh_home
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL "ada@example.com"
  local out
  out="$(identity_render_gitconfig 1)"
  assert_contains "$out" "would write $MACLIFT_HOME/.gitconfig.local" "announces"
  assert_command_fails "[ -e '$MACLIFT_HOME/.gitconfig.local' ]" "nothing written"
}

alt_setup() {
  fresh_home
  ALT_CONF="$MACLIFT_CONFIG_DIR/user.conf"
  conf_set "$ALT_CONF" MACLIFT_NAME "Test User"
  conf_set "$ALT_CONF" MACLIFT_EMAIL "test@example.com"
  conf_set "$ALT_CONF" MACLIFT_ALT_NAME "Work User"
  conf_set "$ALT_CONF" MACLIFT_ALT_EMAIL "work@example.com"
  conf_set "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS "brew:git script:second-identity"
}

test_alt_include() {
  test_suite "identity: includeIf for the second folder"
  alt_setup
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work"
  identity_render_gitconfig 0 >/dev/null
  local g="$MACLIFT_HOME/.gitconfig.local"
  assert_equals "~/.gitconfig.alt" "$(git config -f "$g" 'includeIf.gitdir:~/Work/.path')" "includeIf rendered"
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work/"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "~/.gitconfig.alt" "$(git config -f "$g" 'includeIf.gitdir:~/Work/.path')" "trailing slash: one slash only"
  assert_command_fails "grep -q 'Work//' '$g'" "no double slash in the file"
}

test_alt_resolves() {
  test_suite "identity: real git picks the right email"
  alt_setup
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work"
  printf '[include]\n\tpath = ~/.gitconfig.local\n' >"$MACLIFT_HOME/.gitconfig"
  identity_render_gitconfig 0 >/dev/null
  identity_render_alt 0 >/dev/null
  mkdir -p "$MACLIFT_HOME/Work/proj" "$MACLIFT_HOME/Play/proj"
  git init -q "$MACLIFT_HOME/Work/proj"
  git init -q "$MACLIFT_HOME/Play/proj"
  local inside outside
  inside="$(GIT_CONFIG_GLOBAL="$MACLIFT_HOME/.gitconfig" git -C "$MACLIFT_HOME/Work/proj" config user.email)"
  outside="$(GIT_CONFIG_GLOBAL="$MACLIFT_HOME/.gitconfig" git -C "$MACLIFT_HOME/Play/proj" config user.email)"
  assert_equals "work@example.com" "$inside" "inside the folder: alt email"
  assert_equals "test@example.com" "$outside" "outside: main email"
}

test_alt_render() {
  test_suite "identity: render alt"
  alt_setup
  local out g="$MACLIFT_HOME/.gitconfig.alt"
  out="$(identity_render_alt 0)"
  assert_contains "$out" "wrote $g" "first render writes"
  assert_equals "Work User" "$(git config -f "$g" user.name)" "name"
  assert_equals "false" "$(git config -f "$g" commit.gpgsign)" "no alt key: signing off"
  assert_equals "" "$(git config -f "$g" user.signingkey || true)" "no signing key"
  out="$(identity_render_alt 0)"
  assert_contains "$out" "ok $g" "second render is ok"
  conf_set "$ALT_CONF" MACLIFT_ALT_SIGNING_KEY "FEEDFACE12345678"
  identity_render_alt 0 >/dev/null
  assert_equals "FEEDFACE12345678" "$(git config -f "$g" user.signingkey)" "alt signing key"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "alt signing on"
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .gitconfig.alt | wc -l | tr -d ' ')" "changed file backed up"
  rm -f "$g"
  out="$(identity_render_alt 1)"
  assert_contains "$out" "would write" "dry run announces"
  assert_command_fails "[ -e '$g' ]" "dry run writes nothing"
}

test_alt_ask() {
  test_suite "identity: ask alt"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf"
  printf 'Work User\nbad-email\nwork@example.com\nrelative/dir\n\n~/Work/\n' | identity_ask_alt 2>/dev/null
  assert_equals "Work User" "$(conf_get "$conf" MACLIFT_ALT_NAME)" "name saved"
  assert_equals "work@example.com" "$(conf_get "$conf" MACLIFT_ALT_EMAIL)" "bad email asked again"
  assert_equals "~/Work" "$(conf_get "$conf" MACLIFT_ALT_DIR)" "relative and empty folder rejected, slash stripped"
  printf 'W\nw@example.com\n/abs/dir\n' | identity_ask_alt 2>/dev/null
  assert_equals "/abs/dir" "$(conf_get "$conf" MACLIFT_ALT_DIR)" "absolute path accepted"
  local rc=0
  printf 'W\nw@example.com\nnope\nnope\nnope\nnope\nnope\n' | identity_ask_alt >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "gives up on a bad folder"
  rc=0
  MACLIFT_ASSUME_YES=1 identity_ask_alt 2>/dev/null || rc=$?
  assert_equals "0" "$rc" "-y uses saved values"
  conf_set "$conf" MACLIFT_ALT_DIR "relative"
  rc=0
  MACLIFT_ASSUME_YES=1 identity_ask_alt 2>/dev/null || rc=$?
  assert_equals "1" "$rc" "-y rejects a bad saved folder"
}

test_alt_deselected() {
  test_suite "identity: deselected item writes no includeIf"
  alt_setup
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work"
  conf_set "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS "brew:git"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "" "$(git config -f "$MACLIFT_HOME/.gitconfig.local" 'includeIf.gitdir:~/Work/.path' || true)" "no includeIf"
}

test_alt_bad_dir_and_space() {
  test_suite "identity: folder cleanup and validation"
  alt_setup
  local g="$MACLIFT_HOME/.gitconfig.local"
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "relative/dir"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "" "$(git config -f "$g" --get-regexp '^includeif' || true)" "relative folder: no includeIf"
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/My Work//clients/"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "~/.gitconfig.alt" "$(git config -f "$g" 'includeIf.gitdir:~/My Work/clients/.path')" "slashes collapsed, space kept"
  local d
  for d in "~" "~/" "/" "//"; do
    assert_command_fails "_identity_alt_dir '$d'" "rejects '$d'"
  done
}

test_alt_no_key_never_signs_personal() {
  test_suite "identity: alt folder never uses the personal key"
  alt_setup
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work"
  conf_set "$ALT_CONF" MACLIFT_SIGNING_KEY "PERSONALKEY0001"
  printf '[include]\n\tpath = ~/.gitconfig.local\n' >"$MACLIFT_HOME/.gitconfig"
  identity_render_gitconfig 0 >/dev/null
  identity_render_alt 0 >/dev/null
  mkdir -p "$MACLIFT_HOME/Work/proj" "$MACLIFT_HOME/Play/proj"
  git init -q "$MACLIFT_HOME/Work/proj"
  git init -q "$MACLIFT_HOME/Play/proj"
  local gl="$MACLIFT_HOME/.gitconfig"
  assert_equals "PERSONALKEY0001" "$(GIT_CONFIG_GLOBAL=$gl git -C "$MACLIFT_HOME/Play/proj" config user.signingkey)" "outside: personal key"
  assert_equals "" "$(GIT_CONFIG_GLOBAL=$gl git -C "$MACLIFT_HOME/Work/proj" config user.signingkey)" "inside: signing key blank"
  assert_equals "false" "$(GIT_CONFIG_GLOBAL=$gl git -C "$MACLIFT_HOME/Work/proj" config tag.gpgsign)" "inside: tag.gpgsign false"
  assert_equals "false" "$(GIT_CONFIG_GLOBAL=$gl git -C "$MACLIFT_HOME/Work/proj" config commit.gpgsign)" "inside: commit.gpgsign false"
  conf_set "$ALT_CONF" MACLIFT_ALT_SIGNING_KEY "WORKKEY0002"
  identity_render_alt 0 >/dev/null
  assert_equals "WORKKEY0002" "$(GIT_CONFIG_GLOBAL=$gl git -C "$MACLIFT_HOME/Work/proj" config user.signingkey)" "with alt key: alt key"
  assert_equals "true" "$(GIT_CONFIG_GLOBAL=$gl git -C "$MACLIFT_HOME/Work/proj" config tag.gpgsign)" "with alt key: tag.gpgsign true"
}

test_roundtrip
test_alt_deselected
test_alt_bad_dir_and_space
test_alt_no_key_never_signs_personal
test_alt_include
test_alt_resolves
test_alt_render
test_alt_ask
test_signing_key
test_bad_email
test_rerun_keeps
test_assume_yes
test_escaping
test_render_backup_and_idempotent
test_dry_run
test_summary
