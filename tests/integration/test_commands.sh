#!/usr/bin/env bash
#
# Integration tests for ./maclift subcommands (doctor, add, snapshot,
# restore, update) and their usage errors, against a temporary home folder
# with stubbed brew, asdf, git and gum.
#

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

write_user_conf() {
  mkdir -p "$CONF"
  printf 'MACLIFT_NAME="Test User"\nMACLIFT_EMAIL="test@example.com"\nMACLIFT_GITHUB=""\n' >"$CONF/user.conf"
}

test_doctor_cli() {
  test_suite "maclift doctor"
  setup_env
  write_user_conf
  local rc=0 out
  out="$("$MACLIFT" doctor 2>&1)" || rc=$?
  assert_equals "1" "$rc" "nothing linked: exit 1"
  assert_contains "$out" "problem(s) found" "summary line"
  assert_command_fails "[ -e '$CONF/logs' ]" "no log folder created"
}

test_doctor_no_guard() {
  test_suite "doctor skips the development guard"
  setup_env
  local rc=0
  mkdir -p "$T/devdir"
  printf '0.9.0\n' >"$T/devdir/VERSION"
  MACLIFT_DIR="$T/devdir" MACLIFT_HOME="$HOME" "$MACLIFT" doctor >/dev/null 2>&1 || rc=$?
  assert_command_fails "[ '$rc' = 2 ]" "does not exit 2"
}

test_usage() {
  test_suite "usage errors"
  setup_env
  local rc out
  rc=0; "$MACLIFT" add >/dev/null 2>&1 || rc=$?
  assert_equals "64" "$rc" "add without a name"
  rc=0; "$MACLIFT" doctor extra >/dev/null 2>&1 || rc=$?
  assert_equals "64" "$rc" "doctor with an argument"
  rc=0; out="$("$MACLIFT" frobnicate 2>&1)" || rc=$?
  assert_equals "64" "$rc" "unknown command"
  assert_contains "$out" "unknown command: frobnicate" "names the command"
  rc=0; "$MACLIFT" --run x >/dev/null 2>&1 || rc=$?
  assert_equals "64" "$rc" "--run without a command"
  rc=0; "$MACLIFT" --no-pull >/dev/null 2>&1 || rc=$?
  assert_equals "64" "$rc" "--no-pull without update"
  rc=0; "$MACLIFT" doctor --no-pull >/dev/null 2>&1 || rc=$?
  assert_equals "64" "$rc" "--no-pull with doctor"
  local c
  for c in doctor "add figlet" update snapshot restore; do
    # shellcheck disable=SC2086 # "add figlet" is two words on purpose
    rc=0; out="$("$MACLIFT" $c --from "$T" 2>&1)" || rc=$?
    assert_equals "64" "$rc" "--from with $c: exit 64"
    assert_contains "$out" "--from only works without a command" "--from with $c: says why"
  done
  rc=0; out="$("$MACLIFT" doctor --from="$T" 2>&1)" || rc=$?
  assert_equals "64" "$rc" "--from= with doctor: exit 64"
  rc=0; out="$("$MACLIFT" restore --run nope --dry-run 2>&1)" || rc=$?
  assert_equals "1" "$rc" "restore --run reaches restore: unknown run exits 1"
  assert_contains "$out" "no backup run nope" "restore gets the run id"
  out="$("$MACLIFT" --help)"
  local w
  for w in doctor add update snapshot restore; do
    assert_contains "$out" "maclift $w" "help lists $w"
  done
  assert_equals "1" "$(printf '%s\n' "$out" | grep -cF -- 'maclift add <name>... [--dry-run] [-y]')" "add synopsis"
  assert_equals "1" "$(printf '%s\n' "$out" | grep -cF -- 'maclift update [--dry-run] [-y]')" "update synopsis"
  assert_equals "1" "$(printf '%s\n' "$out" | grep -cF -- 'maclift snapshot [--dry-run] [-y]')" "snapshot synopsis"
  assert_equals "1" "$(printf '%s\n' "$out" | grep -cF -- 'maclift restore [--run <id>] [--dry-run] [-y]')" "restore synopsis"
  assert_equals "0" "$(printf '%s\n' "$out" | grep -cF -- '--for-real')" "help does not mention --for-real"
  # With nothing linked doctor reports problems (exit 1); the flag must not change that.
  rc=0; out="$("$MACLIFT" doctor --for-real 2>&1)" || rc=$?
  assert_equals "1" "$rc" "doctor --for-real is still accepted (same exit as without it)"
  assert_contains "$out" "problem(s) found" "doctor --for-real runs the checks"
}

