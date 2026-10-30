#!/usr/bin/env bash
#
# Unit tests for lib/doctor.sh
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
# shellcheck source=lib/identity.sh
source "$PROJECT_ROOT/lib/identity.sh"
# shellcheck source=lib/ui.sh
source "$PROJECT_ROOT/lib/ui.sh"
# shellcheck source=lib/dotfiles.sh
source "$PROJECT_ROOT/lib/dotfiles.sh"
# shellcheck source=lib/asdf.sh
source "$PROJECT_ROOT/lib/asdf.sh"
# shellcheck source=lib/bootstrap.sh
source "$PROJECT_ROOT/lib/bootstrap.sh"
# shellcheck source=lib/doctor.sh
source "$PROJECT_ROOT/lib/doctor.sh"

export MACLIFT_PLAIN=1
export MACLIFT_DIR="$PROJECT_ROOT"

# A healthy sandbox: everything the checks look at is in order.
setup_healthy() {
  T="$(mktemp -d)"
  MACLIFT_HOME="$T/home"
  mkdir -p "$MACLIFT_HOME" "$T/bin" "$T/stub"
  export MACLIFT_HOME MACLIFT_STUB_DIR="$T/stub"
  maclift_init_paths
  ln -s "$PROJECT_ROOT/tests/stubs/brew" "$T/bin/brew"
  ln -s "$PROJECT_ROOT/tests/stubs/asdf" "$T/bin/asdf"
  export MACLIFT_BREW="$T/bin/brew" MACLIFT_ASDF="$T/bin/asdf"
  export MACLIFT_LOGIN_SHELL=/bin/zsh
  export MACLIFT_DOCTOR_PATH="$T/bin:/usr/bin"
  mkdir -p "$MACLIFT_CONFIG_DIR"
  printf 'MACLIFT_NAME="Test User"\nMACLIFT_EMAIL="test@example.com"\nMACLIFT_GITHUB=""\n' >"$MACLIFT_CONFIG_DIR/user.conf"
  git config -f "$MACLIFT_HOME/.gitconfig.local" user.email test@example.com
  ln -s "$PROJECT_ROOT" "$MACLIFT_HOME/.maclift"
  local id
  for id in $(selection_load); do
    case "$id" in dotfiles:*) dotfiles_link_item "$id" 0 >/dev/null ;; esac
  done
}

test_healthy() {
  test_suite "doctor: healthy machine"
  setup_healthy
  local out rc=0
  out="$(cmd_doctor 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit 0"
  assert_contains "$out" "All 8 checks passed" "summary line"
}

test_shell_bash() {
  test_suite "doctor: login shell is bash"
  setup_healthy
  local out rc=0
  out="$(MACLIFT_LOGIN_SHELL=/bin/bash cmd_doctor 0 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exit 1"
  assert_contains "$out" "✗" "has a cross"
  assert_contains "$out" "chsh -s /bin/zsh" "shows the fix"
  assert_contains "$out" "1 problem(s) found" "summary line"
}

test_path_order() {
  test_suite "doctor: shims must come before brew"
  setup_healthy
  printf 'nodejs 24.5.1\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  local rc=0
  MACLIFT_DOCTOR_PATH="$T/bin:$MACLIFT_HOME/.asdf/shims" doctor_check_path >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "brew before shims fails"
  rc=0
  MACLIFT_DOCTOR_PATH="$MACLIFT_HOME/.asdf/shims:$T/bin" doctor_check_path >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "shims before brew passes"
  rc=0
  MACLIFT_DOCTOR_PATH="/usr/bin" doctor_check_path >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "brew missing from PATH fails"
}

test_dangling_link() {
  test_suite "doctor: dangling link into maclift"
  setup_healthy
  ln -s "$MACLIFT_HOME/.maclift/nope" "$MACLIFT_HOME/.broken"
  local out rc=0
  out="$(doctor_check_links 2>&1)" || rc=$?
  assert_equals "1" "$rc" "fails"
  assert_contains "$out" ".broken" "names the link"
  rm "$MACLIFT_HOME/.broken"
  ln -s /nonexistent/elsewhere "$MACLIFT_HOME/.unrelated"
  rc=0
  doctor_check_links >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "unrelated dangling link is ignored"
}

