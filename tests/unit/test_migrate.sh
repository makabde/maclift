#!/usr/bin/env bash
#
# Unit tests for lib/migrate.sh
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=lib/migrate.sh
source "$PROJECT_ROOT/lib/migrate.sh"
# shellcheck source=lib/dotfiles.sh
source "$PROJECT_ROOT/lib/dotfiles.sh"

# Sandbox: $T/old is the old repo, $T/maclift is a fake maclift tree,
# $T/home/user is a nested home.
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/old/dotfiles/shell/zsh" "$T/maclift/dotfiles/shell/zsh" "$T/home/user/.config"
echo z >"$T/old/dotfiles/shell/zshrc"
echo n >"$T/old/dotfiles/shell/nv"
echo i >"$T/old/dotfiles/shell/inputrc"
echo mz >"$T/maclift/dotfiles/shell/zshrc"
echo 0.0.0 >"$T/maclift/VERSION"
export MACLIFT_DIR="$T/maclift"
export MACLIFT_HOME="$T/home/user"
maclift_init_paths

H="$MACLIFT_HOME"
OLD="$T/old"
OLDR="$(maclift_real_path "$OLD")"
ln -s "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
ln -s "$OLD/dotfiles/shell/zsh" "$H/.zsh"
ln -s "$OLD/dotfiles/shell/nv" "$H/.nv"
ln -s "../../old/dotfiles/shell/inputrc" "$H/.inputrc"
ln -s "$OLD/dotfiles/gone" "$H/.gone"
ln -s /etc/hosts "$H/.foo"
ln -s "../../old/dotfiles/shell/zshrc" "$H/.relz"
echo x >"$H/.vimrc"
ln -s "$OLD/dotfiles/shell/zshrc" "$H/.config/zrc"

field() { # field <plan> <link> <n>
  printf '%s\n' "$1" | awk -F'\t' -v l="$2" -v n="$3" '$1==l{print $n}'
}

test_plan() {
  test_suite "migrate_plan maps links into the old folder"
  local plan
  plan="$(migrate_plan "$OLD")"
  assert_equals "repoint" "$(field "$plan" "$H/.zshrc" 4)" ".zshrc repoint"
  assert_equals "$H/.maclift/dotfiles/shell/zshrc" "$(field "$plan" "$H/.zshrc" 3)" ".zshrc new target"
  assert_equals "repoint" "$(field "$plan" "$H/.zsh" 4)" ".zsh folder repoint"
  assert_equals "$MACLIFT_HOME/.maclift/dotfiles/shell/zsh" "$(field "$plan" "$H/.zsh" 3)" ".zsh folder new target"
  assert_equals "unmapped" "$(field "$plan" "$H/.nv" 4)" ".nv unmapped"
  assert_equals "-" "$(field "$plan" "$H/.nv" 3)" ".nv new target is -"
  assert_contains "$(field "$plan" "$H/.inputrc" 2)" "/old/dotfiles/shell/inputrc" "relative link detected"
  assert_equals "unmapped" "$(field "$plan" "$H/.inputrc" 4)" ".inputrc unmapped (no maclift copy)"
  assert_equals "unmapped" "$(field "$plan" "$H/.gone" 4)" "dangling link detected"
  assert_equals "" "$(field "$plan" "$H/.vimrc" 1)" "regular file not listed"
  assert_equals "" "$(field "$plan" "$H/.foo" 1)" "link elsewhere not listed"
  assert_equals "repoint" "$(field "$plan" "$H/.config/zrc" 4)" ".config entry scanned"
  assert_equals "$(printf '%s\n' "$plan" | LC_ALL=C sort)" "$plan" "sorted by link"
}

test_override() {
  test_suite "migrate_plan uses the private layer override"
  mkdir -p "$MACLIFT_CONFIG_DIR/dotfiles"
  echo n >"$MACLIFT_CONFIG_DIR/dotfiles/nv"
  local plan
  plan="$(migrate_plan "$OLD")"
  assert_equals "repoint" "$(field "$plan" "$H/.nv" 4)" ".nv repoint"
  assert_equals "$MACLIFT_CONFIG_DIR/dotfiles/nv" "$(field "$plan" "$H/.nv" 3)" ".nv override target"
  rm -rf "$MACLIFT_CONFIG_DIR/dotfiles"
}

test_missing() {
  test_suite "migrate_plan with a missing old dir"
  assert_command_fails "migrate_plan '$T/nope'" "returns 1"
  assert_equals "" "$(migrate_plan "$T/nope" 2>/dev/null || true)" "prints nothing"
}

