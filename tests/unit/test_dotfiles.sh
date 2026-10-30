#!/usr/bin/env bash
#
# Unit tests for lib/dotfiles.sh
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
# shellcheck source=lib/dotfiles.sh
source "$PROJECT_ROOT/lib/dotfiles.sh"

export MACLIFT_DIR="$PROJECT_ROOT"

fresh_home() {
  MACLIFT_HOME="$(mktemp -d)"
  export MACLIFT_HOME
  unset MACLIFT_RUN_ID
  maclift_init_paths
}

test_linked_via_maclift_link() {
  test_suite "a link through the .maclift link counts as linked"
  fresh_home
  ln -s "$MACLIFT_DIR" "$MACLIFT_HOME/.maclift"
  ln -s "$MACLIFT_HOME/.maclift/dotfiles/shell/zshrc" "$MACLIFT_HOME/.zshrc"
  assert_command_succeeds "_dotfiles_is_linked '$MACLIFT_DIR/dotfiles/shell/zshrc' '$MACLIFT_HOME/.zshrc'" "path through .maclift accepted"
  local before out
  before="$(readlink "$MACLIFT_HOME/.zshrc")"
  out="$(_dotfiles_link_one "$MACLIFT_DIR/dotfiles/shell/zshrc" "$MACLIFT_HOME/.zshrc" 0)"
  assert_equals "$before" "$(readlink "$MACLIFT_HOME/.zshrc")" "link left as it is"
  assert_command_fails "[ -d '$MACLIFT_CONFIG_DIR/backups' ]" "nothing backed up"
  ln -s ../elsewhere "$MACLIFT_HOME/.other"
  assert_command_fails "_dotfiles_is_linked '$MACLIFT_DIR/dotfiles/shell/zshrc' '$MACLIFT_HOME/.other'" "a link elsewhere is not linked"
  assert_command_fails "_dotfiles_is_linked '$MACLIFT_DIR/dotfiles/shell/zshrc' '$MACLIFT_HOME/.nothere'" "a missing link is not linked"
  : "$out"
}

test_link_repo() {
  test_suite "dotfiles_link_repo links ~/.maclift to the clone"
  fresh_home
  local out
  out="$(dotfiles_link_repo 1)"
  assert_contains "$out" "would link $MACLIFT_HOME/.maclift" "dry-run prints would link"
  assert_command_fails "[ -e '$MACLIFT_HOME/.maclift' ] || [ -L '$MACLIFT_HOME/.maclift' ]" "dry-run creates nothing"
  echo old >"$MACLIFT_HOME/.maclift"
  dotfiles_link_repo 0 >/dev/null
  assert_equals "$MACLIFT_DIR" "$(readlink "$MACLIFT_HOME/.maclift")" "links to MACLIFT_DIR"
  assert_command_succeeds "grep -rqx old '$MACLIFT_CONFIG_DIR/backups'" "old file backed up"
  assert_equals "skip" "$(dotfiles_link_repo 0)" "correct link is skipped"

  test_suite "dotfiles_link_repo leaves a clone at ~/.maclift alone"
  fresh_home
  local saved="$MACLIFT_DIR"
  mkdir -p "$MACLIFT_HOME/.maclift"
  MACLIFT_DIR="$MACLIFT_HOME/.maclift"
  assert_equals "skip" "$(dotfiles_link_repo 0)" "skips"
  assert_command_succeeds "[ -d '$MACLIFT_HOME/.maclift' ] && [ ! -L '$MACLIFT_HOME/.maclift' ]" "clone untouched"
  MACLIFT_DIR="$saved"
}

