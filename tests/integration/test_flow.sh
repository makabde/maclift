#!/usr/bin/env bash
#
# Integration tests for ./maclift: the whole flow, end to end, against a
# temporary home folder with stubbed brew, asdf, gum and machine checks.
#

# shellcheck disable=SC2088 # literal ~/ paths are the values under test
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACLIFT="$PROJECT_ROOT/maclift"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"

# Fresh sandbox: temp MACLIFT_HOME, a separate temp HOME, stubs first on PATH.
setup_env() {
  T="$(mktemp -d)"
  BIN="$T/bin"
  mkdir -p "$T/home" "$T/realhome" "$T/stub" "$BIN"
  ln -s "$PROJECT_ROOT/tests/stubs/brew" "$BIN/brew"
  ln -s "$PROJECT_ROOT/tests/stubs/asdf" "$BIN/asdf"
  # shellcheck disable=SC2016 # the stubs expand their own variables
  printf '#!/usr/bin/env bash\necho "$*" >>"$MACLIFT_STUB_DIR/gum.calls"\nexit 1\n' >"$BIN/gum"
  printf '#!/usr/bin/env bash\necho arm64\n' >"$BIN/fake-uname"
  printf '#!/usr/bin/env bash\necho 15.1\n' >"$BIN/fake-sw_vers"
  printf '#!/usr/bin/env bash\necho "Filesystem 1G-blocks Used Available"\necho "/dev/disk1 500 100 400"\n' >"$BIN/fake-df"
  chmod +x "$BIN"/gum "$BIN"/fake-*
  export MACLIFT_HOME="$T/home" HOME="$T/realhome" MACLIFT_STUB_DIR="$T/stub"
  export PATH="$BIN:$PATH"
  export MACLIFT_BREW="$BIN/brew" MACLIFT_ASDF="$BIN/asdf" MACLIFT_GUM="$BIN/gum"
  export MACLIFT_UNAME="$BIN/fake-uname" MACLIFT_SW_VERS="$BIN/fake-sw_vers" MACLIFT_DF="$BIN/fake-df"
  export MACLIFT_SKIP_BOOTSTRAP=1 MACLIFT_PLAIN=1
  unset MACLIFT_DIR MACLIFT_RUN_ID MACLIFT_LOG MACLIFT_ASSUME_YES MACLIFT_ASSUME_TTY
  CONF="$MACLIFT_HOME/.config/maclift"
}

# Name, email, empty GitHub, then Enter for every menu (accept), Install.
answers() {
  printf 'Test User\ntest@example.com\n\n'
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do printf '\n'; done
}

write_user_conf() {
  mkdir -p "$CONF"
  printf 'MACLIFT_NAME="Test User"\nMACLIFT_EMAIL="test@example.com"\nMACLIFT_GITHUB=""\n' >"$CONF/user.conf"
}

# Everything under MACLIFT_HOME except logs: paths, link targets, checksums.
snapshot() {
  local p
  find "$MACLIFT_HOME" -path "$CONF/logs" -prune -o -print | sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    elif [ -f "$p" ]; then
      printf 'F %s %s\n' "$p" "$(cksum <"$p")"
    else
      printf 'D %s\n' "$p"
    fi
  done
}

test_full_flow() {
  test_suite "interactive run installs, saves and links"
  setup_env
  local rc=0 out
  out="$(answers | "$MACLIFT" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_file_exists "$CONF/user.conf" "user.conf exists"
  assert_command_succeeds "grep -q 'MACLIFT_NAME=\"Test User\"' '$CONF/user.conf'" "user.conf has the name"
  assert_command_succeeds "grep -q 'brew:git' '$CONF/selection.conf'" "selection.conf has brew:git"
  assert_command_succeeds "[ -L '$MACLIFT_HOME/.zshrc' ]" ".zshrc is a symlink"
  case "$(readlink "$MACLIFT_HOME/.zshrc")" in
    "$PROJECT_ROOT/dotfiles/"*) assert_equals "ok" "ok" ".zshrc points into the repo dotfiles" ;;
    *) assert_equals "$PROJECT_ROOT/dotfiles/..." "$(readlink "$MACLIFT_HOME/.zshrc")" ".zshrc points into the repo dotfiles" ;;
  esac
  assert_command_succeeds "ls '$CONF'/logs/*.log" "the log exists"
  assert_command_succeeds "[ -L '$MACLIFT_HOME/.maclift' ]" ".maclift is a symlink"
  assert_equals "$PROJECT_ROOT" "$(readlink "$MACLIFT_HOME/.maclift")" ".maclift points at the repo"
  assert_file_exists "$MACLIFT_HOME/.gitconfig.local" "gitconfig.local written"
  assert_command_succeeds "grep -q '^install -- git' '$MACLIFT_STUB_DIR/brew.calls'" "git installed via brew"
  assert_contains "$out" "restart your terminal" "next steps shown"
  assert_contains "$out" "run maclift again with: $PROJECT_ROOT/maclift" "next steps show how to run maclift again"
  assert_contains "$out" "Always installed: Core" "required group shown as a note"

  test_suite "second run with -y changes nothing"
  local before after
  before="$(snapshot)"
  : >"$MACLIFT_STUB_DIR/brew.calls"
  rc=0
  out="$("$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  after="$(snapshot)"
  assert_equals "0" "$rc" "exit code 0"
  assert_contains "$out" "already installed" "prints already installed"
  assert_equals "$before" "$after" "home folder unchanged"
  assert_command_fails "grep -q '^install' '$MACLIFT_STUB_DIR/brew.calls'" "no brew installs"
}