test_apply() {
  test_suite "migrate_apply dry-run changes nothing"
  local out before
  before="$(ls -l "$H" | sed 1d)"
  MACLIFT_RUN_ID=run1
  export MACLIFT_RUN_ID
  out="$(migrate_apply 1 "$OLD")"
  assert_contains "$out" "would repoint $H/.zshrc: $OLDR/dotfiles/shell/zshrc → $H/.maclift/dotfiles/shell/zshrc" "dry-run lists repoint"
  assert_contains "$out" "would link ~/.maclift → $MACLIFT_DIR" "dry-run lists .maclift link"
  assert_contains "$out" "left alone (no maclift copy): $H/.nv" "dry-run lists unmapped"
  assert_equals "$before" "$(ls -l "$H" | sed 1d)" "home unchanged"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/backups' ]" "no manifest folder"
  assert_command_fails "[ -e '$H/.maclift' ] || [ -L '$H/.maclift' ]" "no ~/.maclift"

  test_suite "migrate_apply real run"
  out="$(migrate_apply 0 "$OLD")"
  assert_contains "$out" "repointed $H/.zshrc" "prints repointed"
  assert_contains "$out" "4 repointed, 3 left alone" "summary counts"
  assert_equals "$H/.maclift/dotfiles/shell/zshrc" "$(readlink "$H/.zshrc")" ".zshrc repointed"
  assert_equals "mz" "$(cat "$H/.zshrc")" ".zshrc resolves to the maclift file"
  assert_equals "$(maclift_real_path "$MACLIFT_DIR/dotfiles/shell/zsh")" "$(maclift_real_path "$H/.zsh")" ".zsh resolves to the maclift folder"
  assert_equals "$H/.maclift/dotfiles/shell/zsh" "$(readlink "$H/.zsh")" ".zsh repointed"
  assert_command_succeeds "[ -L '$H/.zsh' ]" ".zsh still a symlink"
  assert_command_succeeds "[ -d '$MACLIFT_DIR/dotfiles/shell/zsh' ]" "maclift zsh folder present"
  assert_command_succeeds "[ -d '$OLD/dotfiles/shell/zsh' ] && [ ! -L '$OLD/dotfiles/shell/zsh' ]" "old folder intact"
  assert_equals "$MACLIFT_DIR" "$(readlink "$H/.maclift")" "maclift link -> MACLIFT_DIR"
  assert_equals "$OLD/dotfiles/shell/nv" "$(readlink "$H/.nv")" ".nv untouched"
  assert_equals "z" "$(cat "$OLD/dotfiles/shell/zshrc")" "old file contents unchanged"
  local m="$MACLIFT_CONFIG_DIR/backups/run1/migrate.tsv"
  assert_file_exists "$m" "manifest written"
  assert_equals "yes" "$(awk -F'\t' '$1=="#created-maclift-link"{print $2}' "$m")" "created-maclift-link yes"
  assert_equals "4" "$(grep -vc '^#' "$m" | tr -d ' ')" "one manifest line per repointed link"
  assert_equals "$H/.zshrc	$OLD/dotfiles/shell/zshrc	$H/.maclift/dotfiles/shell/zshrc" "$(grep "^$H/.zshrc	" "$m")" "manifest line format"
  assert_false "$(grep -F "$H/.nv" "$m" || true)" "unmapped not in manifest"
  assert_equals "$H/.relz	../../old/dotfiles/shell/zshrc	$H/.maclift/dotfiles/shell/zshrc" "$(grep "^$H/.relz	" "$m")" "manifest keeps relative link text exactly"
  assert_equals "$H/.maclift/dotfiles/shell/zshrc" "$(readlink "$H/.relz")" "relative link repointed"

  test_suite "migrate_apply second run"
  MACLIFT_RUN_ID=run2
  out="$(migrate_apply 0 "$OLD")"
  assert_equals "nothing to migrate" "$out" "second run prints nothing to migrate"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/backups/run2' ]" "no new manifest"

  test_suite "migrate_apply replaces a wrong ~/.maclift"
  mkdir -p "$T/other"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  ln -sfn "$OLD/dotfiles/shell/zsh" "$H/.zsh"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.config/zrc"
  ln -sfn "../../old/dotfiles/shell/zshrc" "$H/.relz"
  rm "$H/.maclift"
  ln -s "$T/other" "$H/.maclift"
  MACLIFT_RUN_ID=run3
  out="$(migrate_apply 0 "$OLD")"
  assert_equals "$MACLIFT_DIR" "$(readlink "$H/.maclift")" "maclift link replaced"
  assert_contains "$(cat "$MACLIFT_CONFIG_DIR/backups/run3/manifest.tsv")" "$H/.maclift" "old ~/.maclift backed up in manifest.tsv"
  assert_equals "yes" "$(awk -F'\t' '$1=="#created-maclift-link"{print $2}' "$MACLIFT_CONFIG_DIR/backups/run3/migrate.tsv")" "created yes when wrong"

  test_suite "migrate_apply writes the manifest before any change"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  ln -sfn "$OLD/dotfiles/shell/zsh" "$H/.zsh"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.config/zrc"
  ln -sfn "../../old/dotfiles/shell/zshrc" "$H/.relz"
  local before_links rc=0
  before_links="$(for l in .zshrc .zsh .config/zrc .relz; do readlink "$H/$l"; done)"
  eval 'dotfiles_link_repo() { return 1; }'
  MACLIFT_RUN_ID=run3b
  migrate_apply 0 "$OLD" >/dev/null 2>&1 || rc=$?
  # shellcheck source=lib/dotfiles.sh
  source "$PROJECT_ROOT/lib/dotfiles.sh"
  assert_equals "1" "$rc" "returns 1 when linking ~/.maclift fails"
  assert_file_exists "$MACLIFT_CONFIG_DIR/backups/run3b/migrate.tsv" "manifest exists"
  assert_equals "$before_links" "$(for l in .zshrc .zsh .config/zrc .relz; do readlink "$H/$l"; done)" "no link changed"

  test_suite "migrate_apply keeps created-maclift-link no when already correct"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  MACLIFT_RUN_ID=run4
  migrate_apply 0 "$OLD" >/dev/null
  assert_equals "no" "$(awk -F'\t' '$1=="#created-maclift-link"{print $2}' "$MACLIFT_CONFIG_DIR/backups/run4/migrate.tsv")" "created no when already correct"
  assert_equals "$H/.maclift/dotfiles/shell/zshrc" "$(readlink "$H/.zshrc")" ".zshrc repointed again"
}

