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

# refute_contains <haystack> <needle> <message>: passes when needle is absent.
refute_contains() {
  case "$1" in
    *"$2"*) assert_false "$1" "$3" ;;
    *) assert_true "absent" "$3" ;;
  esac
}

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

# A hand-written ~/.gitconfig.local with signing, as on a Mac set up by hand.
hand_signing_file() {
  printf '[user]\n\tname = Old Name\n\temail = old@example.com\n\tsigningkey = HANDKEY0123456789\n[commit]\n\tgpgsign = true\n[tag]\n\tgpgSign = true\n' >"$1"
}

test_adopt_signing_key() {
  test_suite "identity: keeps hand-set signing (adopts the key)"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" out
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  hand_signing_file "$g"
  out="$(identity_render_gitconfig 0)"
  assert_contains "$out" "Kept commit signing with key HANDKEY0123456789; saved it to user.conf as MACLIFT_SIGNING_KEY (set it to \"\" to turn signing off)" "note printed"
  assert_equals "HANDKEY0123456789" "$(conf_get "$conf" MACLIFT_SIGNING_KEY)" "user.conf gains the key"
  assert_equals "HANDKEY0123456789" "$(git config -f "$g" user.signingkey)" "signingkey kept"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "commit.gpgsign kept"
  assert_equals "true" "$(git config -f "$g" tag.gpgsign)" "tag.gpgsign kept"
  assert_equals "1" "$(git config -f "$g" --get-all tag.gpgsign | wc -l | tr -d ' ')" "tag.gpgSign not duplicated"
  assert_equals "ada@example.com" "$(git config -f "$g" user.email)" "email from user.conf"
  assert_equals "Ada Lovelace" "$(git config -f "$g" user.name)" "name from user.conf"
  out="$(identity_render_gitconfig 0)"
  refute_contains "$out" "Kept commit signing" "second run: nothing more to adopt"
}

test_signing_explicit_off() {
  test_suite "identity: MACLIFT_SIGNING_KEY=\"\" turns signing off"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" out before
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  conf_set "$conf" MACLIFT_SIGNING_KEY ""
  before="$(cat "$conf")"
  hand_signing_file "$g"
  out="$(identity_render_gitconfig 0)"
  refute_contains "$out" "Kept commit signing" "no adoption note"
  assert_equals "$before" "$(cat "$conf")" "user.conf unchanged"
  assert_equals "" "$(git config -f "$g" user.signingkey || true)" "no signingkey"
  assert_equals "" "$(git config -f "$g" commit.gpgsign || true)" "no commit.gpgsign"
  assert_equals "" "$(git config -f "$g" tag.gpgsign || true)" "no tag.gpgsign"
}

test_carry_unmanaged() {
  test_suite "identity: hand-added settings survive a re-render"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local"
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  conf_set "$conf" MACLIFT_SIGNING_KEY ""
  printf '# my notes\n[user]\n\temail = hand@example.com\n\tuseConfigOnly = true\n[pull]\n\trebase = true\n[credential]\n\thelper =\n\thelper = osxkeychain\n[alias]\n\tlg = "log --oneline -n 5 ; # x"\n[url "ssh://git.example.com/"]\n\tinsteadOf = https://git.example.com/\n' >"$g"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "ada@example.com" "$(git config -f "$g" user.email)" "owned email from user.conf"
  assert_equals "1" "$(git config -f "$g" --get-all user.email | wc -l | tr -d ' ')" "one email only"
  assert_equals "true" "$(git config -f "$g" pull.rebase)" "pull.rebase kept"
  assert_equals "true" "$(git config -f "$g" user.useConfigOnly)" "user.useConfigOnly kept"
  assert_equals "$(printf '\nosxkeychain')" "$(git config -f "$g" --get-all credential.helper)" "multi-valued credential.helper kept in order"
  assert_equals "log --oneline -n 5 ; # x" "$(git config -f "$g" alias.lg)" "value with ; and # kept"
  assert_equals "https://git.example.com/" "$(git config -f "$g" 'url.ssh://git.example.com/.insteadOf')" "subsection key kept"
  local n
  n="$(find "$MACLIFT_CONFIG_DIR/backups" -name .gitconfig.local | wc -l | tr -d ' ')"
  assert_equals "1" "$n" "changed file backed up"
  local out
  out="$(identity_render_gitconfig 0)"
  assert_contains "$out" "ok $g" "second render leaves the file alone"
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .gitconfig.local | wc -l | tr -d ' ')" "no new backup"
}