test_dry_run() {
  test_suite "--dry-run on a fresh home only writes the config folder"
  setup_env
  mkdir -p "$CONF/hooks"
  printf 'echo pre >>"%s/pre-ran"\n' "$T" >"$CONF/hooks/pre-install.sh"
  local rc=0 out stray
  out="$(answers | "$MACLIFT" --dry-run 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  stray="$(find "$MACLIFT_HOME" -mindepth 1 ! -path "$MACLIFT_HOME/.config" ! -path "$CONF" ! -path "$CONF/*")"
  assert_equals "" "$stray" "no files outside the config folder"
  assert_command_fails "[ -e '$MACLIFT_HOME/.maclift' ] || [ -L '$MACLIFT_HOME/.maclift' ]" ".maclift not created"
  assert_contains "$out" "would link $MACLIFT_HOME/.maclift" "prints would link for .maclift"
  assert_file_exists "$CONF/selection.conf" "selection saved"
  assert_contains "$out" "would install" "prints would install"
  assert_contains "$out" "would run hook $CONF/hooks/pre-install.sh" "hook not run in dry-run"
  assert_command_fails "[ -e '$T/pre-ran' ]" "pre-install hook did not run"
  assert_command_fails "grep -q '^install' '$MACLIFT_STUB_DIR/brew.calls'" "no brew installs"
}

test_hooks() {
  test_suite "user hooks run around the install"
  setup_env
  write_user_conf
  mkdir -p "$CONF/hooks"
  printf 'echo post >>"%s/hooked"\n' "$T" >"$CONF/hooks/post-install.sh"
  printf 'echo pre >>"%s/pre-ran"\n' "$T" >"$CONF/hooks/pre-install.sh"
  local rc=0
  "$MACLIFT" -y </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_equals "1" "$(wc -l <"$T/hooked" | tr -d ' ')" "post-install hook ran once"
  assert_equals "1" "$(wc -l <"$T/pre-ran" | tr -d ' ')" "pre-install hook ran once"

  test_suite "a failing pre-install hook stops the run"
  setup_env
  write_user_conf
  mkdir -p "$CONF/hooks"
  printf 'exit 3\n' >"$CONF/hooks/pre-install.sh"
  rc=0
  "$MACLIFT" -y </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "exit code 1"
  assert_command_fails "grep -q '^install' '$MACLIFT_STUB_DIR/brew.calls'" "nothing installed"
}

test_guard() {
  test_suite "unset MACLIFT_HOME without --for-real exits 2"
  setup_env
  local rc=0 out dev="$T/devdir"
  # The guard only fires below 1.0, so run against a fake 0.9.0 MACLIFT_DIR.
  mkdir -p "$dev"
  printf '0.9.0\n' >"$dev/VERSION"
  out="$(unset MACLIFT_HOME; MACLIFT_DIR="$dev" HOME="$T/realhome" "$MACLIFT" </dev/null 2>&1)" || rc=$?
  assert_equals "2" "$rc" "exit code 2"
  assert_contains "$out" "pass --for-real" "explains --for-real"
  assert_equals "" "$(ls -A "$T/realhome")" "nothing written to the home folder"
}