test_unlinked_item() {
  test_suite "doctor: selected dotfile not linked"
  setup_healthy
  rm "$MACLIFT_HOME/.zshrc"
  local rc=0
  doctor_check_links >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "fails"
}

test_repo_link() {
  test_suite "doctor: repo link"
  setup_healthy
  rm "$MACLIFT_HOME/.maclift"
  local rc=0
  doctor_check_repo_link >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "missing link fails"
  ln -s /tmp "$MACLIFT_HOME/.maclift"
  rc=0
  doctor_check_repo_link >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "wrong target fails"
}

test_asdf() {
  test_suite "doctor: asdf pins"
  setup_healthy
  printf 'nodejs 24.5.1\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  local rc=0
  doctor_check_asdf >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "pin not installed fails"
  echo "nodejs 24.5.1" >"$T/stub/asdf.installed"
  rc=0
  doctor_check_asdf >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "pins not applied to ~/.tool-versions fails"
  pins_apply 0 >/dev/null
  rc=0
  doctor_check_asdf >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "installed and applied passes"
}

test_git_mismatch() {
  test_suite "doctor: git email mismatch"
  setup_healthy
  git config -f "$MACLIFT_HOME/.gitconfig.local" user.email other@example.com
  local rc=0
  doctor_check_git >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "fails"
}

test_git_signing_key() {
  test_suite "doctor: signing key"
  setup_healthy
  export MACLIFT_GPG="$PROJECT_ROOT/tests/stubs/gpg"
  : >"$MACLIFT_STUB_DIR/gpg.secret"
  local rc=0 out
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_SIGNING_KEY "ABCDEF0123456789"
  out="$(doctor_check_git 2>&1)" || rc=$?
  assert_equals "1" "$rc" "unknown signing key fails"
  assert_contains "$out" "gpg --import your key, or remove MACLIFT_SIGNING_KEY from user.conf" "fix text"
  echo "ABCDEF0123456789 test@example.com" >"$MACLIFT_STUB_DIR/gpg.secret"
  rc=0
  doctor_check_git >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "known signing key passes"
  out="$(MACLIFT_GPG="$T/no-gpg" doctor_check_git 2>&1)" || true
  assert_contains "$out" "gpg not found" "missing gpg binary is named"
  unset MACLIFT_GPG
}

test_git_alt_identity() {
  test_suite "doctor: second identity"
  setup_healthy
  local rc=0 out uc="$MACLIFT_CONFIG_DIR/user.conf"
  conf_set "$uc" MACLIFT_ALT_DIR "~/Work"
  conf_set "$uc" MACLIFT_ALT_EMAIL "work@example.com"
  doctor_check_git >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "deselected item: alt email is not checked"
  conf_set "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS "script:second-identity"
  rc=0
  doctor_check_git >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "missing .gitconfig.alt fails"
  git config -f "$MACLIFT_HOME/.gitconfig.alt" user.email work@example.com
  rc=0
  out="$(doctor_check_git 2>&1)" || rc=$?
  assert_equals "1" "$rc" "hand-made alt file with the right email is stale"
  assert_contains "$out" "out of date with user.conf" "says it is stale"
  assert_contains "$out" "maclift -y" "fix text"
  conf_set "$uc" MACLIFT_ALT_NAME "Work User"
  rm -f "$MACLIFT_HOME/.gitconfig.alt"
  identity_render_alt 0 >/dev/null
  rc=0
  doctor_check_git >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "freshly rendered alt file passes"
  conf_set "$uc" MACLIFT_ALT_SIGNING_KEY "ABCDEF0123456789"
  rc=0
  doctor_check_git >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "added alt signing key makes it stale"
}

test_brew_missing() {
  test_suite "doctor: brew missing"
  setup_healthy
  local rc=0
  MACLIFT_BREW="$T/nope" doctor_check_brew >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "fails"
}

# Every path under the home folder with its type and content: file checksums,
# link targets, folder names.
tree_state() {
  local p
  find "$MACLIFT_HOME" | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    elif [ -f "$p" ]; then
      printf 'F %s %s\n' "$p" "$(cksum <"$p")"
    else
      printf 'D %s\n' "$p"
    fi
  done
}