test_backup_regular() {
  test_suite "dotfiles backup regular file"
  fresh_home
  echo old >"$MACLIFT_HOME/.zshrc"
  local out
  out="$(dotfiles_link_item dotfiles:zsh 0)"
  assert_contains "$out" "ok" "prints ok"
  assert_equals "$MACLIFT_DIR/dotfiles/shell/zshrc" "$(readlink "$MACLIFT_HOME/.zshrc")" "link points at repo"
  local b
  b="$(find "$MACLIFT_CONFIG_DIR/backups" -name .zshrc | head -n1)"
  assert_equals "old" "$(cat "$b")" "backup keeps content"
  local m
  m="$(find "$MACLIFT_CONFIG_DIR/backups" -name manifest.tsv | head -n1)"
  assert_equals "1" "$(wc -l <"$m" | tr -d ' ')" "manifest has one row"
  assert_contains "$(cat "$m")" "$MACLIFT_HOME/.zshrc" "manifest names original"
}

test_backup_symlink() {
  test_suite "dotfiles backup symlink"
  fresh_home
  ln -s /etc/hosts "$MACLIFT_HOME/.zshrc"
  dotfiles_link_item dotfiles:zsh 0 >/dev/null
  local b
  b="$(find "$MACLIFT_CONFIG_DIR/backups" -name .zshrc | head -n1)"
  assert_command_succeeds "[ -L '$b' ]" "backup is a symlink"
  assert_equals "/etc/hosts" "$(readlink "$b")" "still points at /etc/hosts"
}

test_backup_dir() {
  test_suite "dotfiles backup folder"
  fresh_home
  mkdir -p "$MACLIFT_HOME/.config/nvim"
  echo x >"$MACLIFT_HOME/.config/nvim/init.vim"
  dotfiles_link_item dotfiles:nvim 0 >/dev/null
  assert_equals "$MACLIFT_DIR/dotfiles/nvim" "$(readlink "$MACLIFT_HOME/.config/nvim")" "nvim linked"
  local nb
  nb="$(find "$MACLIFT_CONFIG_DIR/backups" -path '*/.config/nvim/init.vim' | head -n1)"
  assert_command_succeeds "[ -f '$nb' ]" "folder backed up whole"
}

test_idempotent() {
  test_suite "dotfiles idempotent"
  fresh_home
  echo old >"$MACLIFT_HOME/.zshrc"
  dotfiles_link_item dotfiles:zsh 0 >/dev/null
  local out n1 n2
  n1="$(ls "$MACLIFT_CONFIG_DIR/backups" | wc -l)"
  MACLIFT_RUN_ID="later"
  out="$(dotfiles_link_item dotfiles:zsh 0)"
  n2="$(ls "$MACLIFT_CONFIG_DIR/backups" | wc -l)"
  assert_contains "$out" "skip" "second run skips"
  assert_equals "$n1" "$n2" "no new backup folder"
  assert_command_succeeds "dotfiles_item_linked dotfiles:zsh" "item reports linked"
}

test_dry_run() {
  test_suite "dotfiles dry-run"
  fresh_home
  local out
  out="$(dotfiles_link_item dotfiles:git 1)"
  assert_contains "$out" "would link" "prints would link"
  assert_command_fails "[ -e '$MACLIFT_HOME/.gitconfig' ] || [ -L '$MACLIFT_HOME/.gitconfig' ]" "nothing created"
  assert_command_fails "[ -d '$MACLIFT_CONFIG_DIR' ]" "no config dir created"
  echo old >"$MACLIFT_HOME/.gitconfig"
  out="$(dotfiles_link_item dotfiles:git 1)"
  assert_contains "$out" "would back up" "prints would back up"
  assert_equals "old" "$(cat "$MACLIFT_HOME/.gitconfig")" "file untouched"
}

test_override() {
  test_suite "dotfiles user override"
  fresh_home
  mkdir -p "$MACLIFT_CONFIG_DIR/dotfiles"
  echo mine >"$MACLIFT_CONFIG_DIR/dotfiles/zshrc"
  dotfiles_link_item dotfiles:zsh 0 >/dev/null
  assert_equals "$MACLIFT_CONFIG_DIR/dotfiles/zshrc" "$(readlink "$MACLIFT_HOME/.zshrc")" "override wins"
  assert_equals "$MACLIFT_DIR/dotfiles/shell/zprofile" "$(readlink "$MACLIFT_HOME/.zprofile")" "others use repo"
}