test_flags() {
  test_suite "flags and subcommands"
  setup_env
  local rc=0 out
  out="$("$MACLIFT" --bogus </dev/null 2>&1)" || rc=$?
  assert_equals "64" "$rc" "unknown flag exits 64"
  assert_contains "$out" "Usage" "unknown flag prints usage"
  rc=0
  out="$("$MACLIFT" --help 2>&1)" || rc=$?
  assert_equals "0" "$rc" "--help exits 0"
  assert_contains "$out" "MACLIFT_SKIP_BOOTSTRAP" "--help documents the test-only variable"
  out="$("$MACLIFT" --version 2>&1)"
  assert_contains "$out" "$(head -n1 "$PROJECT_ROOT/VERSION")" "--version prints the version"
  rc=0
  out="$("$MACLIFT" --from </dev/null 2>&1)" || rc=$?
  assert_equals "64" "$rc" "--from without a value exits 64"
}

test_fine_tune_and_save() {
  test_suite "fine-tune unticks an item; Save without installing"
  setup_env
  local rc=0 first
  first="$(awk -F'\t' '/^@/ || /^#/ || NF < 4 { next } { print $1 ":" $2; exit }' "$PROJECT_ROOT/catalog/20-cli.tsv")"
  # name, email, github, groups, cli: toggle 1 then accept, 7 more groups, Save (3).
  rc=0
  {
    printf 'Test User\ntest@example.com\n\n\n1\n\n'
    printf '\n\n\n\n\n\n\n'
    printf '3\n'
  } | "$MACLIFT" >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_command_fails "grep -q '$first' '$CONF/selection.conf'" "$first unticked"
  assert_command_succeeds "grep -q 'brew:git' '$CONF/selection.conf'" "required item kept"
  assert_command_fails "grep -q '^install' '$MACLIFT_STUB_DIR/brew.calls'" "nothing installed"
  assert_command_fails "[ -e '$MACLIFT_HOME/.zshrc' ]" "nothing linked"

  test_suite "Back returns to the groups with choices kept"
  setup_env
  rc=0
  local out
  out="$({
    printf 'Test User\ntest@example.com\n\n\n1\n\n'
    printf '\n\n\n\n\n\n\n'
    printf '2\n'
    printf '\n\n\n\n\n\n\n\n\n'
    printf '3\n'
  } | "$MACLIFT" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_command_fails "grep -q '$first' '$CONF/selection.conf'" "$first still unticked after Back"
  assert_equals "2" "$(printf '%s\n' "$out" | grep -c 'Your choices')" "review shown twice"

  test_suite "Back keeps an unticked Brewfile.local extra unticked"
  setup_env
  mkdir -p "$CONF"
  printf 'brew "extra-one"\nbrew "extra-two"\n' >"$CONF/Brewfile.local"
  rc=0
  # name, email, github, groups, 8 groups, extras: untick 1 then accept,
  # Back; groups, 8 groups, extras accept, Install.
  out="$({
    printf 'Test User\ntest@example.com\n\n\n'
    printf '\n\n\n\n\n\n\n\n'
    printf '1\n\n'
    printf '2\n'
    printf '\n\n\n\n\n\n\n\n\n\n'
    printf '1\n'
  } | "$MACLIFT" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_equals "2" "$(printf '%s\n' "$out" | grep -c 'Your choices')" "review shown twice"
  assert_command_fails "grep -q '^install -- extra-one' '$MACLIFT_STUB_DIR/brew.calls'" "unticked extra not installed"
  assert_command_succeeds "grep -q '^install -- extra-two' '$MACLIFT_STUB_DIR/brew.calls'" "kept extra installed"
}

test_from() {
  test_suite "--from imports a selection, never scripts"
  setup_env
  write_user_conf
  printf 'MACLIFT_ITEMS="brew:git brew:bat script:evil"\n' >"$T/shared.conf"
  local rc=0
  "$MACLIFT" -y --dry-run --from "$T/shared.conf" </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_command_succeeds "grep -q 'brew:bat' '$CONF/selection.conf'" "imported item saved"
  assert_command_fails "grep -q 'script:evil' '$CONF/selection.conf'" "script item dropped"
  assert_command_fails "grep -q 'brew:ripgrep' '$CONF/selection.conf'" "selection replaced by the import"
}

