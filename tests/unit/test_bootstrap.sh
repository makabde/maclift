#!/usr/bin/env bash
#
# Unit tests for lib/bootstrap.sh (stubs only; never installs anything)
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
# shellcheck source=lib/bootstrap.sh
source "$PROJECT_ROOT/lib/bootstrap.sh"

MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
STUBS="$(mktemp -d)"
CALLS="$STUBS/calls"
# A release folder: never the real clone.
MACLIFT_DIR="$(mktemp -d)"
GSTUB="$(mktemp -d)"
export MACLIFT_DIR
trap 'rm -rf "$MACLIFT_HOME" "$STUBS" "$MACLIFT_DIR" "$GSTUB"' EXIT

mk_stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUBS/$1"; chmod +x "$STUBS/$1"; }

export MACLIFT_BOOTSTRAP_POLL=0.1 MACLIFT_BOOTSTRAP_TIMEOUT=1
export MACLIFT_XCODE_SELECT="$STUBS/xcode-select" MACLIFT_CURL="$STUBS/curl" MACLIFT_BREW="$STUBS/brew-missing"

test_bootstrap() {
  test_suite "bootstrap_run"
  local out rc

  : >"$CALLS"
  mk_stub xcode-select "echo \"xcode-select \$*\" >>$CALLS; [ \"\$1\" = -p ] && exit 1; exit 0"
  rc=0; out="$(bootstrap_run 0 2>&1)" || rc=$?
  assert_equals "1" "$rc" "CLT that never installs fails within the timeout"
  assert_contains "$out" "Command-line tools were not installed. Run xcode-select --install, accept the dialog, then run maclift again." "timeout message says what to do"

  : >"$CALLS"
  mk_stub xcode-select "echo \"xcode-select \$*\" >>$CALLS; exit 0"
  mk_stub curl "echo curl >>$CALLS; exit 22"
  rc=0; out="$(bootstrap_run 0 2>&1)" || rc=$?
  assert_equals "1" "$rc" "failed Homebrew download fails"
  assert_contains "$out" "Could not download the Homebrew installer (check your internet connection)." "download failure message"
  assert_equals "0" "$(grep -c brew "$CALLS" || true)" "brew never invoked after failed download"

  : >"$CALLS"
  mk_stub xcode-select "echo \"xcode-select \$*\" >>$CALLS; [ \"\$1\" = -p ] && exit 1; exit 0"
  mk_stub curl "echo curl >>$CALLS; exit 0"
  rc=0; out="$(bootstrap_run 1 2>&1)" || rc=$?
  assert_equals "0" "$rc" "dry run succeeds"
  assert_contains "$out" "would install: Homebrew" "dry run reports missing Homebrew"
  assert_equals "0" "$(grep -c -e '--install' -e curl "$CALLS" || true)" "dry run makes no install calls"

  # The git-clone step runs as part of bootstrap_run.
  write_marker
  rc=0; out="$(bootstrap_run 1 2>&1)" || rc=$?
  assert_contains "$out" "would turn $MACLIFT_DIR into a git clone of makabde/maclift" "bootstrap_run includes the git-clone step"
  rm -f "$MACLIFT_DIR/.maclift-release"
}

