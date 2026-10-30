#!/usr/bin/env bash
#
# Unit tests for lib/restore.sh
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
# shellcheck source=lib/restore.sh
source "$PROJECT_ROOT/lib/restore.sh"

export MACLIFT_DIR="$PROJECT_ROOT" MACLIFT_PLAIN=1
unset MACLIFT_ASSUME_YES

# Fresh temp home; MACLIFT_RUN_ID is the "current" run.
fresh() {
  MACLIFT_HOME="$(mktemp -d)"
  export MACLIFT_HOME
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
  MACLIFT_RUN_ID="2026-03-01_000000"
  export MACLIFT_RUN_ID
}

# Makes a past run: backs up a .zshrc ("old") and replaces it with a symlink.
make_run() {
  local saved="$MACLIFT_RUN_ID"
  MACLIFT_RUN_ID="$1"
  rm -f "$MACLIFT_HOME/.zshrc"
  printf 'old' >"$MACLIFT_HOME/.zshrc"
  backup_path "$MACLIFT_HOME/.zshrc" >/dev/null
  ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  MACLIFT_RUN_ID="$saved"
}

test_restore_run() {
  test_suite "restore_run"
  fresh
  make_run 2026-01-01_000000
  local out
  out="$(restore_run 0 2026-01-01_000000 2>&1)"
  assert_contains "$out" "restored $MACLIFT_HOME/.zshrc" "says restored"
  assert_command_fails "[ -L '$MACLIFT_HOME/.zshrc' ]" ".zshrc is no longer a symlink"
  assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "content is back"
  assert_file_exists "$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/.zshrc" "old backup stays"
  assert_command_succeeds "[ -L '$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID/.zshrc' ]" "symlink moved into this run"
  out="$(restore_run 0 2026-01-01_000000 2>&1)"
  assert_contains "$out" "ok $MACLIFT_HOME/.zshrc" "second time: ok"
  assert_equals "1" "$(grep -c . "$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID/manifest.tsv")" "no second move"
}

test_restore_unknown() {
  test_suite "restore_run unknown run"
  fresh
  local out rc=0
  out="$(restore_run 0 nope 2>&1)" || rc=$?
  assert_equals "1" "$rc" "returns 1"
  assert_contains "$out" "no backup run nope" "says so"
}

test_restore_outside_and_missing() {
  test_suite "restore_run outside home and missing backup"
  fresh
  make_run 2026-01-01_000000
  local m="$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/manifest.tsv" some out rc=0 hosts_before
  some="$(mktemp)"
  hosts_before="$(cat /etc/hosts)"
  printf '/etc/hosts\t%s\n' "$some" >>"$m"
  printf '%s/.gone\t%s/no-such-file\n' "$MACLIFT_HOME" "$MACLIFT_CONFIG_DIR" >>"$m"
  out="$(restore_run 0 2026-01-01_000000 2>&1)" || rc=$?
  assert_equals "1" "$rc" "returns 1"
  assert_contains "$out" "✗ /etc/hosts: outside the home folder" "outside skipped"
  assert_equals "$hosts_before" "$(cat /etc/hosts)" "/etc/hosts untouched"
  assert_contains "$out" "✗ $MACLIFT_HOME/.gone: backup $MACLIFT_CONFIG_DIR/no-such-file is missing" "missing backup"
  assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "other entry still restored"
  rm -f "$some"
}

test_restore_spaces() {
  test_suite "restore_run paths with spaces"
  fresh
  MACLIFT_RUN_ID=2026-01-01_000000
  mkdir -p "$MACLIFT_HOME/My Dir"
  printf 'x' >"$MACLIFT_HOME/My Dir/a b"
  backup_path "$MACLIFT_HOME/My Dir/a b" >/dev/null
  MACLIFT_RUN_ID=2026-03-01_000000
  restore_run 0 2026-01-01_000000 >/dev/null 2>&1
  assert_equals "x" "$(cat "$MACLIFT_HOME/My Dir/a b")" "restored"
}

test_restore_runs() {
  test_suite "restore_runs"
  fresh
  make_run 2026-01-01_000000
  make_run 2026-02-01_000000
  mkdir -p "$MACLIFT_CONFIG_DIR/backups/2026-02-15_000000"
  make_run "$MACLIFT_RUN_ID"
  assert_equals "$(printf '2026-02-01_000000\t1\n2026-01-01_000000\t1')" "$(restore_runs)" "newest first, no current, no empty"
}