_rb_reset() { # fresh links + no backups, like a never-migrated home
  rm -rf "$MACLIFT_CONFIG_DIR/backups"
  rm -f "$H/.maclift"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  ln -sfn "$OLD/dotfiles/shell/zsh" "$H/.zsh"
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.config/zrc"
  ln -sfn "../../old/dotfiles/shell/zshrc" "$H/.relz"
}
_rb_snap() { for l in .zshrc .zsh .nv .config/zrc .relz .inputrc; do printf '%s=%s\n' "$l" "$(readlink "$H/$l")"; done; }

test_rollback() {
  local before out rc
  test_suite "migrate_rollback restores exactly"
  _rb_reset
  before="$(_rb_snap)"
  MACLIFT_RUN_ID=rb1
  migrate_apply 0 "$OLD" >/dev/null
  assert_command_succeeds "[ -L '$H/.maclift' ]" "migrated: ~/.maclift exists"
  out="$(migrate_rollback 0)"
  assert_equals "$before" "$(_rb_snap)" "links byte-identical (incl. relative)"
  assert_command_fails "[ -e '$H/.maclift' ] || [ -L '$H/.maclift' ]" "no ~/.maclift"
  assert_contains "$out" "restored $H/.zshrc" "prints restored"
  assert_command_succeeds "[ -f '$MACLIFT_CONFIG_DIR/backups/rb1/migrate.rolled-back.tsv' ]" "manifest renamed"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/backups/rb1/migrate.tsv' ]" "old manifest gone"

  test_suite "migrate_rollback second run"
  rc=0
  out="$(migrate_rollback 0)" || rc=$?
  assert_equals "nothing to roll back" "$out" "second rollback message"
  assert_equals "1" "$rc" "second rollback returns 1"

  test_suite "migrate_rollback dry-run changes nothing"
  _rb_reset
  MACLIFT_RUN_ID=rb2
  migrate_apply 0 "$OLD" >/dev/null
  before="$(_rb_snap)"
  out="$(migrate_rollback 1)"
  assert_contains "$out" "would restore $H/.zshrc" "dry-run lists restores"
  assert_equals "$before" "$(_rb_snap)" "links unchanged"
  assert_command_succeeds "[ -L '$H/.maclift' ]" "the maclift link kept"
  assert_command_succeeds "[ -f '$MACLIFT_CONFIG_DIR/backups/rb2/migrate.tsv' ]" "manifest kept"

  test_suite "migrate_rollback skips links changed since migration"
  ln -sfn /etc/hosts "$H/.zshrc"
  out="$(migrate_rollback 0)"
  assert_contains "$out" "skipped $H/.zshrc (changed since migration)" "skip message"
  assert_equals "/etc/hosts" "$(readlink "$H/.zshrc")" "changed link left alone"
  assert_equals "$OLD/dotfiles/shell/zsh" "$(readlink "$H/.zsh")" ".zsh restored"
  assert_equals "../../old/dotfiles/shell/zshrc" "$(readlink "$H/.relz")" ".relz restored"

  test_suite "migrate_rollback restores a pre-existing ~/.maclift"
  _rb_reset
  ln -s "$T/other" "$H/.maclift"
  before="$(_rb_snap)"
  MACLIFT_RUN_ID=rb3
  migrate_apply 0 "$OLD" >/dev/null
  assert_equals "$MACLIFT_DIR" "$(readlink "$H/.maclift")" "migrated: ~/.maclift replaced"
  migrate_rollback 0 >/dev/null
  assert_equals "$T/other" "$(readlink "$H/.maclift")" "original ~/.maclift target restored"
  assert_equals "$before" "$(_rb_snap)" "links restored"
  rm -f "$H/.maclift"

  test_suite "migrate_rollback dry-run previews restoring a pre-existing ~/.maclift"
  _rb_reset
  ln -s "$T/other" "$H/.maclift"
  MACLIFT_RUN_ID=rb3b
  migrate_apply 0 "$OLD" >/dev/null
  out="$(migrate_rollback 1)"
  assert_contains "$out" "would remove ~/.maclift" "preview lists the removal"
  assert_contains "$out" "would restore ~/.maclift from" "preview lists the restore"
  assert_equals "$MACLIFT_DIR" "$(readlink "$H/.maclift")" "dry-run left ~/.maclift alone"
  migrate_rollback 0 >/dev/null
  rm -f "$H/.maclift"

  test_suite "migrate_rollback reports links that are already restored"
  _rb_reset
  MACLIFT_RUN_ID=rb3c
  migrate_apply 0 "$OLD" >/dev/null
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  out="$(migrate_rollback 0)"
  assert_contains "$out" "already restored $H/.zshrc" "already-restored message"
  assert_false "$(printf '%s\n' "$out" | grep "skipped $H/.zshrc" || true)" "not reported as skipped"
  assert_equals "$OLD/dotfiles/shell/zshrc" "$(readlink "$H/.zshrc")" "link still correct"

  test_suite "migrate_rollback keeps a ~/.maclift it did not create"
  _rb_reset
  ln -s "$T/other" "$H/.maclift"
  MACLIFT_RUN_ID=rb4
  eval 'dotfiles_link_repo() { return 1; }'
  migrate_apply 0 "$OLD" >/dev/null 2>&1 || true
  # shellcheck source=lib/dotfiles.sh
  source "$PROJECT_ROOT/lib/dotfiles.sh"
  out="$(migrate_rollback 0)"
  assert_equals "$T/other" "$(readlink "$H/.maclift")" "foreign ~/.maclift untouched"
  rm -f "$H/.maclift"

  test_suite "migrate_rollback picks newest manifest and honours run-id"
  _rb_reset
  MACLIFT_RUN_ID=2026-01-01_000000
  migrate_apply 0 "$OLD" >/dev/null
  ln -sfn "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  MACLIFT_RUN_ID=2026-02-01_000000
  migrate_apply 0 "$OLD" >/dev/null
  out="$(migrate_rollback 0)"
  assert_command_succeeds "[ -f '$MACLIFT_CONFIG_DIR/backups/2026-02-01_000000/migrate.rolled-back.tsv' ]" "newest picked"
  assert_command_succeeds "[ -f '$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/migrate.tsv' ]" "older untouched"
  out="$(migrate_rollback 0 2026-01-01_000000)"
  assert_command_succeeds "[ -f '$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/migrate.rolled-back.tsv' ]" "run-id selects that folder"
  assert_command_fails "migrate_rollback 0 no-such-run >/dev/null" "unknown run-id returns 1"
}

test_plan
test_apply
test_rollback
test_override
test_missing
test_summary