test_carry_include_last() {
  test_suite "identity: alt includeIf stays last, old one replaced"
  alt_setup
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work"
  local g="$MACLIFT_HOME/.gitconfig.local"
  printf '[includeIf "gitdir:~/Old/"]\n\tpath = ~/.gitconfig.alt\n[includeIf "gitdir:~/Other/"]\n\tpath = ~/.gitconfig.other\n[pull]\n\trebase = true\n' >"$g"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "" "$(git config -f "$g" 'includeIf.gitdir:~/Old/.path' || true)" "old maclift includeIf dropped"
  assert_equals "~/.gitconfig.other" "$(git config -f "$g" 'includeIf.gitdir:~/Other/.path')" "unrelated includeIf kept"
  assert_contains "$(git config -f "$g" --list | tail -n 1)" "includeif.gitdir:~/Work/.path=~/.gitconfig.alt" "alt includeIf is last"
  assert_contains "$(identity_render_gitconfig 0)" "ok $g" "re-render is a no-op"
}

test_adopt_dry_run() {
  test_suite "identity: dry run reports adoption, writes nothing"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" out before_conf before_g
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  hand_signing_file "$g"
  before_conf="$(cat "$conf")"
  before_g="$(cat "$g")"
  out="$(identity_render_gitconfig 1)"
  assert_contains "$out" "HANDKEY0123456789" "names the key it would keep"
  assert_contains "$out" "MACLIFT_SIGNING_KEY" "names the user.conf key"
  assert_equals "$before_conf" "$(cat "$conf")" "user.conf unchanged"
  assert_equals "$before_g" "$(cat "$g")" ".gitconfig.local unchanged"
  assert_command_fails "[ -d '$MACLIFT_CONFIG_DIR/backups' ]" "no backup made"
}

test_alt_adopt_and_carry() {
  test_suite "identity: alt file keeps a hand-set key and extra settings"
  alt_setup
  local g="$MACLIFT_HOME/.gitconfig.alt" out
  printf '[user]\n\tname = Work User\n\temail = work@example.com\n\tsigningkey = WORKHANDKEY001\n[commit]\n\tgpgsign = true\n[core]\n\tsshCommand = ssh -i ~/.ssh/work\n' >"$g"
  out="$(identity_render_alt 1)"
  assert_contains "$out" "WORKHANDKEY001" "dry run names the alt key"
  assert_command_fails "conf_get '$ALT_CONF' MACLIFT_ALT_SIGNING_KEY" "dry run: user.conf unchanged"
  assert_command_fails "identity_alt_current" "pending adoption: not current"
  out="$(identity_render_alt 0)"
  assert_contains "$out" "Kept commit signing with key WORKHANDKEY001; saved it to user.conf as MACLIFT_ALT_SIGNING_KEY (set it to \"\" to turn signing off)" "alt note"
  assert_equals "WORKHANDKEY001" "$(conf_get "$ALT_CONF" MACLIFT_ALT_SIGNING_KEY)" "alt key adopted"
  assert_equals "WORKHANDKEY001" "$(git config -f "$g" user.signingkey)" "alt signingkey kept"
  assert_equals "true" "$(git config -f "$g" tag.gpgsign)" "alt tag signing on"
  assert_equals "ssh -i ~/.ssh/work" "$(git config -f "$g" core.sshCommand)" "extra alt setting kept"
  assert_command_succeeds "identity_alt_current" "current after render"
  assert_contains "$(identity_render_alt 0)" "ok $g" "re-render is a no-op"
  git config -f "$g" --add pull.rebase true
  assert_command_succeeds "identity_alt_current" "hand-added setting still current"
}

test_alt_blank_key_not_adopted() {
  test_suite "identity: maclift's blank alt key is not adopted"
  alt_setup
  local g="$MACLIFT_HOME/.gitconfig.alt" out
  identity_render_alt 0 >/dev/null
  assert_equals "" "$(git config -f "$g" user.signingkey)" "blank key written"
  out="$(identity_render_alt 0)"
  refute_contains "$out" "Kept commit signing" "no adoption"
  assert_command_fails "conf_get '$ALT_CONF' MACLIFT_ALT_SIGNING_KEY" "no MACLIFT_ALT_SIGNING_KEY line"
  assert_command_succeeds "identity_alt_current" "still current"
  conf_set "$ALT_CONF" MACLIFT_ALT_SIGNING_KEY ""
  printf '[user]\n\tsigningkey = SOMEKEY\n' >>"$g"
  identity_render_alt 0 >/dev/null
  assert_equals "" "$(git config -f "$g" user.signingkey)" "explicit off: key blank"
  assert_equals "false" "$(git config -f "$g" commit.gpgsign)" "explicit off: signing off"
}