test_add_cli() {
  test_suite "maclift add"
  setup_env
  write_user_conf
  printf 'figlet\n' >"$T/stub/brew.formulae"
  local rc=0 out
  out="$("$MACLIFT" add --dry-run figlet 2>&1)" || rc=$?
  assert_equals "0" "$rc" "dry run exits 0"
  assert_contains "$out" "would install" "dry run says would install"
  printf 'docker\n' >"$T/stub/brew.formulae"
  printf 'docker\n' >"$T/stub/brew.casks"
  rc=0; out="$("$MACLIFT" add --dry-run docker 2>&1)" || rc=$?
  assert_equals "1" "$rc" "ambiguous name exits 1"
  assert_contains "$out" "brew:docker or cask:docker" "says how to choose"
  # A real add goes through the dispatcher to the brew stub.
  printf 'figlet\n' >"$T/stub/brew.formulae"
  : >"$T/stub/brew.casks"
  rc=0; out="$("$MACLIFT" add figlet 2>&1)" || rc=$?
  assert_equals "0" "$rc" "add figlet exits 0"
  assert_command_succeeds "grep -Fxq 'install -- figlet' '$T/stub/brew.calls'" "brew stub installed figlet"
  assert_contains "$(cat "$CONF/Brewfile.local")" 'brew "figlet"' "recorded in Brewfile.local"
  assert_equals "" "$(printf '%s\n' "$out" | grep -F 'Next steps:' || true)" "no notes: no Next steps heading"
}

test_snapshot_cli() {
  test_suite "maclift snapshot"
  setup_env
  write_user_conf
  printf 'figlet\n' >"$T/stub/brew.leaves"
  local rc=0 out
  out="$("$MACLIFT" snapshot --dry-run -y 2>&1)" || rc=$?
  assert_equals "0" "$rc" "dry run exits 0"
  assert_command_fails "[ -e '$CONF/Brewfile.local' ]" "dry run writes nothing"
  rc=0; out="$("$MACLIFT" snapshot -y 2>&1)" || rc=$?
  assert_equals "0" "$rc" "snapshot -y exits 0"
  assert_contains "$(cat "$CONF/Brewfile.local")" 'brew "figlet"' "appended to Brewfile.local"
}

test_restore_cli() {
  test_suite "maclift restore"
  setup_env
  write_user_conf
  local rc=0 out
  out="$("$MACLIFT" restore -y 2>&1)" || rc=$?
  assert_equals "0" "$rc" "no backups: exit 0"
  assert_contains "$out" "No backups" "says so"
  mkdir -p "$CONF/backups/2026-01-01_000000"
  printf 'old' >"$CONF/backups/2026-01-01_000000/.zshrc"
  printf '%s\t%s\n' "$MACLIFT_HOME/.zshrc" "$CONF/backups/2026-01-01_000000/.zshrc" >"$CONF/backups/2026-01-01_000000/manifest.tsv"
  ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  rc=0; out="$("$MACLIFT" restore -y 2>&1)" || rc=$?
  assert_equals "64" "$rc" "-y without --run: exit 64"
  assert_contains "$out" "needs --run" "mentions --run"
  rc=0; out="$("$MACLIFT" restore -y --run 2026-01-01_000000 2>&1)" || rc=$?
  assert_equals "0" "$rc" "restore -y --run exits 0"
  assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "file restored"
  assert_contains "$out" "Undo with: maclift restore --run" "prints the undo hint"
  # The --run=<id> form reaches restore too.
  rm -f "$MACLIFT_HOME/.zshrc"
  ln -s /nowhere "$MACLIFT_HOME/.zshrc"
  rc=0; out="$("$MACLIFT" restore -y --run=2026-01-01_000000 2>&1)" || rc=$?
  assert_equals "0" "$rc" "restore -y --run=<id> exits 0"
  assert_equals "old" "$(cat "$MACLIFT_HOME/.zshrc")" "--run=<id>: file restored"
  rc=0; out="$("$MACLIFT" restore --dry-run --run=nope 2>&1)" || rc=$?
  assert_equals "1" "$rc" "--run=<unknown> exits 1"
  assert_contains "$out" "no backup run nope" "--run=<id> passes the id"
}