test_dangling() {
  test_suite "dotfiles backup dangling symlink"
  fresh_home
  ln -s /nonexistent/nowhere "$MACLIFT_HOME/.zshrc"
  dotfiles_link_item dotfiles:zsh 0 >/dev/null
  local b
  b="$(find "$MACLIFT_CONFIG_DIR/backups" -name .zshrc | head -n1)"
  assert_command_succeeds "[ -L '$b' ]" "dangling link backed up as symlink"
  assert_equals "/nonexistent/nowhere" "$(readlink "$b")" "target preserved"
  assert_equals "$MACLIFT_DIR/dotfiles/shell/zshrc" "$(readlink "$MACLIFT_HOME/.zshrc")" "relinked"
}

test_user_only() {
  test_suite "dotfiles_link_user"
  fresh_home
  mkdir -p "$MACLIFT_CONFIG_DIR/dotfiles"
  echo mine >"$MACLIFT_CONFIG_DIR/dotfiles/npmrc"
  echo mine >"$MACLIFT_CONFIG_DIR/dotfiles/zshrc"
  local out
  out="$(dotfiles_link_user 1 dotfiles:zsh)"
  assert_contains "$out" "would link $MACLIFT_HOME/.npmrc" "dry-run reports npmrc"
  assert_command_fails "[ -L '$MACLIFT_HOME/.npmrc' ]" "dry-run links nothing"
  dotfiles_link_user 0 dotfiles:zsh >/dev/null
  assert_equals "$MACLIFT_CONFIG_DIR/dotfiles/npmrc" "$(readlink "$MACLIFT_HOME/.npmrc")" "npmrc linked"
  assert_command_fails "[ -L '$MACLIFT_HOME/.zshrc' ]" "repo-covered zshrc left to item"
  assert_equals "skip" "$(dotfiles_link_user 0 dotfiles:zsh)" "re-run skips"
}

test_user_unselected() {
  test_suite "dotfiles_link_user with deselected item"
  fresh_home
  mkdir -p "$MACLIFT_CONFIG_DIR/dotfiles"
  echo mine >"$MACLIFT_CONFIG_DIR/dotfiles/zshrc"
  dotfiles_link_user 0 dotfiles:git >/dev/null
  assert_equals "$MACLIFT_CONFIG_DIR/dotfiles/zshrc" "$(readlink "$MACLIFT_HOME/.zshrc")" "zshrc linked when zsh not selected"
}

test_one_run_folder() {
  test_suite "dotfiles one backup folder per run"
  fresh_home
  local stub; stub="$(mktemp -d)"
  cat >"$stub/date" <<'STUB'
#!/usr/bin/env bash
echo "stamp-$(cat "$STUB_COUNTER" 2>/dev/null || echo 0)"
echo $(( $(cat "$STUB_COUNTER" 2>/dev/null || echo 0) + 1 )) >"$STUB_COUNTER"
STUB
  chmod +x "$stub/date"
  export STUB_COUNTER="$stub/n"
  echo a >"$MACLIFT_HOME/.zshrc"
  echo b >"$MACLIFT_HOME/.gitconfig"
  PATH="$stub:$PATH" dotfiles_link_item dotfiles:zsh 0 >/dev/null
  PATH="$stub:$PATH" dotfiles_link_item dotfiles:git 0 >/dev/null
  assert_equals "1" "$(ls "$MACLIFT_CONFIG_DIR/backups" | wc -l | tr -d ' ')" "one backup folder"
  assert_equals "2" "$(cat "$MACLIFT_CONFIG_DIR"/backups/*/manifest.tsv | wc -l | tr -d ' ')" "single manifest, two rows"
}

test_linked_via_maclift_link
test_link_repo
test_backup_regular
test_dangling
test_user_only
test_user_unselected
test_one_run_folder
test_backup_symlink
test_backup_dir
test_idempotent
test_dry_run
test_override
test_summary