test_extras_and_failures() {
  test_suite "Brewfile.local extras install; failures are summarised"
  setup_env
  write_user_conf
  printf 'brew "fail-me"\nbrew "extra-tool"\n' >"$CONF/Brewfile.local"
  local rc=0 out
  out="$("$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exit code 1 on a failed item"
  assert_command_succeeds "grep -q '^install -- extra-tool' '$MACLIFT_STUB_DIR/brew.calls'" "extra installed"
  assert_contains "$out" "✗ brew:fail-me" "failed id in the summary"
  assert_contains "$out" "stub: boom" "last log lines of the failure shown"
  assert_contains "$out" "failed: 1" "failed count"
  assert_command_fails "grep -q 'fail-me' '$CONF/selection.conf'" "extras are not saved in selection.conf"

  test_suite "re-run after the failure is fixed installs only the failed item"
  : >"$MACLIFT_STUB_DIR/fail-me.ok"
  : >"$MACLIFT_STUB_DIR/brew.calls"
  rc=0
  out="$("$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0 once nothing fails"
  assert_command_succeeds "grep -q '^install -- fail-me' '$MACLIFT_STUB_DIR/brew.calls'" "failed item installed this time"
  assert_command_succeeds "grep -qx 'fail-me' '$MACLIFT_STUB_DIR/brew.installed'" "failed item recorded as installed"
  assert_command_fails "grep -q '^install' <(grep -v 'fail-me' '$MACLIFT_STUB_DIR/brew.calls')" "nothing else reinstalled"
  assert_contains "$out" "already installed" "the others report already installed"
  assert_equals "0" "$(printf '%s\n' "$out" | grep -c 'failed: [1-9]' || true)" "no failures reported"
}

test_yes_installs_required() {
  test_suite "-y installs required Core items even when the saved selection omits them"
  setup_env
  write_user_conf
  printf 'MACLIFT_GROUPS="cli"\nMACLIFT_ITEMS="brew:bat"\n' >"$CONF/selection.conf"
  local rc=0
  "$MACLIFT" -y </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_command_succeeds "grep -q '^install -- bat' '$MACLIFT_STUB_DIR/brew.calls'" "bat installed"
  assert_command_succeeds "grep -q '^install -- git' '$MACLIFT_STUB_DIR/brew.calls'" "core item git installed"
}

test_sandbox_note() {
  test_suite "sandbox note when MACLIFT_HOME is not HOME"
  setup_env
  write_user_conf
  local note="MACLIFT_HOME is a sandbox, but packages still install system-wide" out
  out="$("$MACLIFT" -y </dev/null 2>&1)" || true
  assert_contains "$out" "$note" "note shown for a real install"
  out="$("$MACLIFT" -y --dry-run </dev/null 2>&1)" || true
  assert_equals "0" "$(printf '%s' "$out" | grep -c "$note" || true)" "no note in --dry-run"
}

# The summary box line right under "Next steps:" (plain ui_box: "== x ==").
line_under_next_steps() {
  printf '%s\n' "$1" | awk 'prev == "== Next steps: ==" { print; exit } { prev = $0 }'
}

test_next_steps_notes() {
  test_suite "notes from item scripts appear under Next steps"
  setup_env
  write_user_conf
  printf 'MACLIFT_ITEMS="brew:git script:ssh-key"\n' >"$CONF/selection.conf"
  local rc=0 out
  out="$(MACLIFT_SSH_KEYGEN="$PROJECT_ROOT/tests/stubs/ssh-keygen" MACLIFT_SSH_ADD="$PROJECT_ROOT/tests/stubs/ssh-add" \
    MACLIFT_GH="$PROJECT_ROOT/tests/stubs/gh" MACLIFT_HAS_TTY=1 "$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_file_exists "$MACLIFT_HOME/.ssh/id_ed25519" "key made in the sandbox"
  # The box always has "Next steps:" (restart the terminal...); the note must
  # be the line right under it, before the fixed steps.
  assert_equals "==   • sandbox run: skipped the keychain and GitHub upload for $MACLIFT_HOME/.ssh/id_ed25519.pub ==" \
    "$(line_under_next_steps "$out")" "the script's note is the first line under Next steps"
  assert_command_fails "[ -s '$MACLIFT_STUB_DIR/gh.calls' ]" "gh never called"
  assert_command_fails "[ -s '$MACLIFT_STUB_DIR/ssh-add.calls' ]" "ssh-add never called"

  # No notes: the fixed steps come right under the heading.
  setup_env
  write_user_conf
  printf 'MACLIFT_ITEMS="brew:git"\n' >"$CONF/selection.conf"
  rc=0; out="$("$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "0" "$rc" "no notes: exit code 0"
  assert_equals "==   • restart your terminal ==" "$(line_under_next_steps "$out")" "no notes: restart is the first step"
}