test_update_reexec() {
  test_suite "maclift update"
  setup_env
  write_user_conf
  export MACLIFT_GIT="$PROJECT_ROOT/tests/stubs/git"
  local rc=0 out fake="$T/clone"
  # A temp MACLIFT_DIR whose fake maclift records the re-exec arguments.
  mkdir -p "$fake"
  cp "$PROJECT_ROOT/VERSION" "$fake/"
  # shellcheck disable=SC2016 # the fake expands its own variables
  printf '#!/usr/bin/env bash\necho "$*" >"$MACLIFT_STUB_DIR/reexec"\n' >"$T/fake-maclift"
  cp "$T/fake-maclift" "$fake/maclift"
  chmod +x "$fake/maclift"
  rc=0; MACLIFT_DIR="$fake" "$MACLIFT" update -y >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "re-exec exits with the new maclift's code"
  assert_equals "update --no-pull -y" "$(cat "$T/stub/reexec")" "pull moved HEAD: re-runs with --no-pull -y"
  assert_command_succeeds "grep -q -- 'pull --ff-only' '$T/stub/git.calls'" "pull was --ff-only"
  rm -f "$T/stub/reexec" "$T/stub/git.head" "$T/stub/git.calls"
  rc=0; MACLIFT_DIR="$fake" "$MACLIFT" update --no-pull -y >/dev/null 2>&1 || rc=$?
  assert_command_fails "[ -e '$T/stub/reexec' ]" "--no-pull does not re-exec"
  assert_command_fails "grep -q pull '$T/stub/git.calls'" "--no-pull makes no pull call"
  rm -f "$T/stub/reexec" "$T/stub/git.head"
  rc=0; MACLIFT_DIR="$fake" "$MACLIFT" update -y --for-real >/dev/null 2>&1 || rc=$?
  assert_equals "update --no-pull -y --for-real" "$(cat "$T/stub/reexec")" "--for-real is passed on"

  # A maclift that is not executable: no exec, the run finishes in-process.
  chmod -x "$fake/maclift"
  rm -f "$T/stub/reexec" "$T/stub/git.head"
  rc=0; out="$(MACLIFT_DIR="$fake" "$MACLIFT" update -y 2>&1)" || rc=$?
  assert_equals "0" "$rc" "not executable: exit 0"
  assert_contains "$out" "maclift is not executable; finishing this update with the code already loaded" "says why"
  assert_contains "$out" "All packages are up to date" "the run went on"
  assert_command_fails "[ -e '$T/stub/reexec' ]" "not executable: no re-exec"
  chmod +x "$fake/maclift"

  # Managed, installed, outdated packages (extras in Brewfile.local).
  printf 'brew "fail-me"\nbrew "zz-ok"\n' >"$CONF/Brewfile.local"
  printf 'fail-me\nzz-ok\n' >"$T/stub/brew.installed"
  printf 'fail-me\nzz-ok\n' >"$T/stub/brew.outdated"
  rm -f "$T/stub/reexec" "$T/stub/git.calls" "$T/stub/brew.calls" "$T/stub/git.head"
  rc=0; out="$(MACLIFT_DIR="$fake" "$MACLIFT" update --dry-run 2>&1)" || rc=$?
  assert_equals "0" "$rc" "update --dry-run exits 0"
  assert_contains "$out" "package lists may be stale" "dry run notes stale lists"
  assert_contains "$out" "would pull" "dry run: would pull"
  assert_contains "$out" "would upgrade brew:zz-ok" "dry run: would upgrade"
  assert_command_fails "grep -q pull '$T/stub/git.calls'" "dry run: no pull call"
  assert_command_fails "grep -E '^(update|upgrade)' '$T/stub/brew.calls'" "dry run: no brew update or upgrade"
  assert_command_fails "[ -e '$T/stub/reexec' ]" "dry run: no re-exec"

  # An upgrade failure exits 1 but later packages still upgrade.
  rm -f "$T/stub/brew.calls"
  rc=0; out="$(MACLIFT_DIR="$fake" "$MACLIFT" update --no-pull -y 2>&1)" || rc=$?
  assert_equals "1" "$rc" "failed upgrade: exit 1"
  assert_command_succeeds "grep -Fxq 'upgrade -- zz-ok' '$T/stub/brew.calls'" "later package still upgraded"
  assert_contains "$out" "brew:fail-me" "failure is named"
  assert_contains "$out" "Upgraded: 1 · failed: 1" "summary counts"

  # A failed pull exits 1 and does not re-exec.
  : >"$T/stub/git.pullfail"
  : >"$T/stub/brew.outdated"
  : >"$T/stub/brew.cask-outdated"
  rm -f "$T/stub/reexec" "$T/stub/git.head"
  rc=0; out="$(MACLIFT_DIR="$fake" "$MACLIFT" update -y 2>&1)" || rc=$?
  assert_equals "1" "$rc" "failed pull: exit 1"
  assert_contains "$out" "could not fast-forward" "failed pull is reported"
  assert_contains "$out" "All packages are up to date" "failed pull: upgrade step ran clean"
  assert_command_fails "[ -e '$T/stub/reexec' ]" "failed pull: no re-exec"

  # A failed brew update is noted but is not an error.
  rm -f "$T/stub/git.pullfail"
  : >"$T/stub/brew.updatefail"
  rc=0; out="$(MACLIFT_DIR="$fake" "$MACLIFT" update --no-pull -y 2>&1)" || rc=$?
  assert_equals "0" "$rc" "failed brew update: exit 0"
  assert_contains "$out" "(package lists may be stale)" "failed brew update: stale qualifier"
  unset MACLIFT_GIT
}

test_guard() {
  test_suite "snapshot refuses the real home folder"
  setup_env
  local rc=0
  # The guard only fires below 1.0, so run against a fake 0.9.0 MACLIFT_DIR.
  mkdir -p "$T/devdir"
  printf '0.9.0\n' >"$T/devdir/VERSION"
  MACLIFT_DIR="$T/devdir" MACLIFT_HOME="$HOME" "$MACLIFT" snapshot >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "exit 2 on the real home folder"
}

test_doctor_cli
test_doctor_no_guard
test_usage
test_add_cli
test_snapshot_cli
test_restore_cli
test_update_reexec
test_guard
test_summary