test_read_only() {
  test_suite "doctor changes nothing"
  setup_healthy
  local before after out
  before="$(tree_state)"
  cmd_doctor 0 >/dev/null 2>&1 || true
  after="$(tree_state)"
  assert_equals "$before" "$after" "healthy: nothing changed"
  # Broken in every way doctor can see, with the pins installed but not
  # applied, so the asdf check really runs pins_apply 1.
  rm "$MACLIFT_HOME/.zshrc"
  ln -s "$MACLIFT_HOME/.maclift/nope" "$MACLIFT_HOME/.broken"
  printf 'nodejs 24.5.1\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  echo "nodejs 24.5.1" >"$T/stub/asdf.installed"
  printf '# mine\nnodejs 20.0.0\n' >"$MACLIFT_HOME/.tool-versions"
  conf_set "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS "script:ssh-key"
  mkdir -p "$MACLIFT_HOME/.ssh"
  echo "private" >"$MACLIFT_HOME/.ssh/id_ed25519"
  git config -f "$MACLIFT_HOME/.gitconfig.local" user.email other@example.com
  before="$(tree_state)"
  out="$(MACLIFT_LOGIN_SHELL=/bin/bash cmd_doctor 0 2>&1)" || true
  after="$(tree_state)"
  assert_contains "$out" "pins differ from ~/.tool-versions" "reached pins_apply 1"
  assert_contains "$out" "id_ed25519.pub is missing" "reached the ssh check"
  assert_equals "$before" "$after" "broken: nothing changed (paths and contents)"
}

# A stub login shell that prints a PATH, or sleeps longer than the limit.
test_login_shell_path() {
  test_suite "doctor: PATH from the login shell"
  setup_healthy
  unset MACLIFT_DOCTOR_PATH
  printf '#!/bin/bash\nprintf "\\n__MACLIFT_PATH__=%%s\\n" "%s/bin:/usr/bin"\n' "$T" >"$T/fast-shell"
  printf '#!/bin/bash\n/bin/sleep 8\n' >"$T/slow-shell"
  chmod +x "$T/fast-shell" "$T/slow-shell"
  assert_equals "$T/bin:/usr/bin" "$(MACLIFT_LOGIN_SHELL="$T/fast-shell" _doctor_path)" "reads the login shell's PATH"
  local rc=0 out start secs
  start="$(date +%s)"
  out="$(MACLIFT_LOGIN_SHELL="$T/slow-shell" MACLIFT_DOCTOR_SHELL_TIMEOUT=1 doctor_check_path 2>&1)" || rc=$?
  secs=$(($(date +%s) - start))
  assert_equals "1" "$rc" "slow login shell fails the check"
  assert_contains "$out" "could not read your login PATH (your login shell took over 1s)" "says the shell was too slow"
  assert_contains "$out" "fix: check ~/.zprofile and ~/.zshrc (they must finish without waiting for input)" "fix text"
  assert_command_succeeds "[ $secs -lt 5 ]" "gave up after the limit (${secs}s)"
  export MACLIFT_DOCTOR_PATH="$T/bin:/usr/bin"
}

# A stub zsh: junk output around the marker line; the asdf shims come first
# only in an interactive shell (added by .zshrc), as on the owner's Mac.
test_login_shell_interactive() {
  test_suite "doctor: PATH from an interactive login shell"
  setup_healthy
  unset MACLIFT_DOCTOR_PATH
  printf 'nodejs 24.5.1\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  cat >"$T/stub-zsh" <<EOS
#!/bin/bash
p="$T/bin:/usr/bin"
case "\$1" in -*i*) p="$MACLIFT_HOME/.asdf/shims:\$p" ;; esac
echo "Last login: junk"
printf '\033]1337;SetUserVar=x\007prompt%% '
printf '\n__MACLIFT_PATH__=%s\n' "\$p"
echo "__MACLIFT_PATH__ is not at the start of this line"
printf '\033]0;title\007'
EOS
  chmod +x "$T/stub-zsh"
  local rc=0 out
  assert_equals "$MACLIFT_HOME/.asdf/shims:$T/bin:/usr/bin" "$(MACLIFT_LOGIN_SHELL="$T/stub-zsh" _doctor_path)" "only the marker line, from an interactive shell"
  out="$(MACLIFT_LOGIN_SHELL="$T/stub-zsh" doctor_check_path 2>&1)" || rc=$?
  assert_equals "0" "$rc" "shims from .zshrc count: check passes"
  assert_contains "$out" "PATH has Homebrew after the asdf shims" "says so"
  export MACLIFT_DOCTOR_PATH="$T/bin:/usr/bin"
}