test_alt_include_user_paths_kept() {
  test_suite "identity: user's own includeIf for the alt folder is kept"
  alt_setup
  conf_set "$ALT_CONF" MACLIFT_ALT_DIR "~/Work"
  local g="$MACLIFT_HOME/.gitconfig.local" out rc
  printf '[includeIf "gitdir:~/Work/"]\n\tpath = ~/.gitconfig.work-extra\n' >"$g"
  rc=0
  identity_render_gitconfig 0 >/dev/null || rc=$?
  assert_equals "0" "$rc" "one user path: render succeeds"
  assert_equals "$(printf '~/.gitconfig.work-extra\n~/.gitconfig.alt')" "$(git config -f "$g" --get-all 'includeIf.gitdir:~/Work/.path')" "one user path: kept, maclift's once and last"
  assert_contains "$(identity_render_gitconfig 0)" "ok $g" "one user path: re-render is a no-op"
  printf '[includeIf "gitdir:~/Work/"]\n\tpath = ~/.gitconfig.a\n\tpath = ~/.gitconfig.b\n' >"$g"
  rc=0
  identity_render_gitconfig 0 >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "two user paths: render succeeds"
  assert_equals "$(printf '~/.gitconfig.a\n~/.gitconfig.b\n~/.gitconfig.alt')" "$(git config -f "$g" --get-all 'includeIf.gitdir:~/Work/.path')" "two user paths: kept, maclift's once"
  assert_contains "$(identity_render_gitconfig 0)" "ok $g" "two user paths: re-render is a no-op"
}

test_ssh_signing_carried() {
  test_suite "identity: ssh signing is kept as is, not adopted"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" out
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  printf '[user]\n\tsigningkey = ~/.ssh/id_ed25519.pub\n[gpg]\n\tformat = ssh\n[gpg "ssh"]\n\tallowedSignersFile = ~/.ssh/allowed\n[commit]\n\tgpgsign = true\n[tag]\n\tgpgsign = true\n' >"$g"
  out="$(identity_render_gitconfig 0)"
  refute_contains "$out" "Kept" "no adoption note"
  assert_command_fails "conf_get '$conf' MACLIFT_SIGNING_KEY" "user.conf has no MACLIFT_SIGNING_KEY"
  assert_equals "~/.ssh/id_ed25519.pub" "$(git config -f "$g" user.signingkey)" "ssh signingkey kept"
  assert_equals "ssh" "$(git config -f "$g" gpg.format)" "gpg.format kept"
  assert_equals "~/.ssh/allowed" "$(git config -f "$g" gpg.ssh.allowedSignersFile)" "gpg.ssh setting kept"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "commit.gpgsign kept"
  assert_equals "true" "$(git config -f "$g" tag.gpgsign)" "tag.gpgsign kept"
  assert_equals "1" "$(git config -f "$g" --get-all user.signingkey | wc -l | tr -d ' ')" "signingkey once"
  assert_contains "$(identity_render_gitconfig 0)" "ok $g" "second render is a no-op"
}

test_gpg_key_drops_other_format() {
  test_suite "identity: with MACLIFT_SIGNING_KEY, gpg.format is maclift's"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local"
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  conf_set "$conf" MACLIFT_SIGNING_KEY "ABCDEF0123456789"
  printf '[user]\n\tsigningkey = ~/.ssh/id_ed25519.pub\n[gpg]\n\tformat = ssh\n\tprogram = /opt/gpg\n' >"$g"
  identity_render_gitconfig 0 >/dev/null
  assert_equals "ABCDEF0123456789" "$(git config -f "$g" user.signingkey)" "GPG key from user.conf"
  assert_equals "" "$(git config -f "$g" gpg.format || true)" "gpg.format = ssh dropped"
  assert_equals "/opt/gpg" "$(git config -f "$g" gpg.program)" "other gpg settings kept"
  assert_contains "$(identity_render_gitconfig 0)" "ok $g" "second render is a no-op"
}

test_adopt_turns_signing_on_note() {
  test_suite "identity: adopting a key without gpgsign says signing is turned on"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" out
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  printf '[user]\n\tsigningkey = KEYONLY01\n' >"$g"
  out="$(identity_render_gitconfig 0)"
  assert_contains "$out" 'Kept signing key KEYONLY01 and turned on commit and tag signing; saved it to user.conf as MACLIFT_SIGNING_KEY (set it to "" to turn signing off)' "note says signing is turned on"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "signing on"
}

test_unreadable_old_file_warns() {
  test_suite "identity: unreadable old file is named in the warning"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" err
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  printf '[broken\n' >"$g"
  err="$(identity_render_gitconfig 0 2>&1 >/dev/null)"
  assert_contains "$err" "signing settings in it could not be kept; the old file is backed up" "warning"
  assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups" -name .gitconfig.local | wc -l | tr -d ' ')" "old file backed up"
}