test_restore_dry() {
  test_suite "restore_run dry run"
  fresh
  make_run 2026-01-01_000000
  local before after out
  before="$(find "$MACLIFT_HOME" | LC_ALL=C sort; readlink "$MACLIFT_HOME/.zshrc")"
  out="$(restore_run 1 2026-01-01_000000 2>&1)"
  after="$(find "$MACLIFT_HOME" | LC_ALL=C sort; readlink "$MACLIFT_HOME/.zshrc")"
  assert_contains "$out" "would restore $MACLIFT_HOME/.zshrc from" "says would restore"
  assert_equals "$before" "$after" "nothing changed"
}

test_restore_runs_none() {
  test_suite "cmd_restore without backups"
  fresh
  assert_contains "$(cmd_restore 0 2>&1)" "No backups in" "says none"
}

test_restore_bad_originals() {
  test_suite "restore_run rejects relative and dot-segment originals"
  fresh
  make_run 2026-01-01_000000
  local m="$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/manifest.tsv" bk="$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/.zshrc" o out rc
  for o in "$MACLIFT_HOME/." "$MACLIFT_HOME/a/../b" "$MACLIFT_HOME/./x" "$MACLIFT_HOME/x/." "$MACLIFT_HOME/.." "relative.txt" "./foo" "$MACLIFT_HOME"; do
    cp "$m" "$m.orig"
    printf '%s\t%s\n' "$o" "$bk" >>"$m"
    rm -f "$MACLIFT_HOME/.zshrc"; ln -s /nowhere "$MACLIFT_HOME/.zshrc"
    rc=0; out="$(restore_run 0 2026-01-01_000000 2>&1)" || rc=$?
    assert_equals "1" "$rc" "returns 1 for $o"
    assert_contains "$out" "✗ $o: outside the home folder" "skipped $o"
    assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "other entry restored ($o)"
    assert_equals "1" "$(find "$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID" -type l | grep -c .)" "only the .zshrc symlink moved ($o)"
    rm -rf "$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID"
    mv "$m.orig" "$m"
  done
  for o in .. a/b; do
    rc=0; out="$(restore_run 0 "$o" 2>&1)" || rc=$?
    assert_equals "1" "$rc" "run id $o returns 1"
    assert_contains "$out" "no backup run $o" "run id $o rejected"
  done
}

test_restore_first_line_wins() {
  test_suite "restore_run puts back the first backup of a path"
  fresh
  local saved="$MACLIFT_RUN_ID" out
  MACLIFT_RUN_ID=2026-01-01_000000
  printf 'A' >"$MACLIFT_HOME/.zshrc"
  backup_path "$MACLIFT_HOME/.zshrc" >/dev/null
  printf 'B' >"$MACLIFT_HOME/.zshrc"
  backup_path "$MACLIFT_HOME/.zshrc" >/dev/null
  ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  MACLIFT_RUN_ID="$saved"
  assert_equals "2" "$(grep -c . "$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/manifest.tsv")" "two manifest lines"
  out="$(printf 'n\n' | cmd_restore 0 2026-01-01_000000 2>&1)"
  assert_contains "$out" "Restore 1 files from 2026-01-01_000000?" "prompt counts one file"
  out="$(restore_run 0 2026-01-01_000000 2>&1)"
  assert_equals "A" "$(cat "$MACLIFT_HOME/.zshrc")" "the original A is back"
  assert_equals "1" "$(grep -c "restored" <<<"$out")" "restored once"
  out="$(restore_run 0 2026-01-01_000000 2>&1)"
  assert_contains "$out" "ok $MACLIFT_HOME/.zshrc" "second time: ok"
}

test_restore_folder_identical() {
  test_suite "restore_run of an identical folder is a no-op"
  fresh
  local saved="$MACLIFT_RUN_ID" out
  MACLIFT_RUN_ID=2026-01-01_000000
  mkdir -p "$MACLIFT_HOME/.config/app"
  printf 'x' >"$MACLIFT_HOME/.config/app/a"
  backup_path "$MACLIFT_HOME/.config/app" >/dev/null
  MACLIFT_RUN_ID="$saved"
  restore_run 0 2026-01-01_000000 >/dev/null 2>&1
  out="$(restore_run 0 2026-01-01_000000 2>&1)"
  assert_contains "$out" "ok $MACLIFT_HOME/.config/app" "second time: ok"
  assert_command_fails "[ -e '$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID' ]" "nothing moved aside"
}

test_restore_migration_run() {
  test_suite "restore_run on a migration run"
  fresh
  local out rc=0
  mkdir -p "$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000"
  printf 'x\ty\n' >"$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000/migrate.tsv"
  out="$(restore_run 0 2026-01-01_000000 2>&1)" || rc=$?
  assert_equals "1" "$rc" "returns 1"
  assert_contains "$out" "2026-01-01_000000 is a migration, not a dotfile backup; undo it with: maclift migrate --rollback --run 2026-01-01_000000" "points to migrate --rollback"
}