test_shell_timeout_value() {
  test_suite "doctor: login shell timeout value"
  local v
  for v in "" abc 0 00 -3 1.5; do
    assert_equals "10" "$(MACLIFT_DOCTOR_SHELL_TIMEOUT="$v" _doctor_shell_timeout)" "'$v' -> 10"
  done
  assert_equals "3" "$(MACLIFT_DOCTOR_SHELL_TIMEOUT=3 _doctor_shell_timeout)" "3 -> 3"
  assert_equals "8" "$(MACLIFT_DOCTOR_SHELL_TIMEOUT=08 _doctor_shell_timeout)" "08 -> 8"
}

test_path_index_backslash() {
  test_suite "doctor: PATH entries with backslashes"
  assert_equals "2" "$(_doctor_path_index '/x\ty' '/a:/x\ty:/b')" "backslash entry found literally"
  assert_equals "" "$(_doctor_path_index '/x' '/a:/b')" "absent entry: empty"
  assert_equals "3" "$(_doctor_path_index '/b' '/a::/b')" "empty entries are counted"
}

test_asdf_broken_line() {
  test_suite "doctor: pin line without a version"
  setup_healthy
  printf 'nodejs\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  local rc=0 out
  out="$(doctor_check_asdf 2>&1)" || rc=$?
  assert_equals "1" "$rc" "fails"
  assert_contains "$out" "broken pin line 'nodejs' (no version)" "names the broken line"
  printf 'nodejs\t24.5.1\n' >"$MACLIFT_CONFIG_DIR/tool-versions"
  echo "nodejs 24.5.1" >"$T/stub/asdf.installed"
  out="$(doctor_check_asdf 2>&1)" || true
  assert_contains "$out" "pins differ" "tab-separated line is read as nodejs 24.5.1"
}

test_ssh_pub_missing() {
  test_suite "doctor: SSH key without its .pub"
  setup_healthy
  local rc=0 out
  mkdir -p "$MACLIFT_HOME/.ssh"
  echo "private" >"$MACLIFT_HOME/.ssh/id_ed25519"
  doctor_check_ssh >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "not selected: not checked"
  conf_set "$MACLIFT_CONFIG_DIR/selection.conf" MACLIFT_ITEMS "script:ssh-key"
  rc=0
  out="$(doctor_check_ssh 2>&1)" || rc=$?
  assert_equals "1" "$rc" "selected, .pub missing: fails"
  assert_contains "$out" "fix: ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub" "fix text"
  assert_command_fails "[ -e '$MACLIFT_HOME/.ssh/id_ed25519.pub' ]" "doctor does not create the .pub"
  echo "public" >"$MACLIFT_HOME/.ssh/id_ed25519.pub"
  rc=0
  doctor_check_ssh >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "both files: passes"
  rm "$MACLIFT_HOME/.ssh/id_ed25519"
  rc=0
  out="$(doctor_check_ssh 2>&1)" || rc=$?
  assert_equals "1" "$rc" "orphan .pub: fails"
  assert_contains "$out" "fix: move ~/.ssh/id_ed25519.pub aside" "orphan .pub fix text"
  assert_equals "public" "$(cat "$MACLIFT_HOME/.ssh/id_ed25519.pub")" "orphan .pub left alone"
}

test_healthy
test_shell_bash
test_path_order
test_dangling_link
test_unlinked_item
test_repo_link
test_asdf
test_git_mismatch
test_git_signing_key
test_git_alt_identity
test_brew_missing
test_read_only
test_login_shell_path
test_login_shell_interactive
test_shell_timeout_value
test_path_index_backslash
test_asdf_broken_line
test_ssh_pub_missing
test_summary