test_alt_ssh_signing_carried() {
  test_suite "identity: alt ssh signing kept as is"
  alt_setup
  local g="$MACLIFT_HOME/.gitconfig.alt" out
  printf '[user]\n\tsigningkey = ~/.ssh/work.pub\n[gpg]\n\tformat = ssh\n[commit]\n\tgpgsign = true\n' >"$g"
  out="$(identity_render_alt 0)"
  refute_contains "$out" "Kept" "no adoption note"
  assert_command_fails "conf_get '$ALT_CONF' MACLIFT_ALT_SIGNING_KEY" "no MACLIFT_ALT_SIGNING_KEY"
  assert_equals "~/.ssh/work.pub" "$(git config -f "$g" user.signingkey)" "alt ssh key kept"
  assert_equals "1" "$(git config -f "$g" --get-all user.signingkey | wc -l | tr -d ' ')" "alt key once (no blank key added)"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "alt commit signing kept"
  assert_equals "ssh" "$(git config -f "$g" gpg.format)" "alt gpg.format kept"
  assert_command_succeeds "identity_alt_current" "alt current"
  assert_contains "$(identity_render_alt 0)" "ok $g" "alt re-render no-op"
  conf_set "$ALT_CONF" MACLIFT_ALT_SIGNING_KEY "WORKGPG01"
  identity_render_alt 0 >/dev/null
  assert_equals "WORKGPG01" "$(git config -f "$g" user.signingkey)" "alt GPG key from user.conf"
  assert_equals "" "$(git config -f "$g" gpg.format || true)" "alt gpg.format dropped with a GPG key"
}

test_sign_by_email_kept() {
  test_suite "identity: signing without a key (by email) is kept as is"
  fresh_home
  local conf="$MACLIFT_CONFIG_DIR/user.conf" g="$MACLIFT_HOME/.gitconfig.local" out
  conf_set "$conf" MACLIFT_NAME "Ada Lovelace"
  conf_set "$conf" MACLIFT_EMAIL "ada@example.com"
  printf '[commit]\n\tgpgsign = true\n[tag]\n\tgpgSign = false\n[gpg]\n\tprogram = /opt/gpg\n' >"$g"
  out="$(identity_render_gitconfig 0)"
  refute_contains "$out" "Kept" "no adoption note"
  assert_command_fails "conf_get '$conf' MACLIFT_SIGNING_KEY" "no MACLIFT_SIGNING_KEY line"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "commit.gpgsign kept"
  assert_equals "false" "$(git config -f "$g" tag.gpgsign)" "tag.gpgsign kept (any value)"
  assert_equals "/opt/gpg" "$(git config -f "$g" gpg.program)" "gpg.program kept"
  assert_equals "" "$(git config -f "$g" user.signingkey || true)" "no signingkey added"
  assert_contains "$(identity_render_gitconfig 0)" "ok $g" "second render is a no-op"
  conf_set "$conf" MACLIFT_SIGNING_KEY ""
  identity_render_gitconfig 0 >/dev/null
  assert_equals "" "$(git config -f "$g" commit.gpgsign || true)" "explicit \"\": commit.gpgsign dropped"
  assert_equals "" "$(git config -f "$g" tag.gpgsign || true)" "explicit \"\": tag.gpgsign dropped"
}

test_alt_sign_by_email_safety() {
  test_suite "identity: alt signing without an alt key stays off"
  alt_setup
  local g="$MACLIFT_HOME/.gitconfig.alt"
  printf '[commit]\n\tgpgsign = true\n[tag]\n\tgpgsign = true\n[gpg]\n\tprogram = /opt/gpg\n' >"$g"
  identity_render_alt 0 >/dev/null
  assert_equals "false" "$(git config -f "$g" commit.gpgsign)" "alt commit.gpgsign forced off"
  assert_equals "false" "$(git config -f "$g" tag.gpgsign)" "alt tag.gpgsign forced off"
  assert_equals "1" "$(git config -f "$g" --get-all commit.gpgsign | wc -l | tr -d ' ')" "alt gpgsign once"
  assert_equals "" "$(git config -f "$g" user.signingkey)" "alt blank signing key"
  assert_equals "/opt/gpg" "$(git config -f "$g" gpg.program)" "alt gpg.program kept"
  assert_command_fails "conf_get '$ALT_CONF' MACLIFT_ALT_SIGNING_KEY" "no MACLIFT_ALT_SIGNING_KEY"
  assert_contains "$(identity_render_alt 0)" "ok $g" "alt re-render no-op"
}

test_roundtrip
test_sign_by_email_kept
test_alt_sign_by_email_safety
test_alt_include_user_paths_kept
test_ssh_signing_carried
test_gpg_key_drops_other_format
test_adopt_turns_signing_on_note
test_unreadable_old_file_warns
test_alt_ssh_signing_carried
test_adopt_signing_key
test_signing_explicit_off
test_carry_unmanaged
test_carry_include_last
test_adopt_dry_run
test_alt_adopt_and_carry
test_alt_blank_key_not_adopted
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
