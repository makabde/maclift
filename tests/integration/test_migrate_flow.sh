#!/usr/bin/env bash
#
# Integration tests for `maclift migrate`: a sandbox home with a fake old
# dotfiles repo, and the real repo as MACLIFT_DIR. Never touches the real home.
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACLIFT="$PROJECT_ROOT/maclift"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"

setup_env() {
  T="$(mktemp -d)"
  H="$T/home"
  OLD="$T/old"
  mkdir -p "$H" "$T/realhome" "$OLD/dotfiles/shell/zsh" "$OLD/dotfiles/git"
  echo "# old zshrc" >"$OLD/dotfiles/shell/zshrc"
  echo "# old gitconfig" >"$OLD/dotfiles/git/gitconfig"
  ln -s "$OLD/dotfiles/shell/zshrc" "$H/.zshrc"
  ln -s "$OLD/dotfiles/shell/zsh" "$H/.zsh"
  ln -s "$OLD/dotfiles/git/gitconfig" "$H/.gitconfig"
  export MACLIFT_HOME="$H" HOME="$T/realhome" MACLIFT_PLAIN=1
  unset MACLIFT_DIR MACLIFT_RUN_ID MACLIFT_LOG MACLIFT_ASSUME_YES MACLIFT_ASSUME_TTY
}

links() {
  local l
  for l in .zshrc .zsh .gitconfig .maclift; do printf '%s=%s\n' "$l" "$(readlink "$H/$l" || true)"; done
}

run() { RC=0; OUT="$("$@" 2>&1 </dev/null)" || RC=$?; }

test_dry_run() {
  test_suite "migrate --dry-run shows the plan and changes nothing"
  setup_env
  local before
  before="$(links)"
  run "$MACLIFT" migrate --from "$OLD" --dry-run
  assert_equals "0" "$RC" "exit 0"
  assert_contains "$OUT" "would repoint $H/.zshrc" "prints would repoint"
  assert_equals "$before" "$(links)" "links unchanged"
  assert_false "$(ls "$H/.config/maclift/backups" 2>/dev/null || true)" "no manifest written"
}

test_apply_and_rollback() {
  test_suite "migrate repoints with -y, is idempotent, and rolls back"
  setup_env
  local before
  before="$(links)"
  run "$MACLIFT" -y migrate --from "$OLD"
  assert_equals "0" "$RC" "exit 0"
  assert_contains "$OUT" "repointed $H/.zshrc" "prints repointed"
  assert_equals "$H/.maclift/dotfiles/shell/zshrc" "$(readlink "$H/.zshrc")" ".zshrc repointed"
  assert_equals "$PROJECT_ROOT" "$(readlink "$H/.maclift")" "the maclift link points at the repo"

  run "$MACLIFT" migrate --from "$OLD" -y
  assert_equals "0" "$RC" "re-run exit 0"
  assert_contains "$OUT" "nothing to migrate" "re-run reports nothing to migrate"

  run "$MACLIFT" migrate --rollback -y
  assert_equals "0" "$RC" "rollback exit 0"
  assert_contains "$OUT" "restored $H/.zshrc" "rollback prints restored"
  assert_equals "$before" "$(links)" "links restored byte-identically"

  run "$MACLIFT" migrate --rollback -y
  assert_equals "1" "$RC" "second rollback exits 1"
  assert_contains "$OUT" "nothing to roll back" "second rollback message"
}

test_confirm() {
  test_suite "migrate asks before a real apply"
  setup_env
  local before
  before="$(links)"
  RC=0
  OUT="$(printf 'n\n' | "$MACLIFT" migrate --from "$OLD" 2>&1)" || RC=$?
  assert_contains "$OUT" "Repoint 3 links?" "asks with the link count"
  assert_equals "$before" "$(links)" "declining changes nothing"
  RC=0
  OUT="$(printf 'y\n' | "$MACLIFT" migrate --from "$OLD" 2>&1)" || RC=$?
  assert_equals "0" "$RC" "accepting exits 0"
  assert_equals "$H/.maclift/dotfiles/shell/zshrc" "$(readlink "$H/.zshrc")" "accepting repoints"
}

test_usage() {
  test_suite "migrate usage errors and the guard"
  setup_env
  run "$MACLIFT" migrate --from "$T/missing"
  assert_equals "64" "$RC" "missing --from dir exits 64"
  assert_contains "$OUT" "maclift migrate: --from $T/missing: not a directory" "exact message"
  run "$MACLIFT" migrate --from "$OLD/dotfiles/shell/zshrc"
  assert_equals "64" "$RC" "a file as --from exits 64"
  run "$MACLIFT" migrate
  assert_equals "64" "$RC" "no --from and no --rollback exits 64"
  run "$MACLIFT" --rollback
  assert_equals "64" "$RC" "--rollback without migrate exits 64"

  RC=0
  mkdir -p "$T/devdir"
  printf '0.9.0\n' >"$T/devdir/VERSION"
  OUT="$(env -u MACLIFT_HOME MACLIFT_DIR="$T/devdir" HOME="$H" "$MACLIFT" migrate --from "$OLD" 2>&1 </dev/null)" || RC=$?
  assert_equals "2" "$RC" "real home without --for-real exits 2"
  assert_contains "$OUT" "pass --for-real" "guard message"
  assert_equals "$OLD/dotfiles/shell/zshrc" "$(readlink "$H/.zshrc")" "guard changed nothing"
  RC=0
  OUT="$(env -u MACLIFT_HOME HOME="$H" "$MACLIFT" migrate --from "$OLD" --dry-run 2>&1 </dev/null)" || RC=$?
  assert_equals "0" "$RC" "real home dry-run is allowed"

  run "$MACLIFT" --help
  assert_contains "$OUT" "maclift migrate --from" "help documents migrate"
  assert_contains "$OUT" "migrate --rollback" "help documents --rollback"
}

test_rollback_regular_files() {
  test_suite "rollback never touches a regular file or folder at a link path"
  setup_env
  run "$MACLIFT" -y migrate --from "$OLD"
  rm "$H/.zshrc"
  echo "my own content" >"$H/.zshrc"
  rm "$H/.zsh"
  mkdir "$H/.zsh"
  echo "keep" >"$H/.zsh/file"
  run "$MACLIFT" migrate --rollback -y
  assert_contains "$OUT" "skipped $H/.zshrc (changed since migration)" "file reported as skipped"
  assert_contains "$OUT" "skipped $H/.zsh (changed since migration)" "folder reported as skipped"
  assert_equals "my own content" "$(cat "$H/.zshrc")" "file content intact"
  assert_equals "keep" "$(cat "$H/.zsh/file")" "folder content intact"
  assert_equals "$OLD/dotfiles/git/gitconfig" "$(readlink "$H/.gitconfig")" "other link restored"
}

test_dry_run
test_apply_and_rollback
test_confirm
test_usage
test_rollback_regular_files
test_summary