test_bootstrap_git_clone() {
  test_suite "bootstrap_git_clone"
  local out rc
  export MACLIFT_STUB_DIR="$GSTUB" MACLIFT_GIT="$PROJECT_ROOT/tests/stubs/git"

  # test_bootstrap_makes_clone
  rm -f "$GSTUB"/git.*; write_marker
  rc=0; out="$(bootstrap_git_clone 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "making the clone succeeds"
  assert_equals "init -q
remote add origin https://github.com/makabde/maclift.git
fetch -q origin main --tags
checkout -q -f -B main v1.0.0
branch -q -u origin/main main" "$(cat "$GSTUB/git.calls")" "git calls in order"
  assert_contains "$out" "✓ $MACLIFT_DIR is now a git clone (maclift update keeps it current)" "says the folder is a clone"
  assert_command_fails "[ -e '$MACLIFT_DIR/.maclift-release' ]" "marker removed"

  # every git call runs with GIT_TERMINAL_PROMPT=0, so a 401 can't hang,
  # even when the environment says 1
  rm -f "$GSTUB"/git.*; write_marker
  mk_stub git-env "echo \"\${GIT_TERMINAL_PROMPT:-unset}\" >>\"$GSTUB/git.prompt\"; exec \"$PROJECT_ROOT/tests/stubs/git\" \"\$@\""
  rc=0; out="$(GIT_TERMINAL_PROMPT=1 MACLIFT_GIT="$STUBS/git-env" bootstrap_git_clone 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "prompt check: succeeds"
  assert_equals "0 0 0 0 0" "$(tr '\n' ' ' <"$GSTUB/git.prompt" | sed 's/ $//')" "GIT_TERMINAL_PROMPT=0 for each git call"

  # dry run
  rm -f "$GSTUB"/git.*; write_marker
  rc=0; out="$(bootstrap_git_clone 1 2>&1)" || rc=$?
  assert_equals "0" "$rc" "dry run succeeds"
  assert_contains "$out" "would turn $MACLIFT_DIR into a git clone of makabde/maclift" "dry run says what it would do"
  assert_command_fails "[ -e '$GSTUB/git.calls' ]" "dry run makes no git calls"
  assert_command_succeeds "[ -e '$MACLIFT_DIR/.maclift-release' ]" "dry run keeps the marker"

  # no marker
  rm -f "$GSTUB"/git.* "$MACLIFT_DIR/.maclift-release"
  rc=0; out="$(bootstrap_git_clone 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "no marker: succeeds"
  assert_equals "" "$out" "no marker: prints nothing"
  assert_command_fails "[ -e '$GSTUB/git.calls' ]" "no marker: no git calls"

  # already a clone
  rm -f "$GSTUB"/git.*; write_marker; mkdir "$MACLIFT_DIR/.git"
  rc=0; out="$(bootstrap_git_clone 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "already a clone: succeeds"
  assert_command_fails "[ -e '$GSTUB/git.calls' ]" "already a clone: no git calls"
  rmdir "$MACLIFT_DIR/.git"

  # failed fetch
  rm -f "$GSTUB"/git.*; write_marker; : >"$GSTUB/git.fetchfail"
  rc=0; out="$(bootstrap_git_clone 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "failed fetch does not fail the run"
  assert_contains "$out" "✗ could not make $MACLIFT_DIR a git clone; run maclift again to retry (until then maclift update skips pulling)" "failed fetch message says how to retry"
  assert_command_succeeds "[ -e '$MACLIFT_DIR/.maclift-release' ]" "failed fetch keeps the marker"
  assert_command_fails "grep -q checkout '$GSTUB/git.calls'" "no checkout after a failed fetch"

  # a failed fetch after init leaves no half-made .git, so the next run retries
  rm -f "$GSTUB"/git.*; write_marker; : >"$GSTUB/git.fetchfail"
  mk_stub git-init-mkdir "[ \"\$3\" = init ] && mkdir -p \"\$2/.git\"; exec \"$PROJECT_ROOT/tests/stubs/git\" \"\$@\""
  MACLIFT_GIT="$STUBS/git-init-mkdir"
  rc=0; out="$(bootstrap_git_clone 0 2>&1)" || rc=$?
  assert_equals "0" "$rc" "failed fetch after init: rc 0"
  assert_command_fails "[ -e '$MACLIFT_DIR/.git' ]" "failed fetch after init: no .git left"
  assert_command_succeeds "[ -e '$MACLIFT_DIR/.maclift-release' ]" "failed fetch after init: marker kept"
  rm -f "$GSTUB"/git.* "$MACLIFT_DIR/.maclift-release"
  unset MACLIFT_STUB_DIR MACLIFT_GIT
}

write_marker() {
  printf 'MACLIFT_RELEASE_REPO="makabde/maclift"\nMACLIFT_RELEASE_TAG="v1.0.0"\n' >"$MACLIFT_DIR/.maclift-release"
}

test_bootstrap
test_bootstrap_git_clone
test_summary