test_no_escapes_when_piped() {
  test_suite "piped -y output contains no escape codes"
  setup_env
  write_user_conf
  local out rc=0
  out="$(COLORTERM=truecolor TERM=xterm-256color "$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_equals "0" "$(printf '%s' "$out" | LC_ALL=C grep -c "$(printf '\033')" || true)" "no ESC byte in the output"
}

# run_interrupt <assume_tty:0|1>: starts a slow install, sends SIGINT, sets
# INT_RC and leaves the output in $T/int.out.
run_interrupt() {
  setup_env
  write_user_conf
  rm -f "$BIN/brew"
  # shellcheck disable=SC2016 # the stub expands its own variables
  printf '#!/usr/bin/env bash\necho "$*" >>"$MACLIFT_STUB_DIR/brew.calls"\ncase "$1" in install) sleep 30 ;; *) exit 1 ;; esac\n' >"$BIN/brew"
  chmod +x "$BIN/brew"
  local pid i=0
  INT_RC=0
  [ "$1" != 1 ] || export MACLIFT_ASSUME_TTY=1
  set -m # own process group, and SIGINT is not ignored in the background job
  "$MACLIFT" -y </dev/null >"$T/int.out" 2>&1 &
  pid=$!
  set +m
  unset MACLIFT_ASSUME_TTY
  while ! grep -q '^install' "$MACLIFT_STUB_DIR/brew.calls" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 200 ] || break
    sleep 0.1
  done
  kill -INT -- "-$pid" 2>/dev/null || kill -INT "$pid"
  wait "$pid" || INT_RC=$?
}

test_interrupt() {
  test_suite "Ctrl+C restores the terminal and exits 130"
  run_interrupt 1
  assert_equals "130" "$INT_RC" "exit code 130"
  assert_command_succeeds "grep -q 'Interrupted. Re-run maclift to finish (log: $CONF/logs/' '$T/int.out'" "prints Interrupted with the log path"
  assert_command_succeeds "grep -q \"$(printf '\033')\\[?25h\" '$T/int.out'" "cursor-show sequence printed on a terminal"

  test_suite "Ctrl+C without a terminal prints no escape codes"
  run_interrupt 0
  assert_equals "130" "$INT_RC" "exit code 130"
  assert_command_succeeds "grep -q 'Interrupted. Re-run maclift to finish' '$T/int.out'" "prints Interrupted"
  assert_command_fails "grep -q \"$(printf '\033')\" '$T/int.out'" "no ESC byte when not a terminal"
}

test_no_old_repo_paths() {
  test_suite "dotfiles use ~/.maclift, not a fixed clone path"
  # shellcheck disable=SC2088 # a literal pattern, not a path
  assert_equals "" "$(git -C "$PROJECT_ROOT" grep -n '~/maclift/' -- dotfiles || true)" "no literal home-relative clone paths in dotfiles"
}

test_second_identity() {
  test_suite "-y run writes the second identity"
  setup_env
  write_user_conf
  printf 'MACLIFT_ALT_NAME="Work User"\nMACLIFT_ALT_EMAIL="work@example.com"\nMACLIFT_ALT_DIR="~/Work/"\n' >>"$CONF/user.conf"
  printf 'MACLIFT_ITEMS="brew:git script:second-identity"\n' >"$CONF/selection.conf"
  local rc=0 out
  out="$("$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exit code 0"
  assert_equals "work@example.com" "$(git config -f "$MACLIFT_HOME/.gitconfig.alt" user.email 2>/dev/null || true)" ".gitconfig.alt written"
  assert_equals "~/.gitconfig.alt" "$(git config -f "$MACLIFT_HOME/.gitconfig.local" 'includeIf.gitdir:~/Work/.path' 2>/dev/null || true)" "includeIf in .gitconfig.local"

  test_suite "-y without the alt values fails"
  setup_env
  write_user_conf
  printf 'MACLIFT_ITEMS="brew:git script:second-identity"\n' >"$CONF/selection.conf"
  rc=0
  out="$("$MACLIFT" -y </dev/null 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exit code 1"
  assert_contains "$out" "second identity needs MACLIFT_ALT_NAME" "says what is missing"
}

test_full_flow
test_second_identity
test_dry_run
test_hooks
test_guard
test_flags
test_fine_tune_and_save
test_from
test_no_old_repo_paths
test_extras_and_failures
test_yes_installs_required
test_no_escapes_when_piped
test_sandbox_note
test_next_steps_notes
test_interrupt
test_summary