test_restore_backup_outside_backups() {
  test_suite "restore_run only copies from inside backups/"
  fresh
  make_run 2026-01-01_000000
  local run="$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000" m elsewhere out rc=0 b
  m="$run/manifest.tsv"
  elsewhere="$(mktemp -d)"
  printf 'secret' >"$elsewhere/f"
  printf 'secret' >"$MACLIFT_CONFIG_DIR/f"
  # A folder link inside the run that leads out of backups/.
  ln -s "$elsewhere" "$run/sneaky"
  for b in "$elsewhere/f" "$MACLIFT_CONFIG_DIR/f" "$run/sneaky/f" "$run/../../f"; do
    printf '%s/.stolen\t%s\n' "$MACLIFT_HOME" "$b" >>"$m"
    rc=0; out="$(restore_run 0 2026-01-01_000000 2>&1)" || rc=$?
    assert_equals "1" "$rc" "returns 1 for $b"
    assert_contains "$out" "✗ $MACLIFT_HOME/.stolen: backup $b is not inside $MACLIFT_CONFIG_DIR/backups" "skipped $b"
    assert_command_fails "[ -e '$MACLIFT_HOME/.stolen' ]" "nothing copied from $b"
    assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "other entry restored ($b)"
    assert_equals "0" "$(_restore_count "$m")" "not counted ($b)"
    # Back to the state before this entry.
    grep -v stolen "$m" >"$m.tmp"; mv "$m.tmp" "$m"
    rm -rf "$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID"
    rm -f "$MACLIFT_HOME/.zshrc"; ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  done
  rm -rf "$elsewhere"
}

test_restore_picker() {
  test_suite "cmd_restore: pick a run and confirm (plain menu)"
  fresh
  make_run 2026-01-01_000000
  make_run 2026-02-01_000000
  # 2026-01-01 also backed up a file that is identical to what is there now.
  local run="$MACLIFT_CONFIG_DIR/backups/2026-01-01_000000" out rc=0
  printf 'same' >"$run/.same"
  printf 'same' >"$MACLIFT_HOME/.same"
  printf '%s/.same\t%s/.same\n' "$MACLIFT_HOME" "$run" >>"$run/manifest.tsv"
  rm -f "$MACLIFT_HOME/.zshrc"; ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  out="$(printf '2\ny\n' | cmd_restore 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit 0"
  assert_contains "$out" "1) 2026-02-01_000000 (1 files, 1 to restore)" "newest run listed first"
  assert_contains "$out" "2) 2026-01-01_000000 (2 files, 1 to restore)" "label counts what will be restored"
  assert_contains "$out" "Restore 1 files from 2026-01-01_000000?" "prompt uses the same count"
  assert_contains "$out" "restored $MACLIFT_HOME/.zshrc" "restored"
  assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "content is back"
  rm -f "$MACLIFT_HOME/.zshrc"; ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  out="$(printf '1\nn\n' | cmd_restore 0 2>&1)"
  assert_contains "$out" "Nothing restored." "answering no restores nothing"
  assert_command_succeeds "[ -L '$MACLIFT_HOME/.zshrc' ]" "still the symlink"
}

test_restore_directory() {
  test_suite "restore_run puts back a backed-up folder"
  fresh
  local saved="$MACLIFT_RUN_ID"
  MACLIFT_RUN_ID=2026-01-01_000000
  mkdir -p "$MACLIFT_HOME/.config/app/sub"
  printf 'a' >"$MACLIFT_HOME/.config/app/a"
  printf 'b' >"$MACLIFT_HOME/.config/app/sub/b"
  backup_path "$MACLIFT_HOME/.config/app" >/dev/null
  ln -s /nowhere "$MACLIFT_HOME/.config/app"
  MACLIFT_RUN_ID="$saved"
  restore_run 0 2026-01-01_000000 >/dev/null 2>&1
  assert_command_succeeds "[ -d '$MACLIFT_HOME/.config/app' ] && [ ! -L '$MACLIFT_HOME/.config/app' ]" "a real folder again"
  assert_equals "a" "$(cat "$MACLIFT_HOME/.config/app/a")" "top file back"
  assert_equals "b" "$(cat "$MACLIFT_HOME/.config/app/sub/b")" "nested file back"
  assert_command_succeeds "[ -L '$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID/.config/app' ]" "the link was moved aside"
}

test_restore_run
test_restore_backup_outside_backups
test_restore_picker
test_restore_directory
test_restore_first_line_wins
test_restore_folder_identical
test_restore_migration_run
test_restore_bad_originals
test_restore_unknown
test_restore_outside_and_missing
test_restore_spaces
test_restore_runs
test_restore_dry
test_restore_runs_none
test_summary
