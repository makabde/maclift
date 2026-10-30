#!/usr/bin/env bash
#
# Unit tests for scripts/release/build-public-tree.sh. Each case runs the
# script from a tiny throwaway git repo built here (never this repo's history),
# with a temp HOME, no global git config and signing off for these tests only.
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"

T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home"

# Tests only: no global/system git config, commits unsigned.
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
unset MACLIFT_PRIVATE_PATTERNS
export MACLIFT_PRIVATE_PATTERNS_FILE="$T/no-patterns-file"

NAME="Ada Lovelace"
EMAIL="12345+ada@users.noreply.github.com"
RUN_OUT=""
RUN_RC=0

# make_src <dir>: a tiny clean repo with the script, the leak scan, VERSION,
# install and an ignored .superpowers/ dir. Prints nothing.
make_src() {
  local d="$1"
  mkdir -p "$d/scripts/release" "$d/tests/lib" "$d/lib" "$d/.superpowers"
  cp "$PROJECT_ROOT/scripts/release/build-public-tree.sh" "$d/scripts/release/"
  cp "$PROJECT_ROOT/tests/lib/leak-scan.sh" "$d/tests/lib/"
  echo 1.0.0 >"$d/VERSION"
  printf '#!/usr/bin/env bash\nMACLIFT_TAG="${MACLIFT_TAG:-v1.0.0}"\n' >"$d/install"
  printf 'hello\n' >"$d/lib/core.sh"
  printf '.superpowers/\n' >"$d/.gitignore"
  printf 'private notes\n' >"$d/.superpowers/notes.md"
  git -C "$d" init -q -b dev
  git -C "$d" add -A
  git -C "$d" -c user.name=Ada -c user.email=ada@example.com commit -q -m "dev history"
}

# run_build <src> <out> [env assignments...]: runs the script, sets RUN_OUT/RUN_RC.
run_build() {
  local src="$1" out="$2"
  shift 2
  RUN_RC=0
  RUN_OUT="$(env MACLIFT_PUBLIC_NAME="$NAME" MACLIFT_PUBLIC_EMAIL="$EMAIL" \
    MACLIFT_PRIVATE_PATTERNS=zzneverzz "$@" \
    bash "$src/scripts/release/build-public-tree.sh" "$out" 2>&1)" || RUN_RC=$?
}

test_usage() {
  test_suite "Usage and identity are checked first"
  local src="$T/usage-src"
  make_src "$src"
  RUN_RC=0
  RUN_OUT="$(bash "$src/scripts/release/build-public-tree.sh" 2>&1)" || RUN_RC=$?
  assert_equals "64" "$RUN_RC" "no out-dir argument is bad usage"
  run_build "$src" "$T/usage-out" MACLIFT_PUBLIC_NAME=
  assert_equals "64" "$RUN_RC" "empty MACLIFT_PUBLIC_NAME is bad usage"
  assert_contains "$RUN_OUT" "MACLIFT_PUBLIC_NAME" "says which variable is missing"
  assert_false "$([ -e "$T/usage-out" ] && echo made)" "no out-dir created"
}

test_refuses_non_noreply_email() {
  test_suite "Refuses an email that is not a GitHub noreply address"
  local src="$T/email-src"
  make_src "$src"
  run_build "$src" "$T/email-out" MACLIFT_PUBLIC_EMAIL=ada@example.com
  assert_equals "64" "$RUN_RC" "example.com email refused"
  assert_contains "$RUN_OUT" "users.noreply.github.com" "says which email is expected"
  run_build "$src" "$T/email-out" MACLIFT_PUBLIC_EMAIL="x@users.noreply.github.com"".evil.test"
  assert_equals "64" "$RUN_RC" "lookalike domain refused"
  run_build "$src" "$T/email-out" MACLIFT_PUBLIC_EMAIL=""
  assert_equals "64" "$RUN_RC" "empty email refused"
  assert_false "$([ -e "$T/email-out" ] && echo made)" "no out-dir created"
}

test_refuses_existing_out_dir() {
  test_suite "Refuses an existing out-dir and leaves it alone"
  local src="$T/exist-src" out="$T/exist-out"
  make_src "$src"
  mkdir -p "$out"
  printf 'keep\n' >"$out/mine.txt"
  run_build "$src" "$out"
  assert_equals "1" "$RUN_RC" "existing out-dir refused"
  assert_contains "$RUN_OUT" "already exists" "says why"
  assert_equals "keep" "$(cat "$out/mine.txt")" "existing content untouched"
  assert_false "$([ -e "$out/.git" ] && echo made)" "no repo created inside it"
  : >"$T/exist-file"
  run_build "$src" "$T/exist-file"
  assert_equals "1" "$RUN_RC" "existing file refused"
}

test_refuses_out_dir_inside_source() {
  test_suite "Refuses an out-dir inside the source repo"
  local src="$T/inside-src"
  make_src "$src"
  run_build "$src" "$src/public"
  assert_equals "1" "$RUN_RC" "out-dir inside the source refused"
  assert_false "$([ -e "$src/public" ] && echo made)" "nothing created"
}

test_refuses_dirty_tree() {
  test_suite "Refuses uncommitted changes to tracked files"
  local src="$T/dirty-src"
  make_src "$src"
  printf 'changed\n' >>"$src/lib/core.sh"
  run_build "$src" "$T/dirty-out"
  assert_equals "1" "$RUN_RC" "modified tracked file refused"
  assert_contains "$RUN_OUT" "uncommitted" "says why"
  assert_false "$([ -e "$T/dirty-out" ] && echo made)" "no out-dir created"
  git -C "$src" checkout -q -- lib/core.sh
  printf 'staged\n' >"$src/lib/new.sh"
  git -C "$src" add lib/new.sh
  run_build "$src" "$T/dirty-out"
  assert_equals "1" "$RUN_RC" "staged new file refused"
}

test_builds_one_commit() {
  test_suite "Builds one commit with the public identity"
  local src="$T/ok-src" out="$T/ok-out" log
  make_src "$src"
  printf 'scratch\n' >"$src/untracked.txt"
  run_build "$src" "$out"
  assert_equals "0" "$RUN_RC" "build succeeds"
  assert_contains "$RUN_OUT" "public tree ready: $out (1 commit, 6 files)" "ready line with commit and file count"
  assert_equals "1" "$(git -C "$out" rev-list --count HEAD)" "exactly one commit"
  assert_equals "main" "$(git -C "$out" branch --show-current)" "branch is main"
  assert_equals "maclift 1.0.0: initial release" "$(git -C "$out" log -1 --format=%s)" "commit subject"
  log="$(git -C "$out" log --format='%an|%ae|%cn|%ce')"
  assert_equals "$NAME|$EMAIL|$NAME|$EMAIL" "$log" "author and committer are the public identity"
  assert_equals "" "$(git -C "$out" remote)" "no remote"
  assert_equals "$(git -C "$src" rev-parse 'HEAD^{tree}')" "$(git -C "$out" rev-parse 'HEAD^{tree}')" \
    "tree is identical to the source HEAD tree"
  assert_false "$([ -e "$out/.superpowers" ] && echo leaked)" "ignored .superpowers/ not exported"
  assert_false "$([ -e "$out/untracked.txt" ] && echo leaked)" "untracked file not exported"
  assert_false "$([ -n "$(ls "$out/.git/hooks" 2>/dev/null)" ] && echo hooks)" "no template hooks in the new repo"
  assert_equals "" "$(git -C "$out" status --porcelain)" "out-dir work tree is clean"
  assert_equals "dev" "$(git -C "$src" branch --show-current)" "source branch untouched"
  assert_equals "1" "$(git -C "$src" rev-list --count HEAD)" "source history untouched"
}

test_version_drives_subject() {
  test_suite "Commit subject follows VERSION"
  local src="$T/ver-src" out="$T/ver-out"
  make_src "$src"
  echo 1.2.3 >"$src/VERSION"
  printf '#!/usr/bin/env bash\nMACLIFT_TAG="${MACLIFT_TAG:-v1.2.3}"\n' >"$src/install"
  git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -am "bump"
  run_build "$src" "$out"
  assert_equals "0" "$RUN_RC" "build succeeds"
  assert_equals "maclift 1.2.3: initial release" "$(git -C "$out" log -1 --format=%s)" "subject uses VERSION"
}

test_planted_leak_fails() {
  test_suite "An owner pattern hit fails the build"
  local src="$T/leak-src" out="$T/leak-out"
  make_src "$src"
  printf 'zzleakzz here\n' >"$src/lib/planted.sh"
  git -C "$src" add lib/planted.sh
  git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -m "plant"
  run_build "$src" "$out" MACLIFT_PRIVATE_PATTERNS=zzleakzz
  assert_equals "1" "$RUN_RC" "hit exits 1"
  assert_contains "$RUN_OUT" "lib/planted.sh:1:zzleakzz here" "prints the hit"
  assert_false "$([ -e "$out" ] && echo kept)" "failed out-dir removed"
}

test_generic_leak_fails() {
  test_suite "A generic hit fails the build"
  local src="$T/gen-src" out="$T/gen-out" addr
  make_src "$src"
  addr="$(printf '%s@%s' bob corp.test)"
  printf 'mail %s\n' "$addr" >"$src/lib/mail.sh"
  git -C "$src" add lib/mail.sh
  git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -m "mail"
  run_build "$src" "$out"
  assert_equals "1" "$RUN_RC" "generic hit exits 1"
  assert_contains "$RUN_OUT" "$addr" "prints the hit"
  assert_false "$([ -e "$out" ] && echo kept)" "failed out-dir removed"
}

test_no_patterns_refused() {
  test_suite "No owner patterns: refused, with how to provide them"
  local src="$T/nopat-src" out="$T/nopat-out"
  make_src "$src"
  RUN_RC=0
  RUN_OUT="$(env -u MACLIFT_PRIVATE_PATTERNS MACLIFT_PUBLIC_NAME="$NAME" MACLIFT_PUBLIC_EMAIL="$EMAIL" \
    bash "$src/scripts/release/build-public-tree.sh" "$out" 2>&1)" || RUN_RC=$?
  assert_equals "1" "$RUN_RC" "no patterns exits 1"
  assert_contains "$RUN_OUT" "MACLIFT_PRIVATE_PATTERNS" "names the variable"
  assert_contains "$RUN_OUT" "private-patterns" "names the file"
  assert_false "$([ -e "$out" ] && echo kept)" "failed out-dir removed"
  run_build "$src" "$out" MACLIFT_PRIVATE_PATTERNS=$'\n\n'
  assert_equals "1" "$RUN_RC" "blank-only patterns exit 1"
}

test_scan_error_fails() {
  test_suite "A scan error fails the build"
  local src="$T/err-src" out="$T/err-out"
  make_src "$src"
  run_build "$src" "$out" 'MACLIFT_PRIVATE_PATTERNS=(unclosed'
  assert_equals "1" "$RUN_RC" "bad regex exits 1"
  assert_contains "$RUN_OUT" "scan" "says the scan failed"
  assert_false "$([ -e "$out" ] && echo kept)" "failed out-dir removed"
}

test_tag_mismatch_fails() {
  test_suite "install's MACLIFT_TAG must equal v\$(cat VERSION)"
  local src="$T/tag-src" out="$T/tag-out"
  make_src "$src"
  echo 1.0.1 >"$src/VERSION"
  git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -am "bump only VERSION"
  run_build "$src" "$out"
  assert_equals "1" "$RUN_RC" "tag mismatch exits 1"
  assert_contains "$RUN_OUT" "v1.0.1" "names the expected tag"
  assert_false "$([ -e "$out" ] && echo kept)" "failed out-dir removed"
  printf '#!/usr/bin/env bash\necho no tag\n' >"$src/install"
  git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -am "drop tag"
  run_build "$src" "$out"
  assert_equals "1" "$RUN_RC" "missing MACLIFT_TAG exits 1"
}

test_excluded_files_scanned_for_owner_patterns() {
  test_suite "Owner patterns are also checked in the scan-excluded files"
  local src out
  for f in tests/lib/leak-scan.sh tests/unit/test_no_personal_data.sh; do
    src="$T/excl-src-${f##*/}"
    out="$T/excl-out-${f##*/}"
    make_src "$src"
    mkdir -p "$src/tests/unit"
    [ -f "$src/$f" ] || printf '#!/usr/bin/env bash\n' >"$src/$f"
    printf '# zzleakzz planted\n' >>"$src/$f"
    git -C "$src" add -A
    git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -m "plant in $f"
    run_build "$src" "$out" MACLIFT_PRIVATE_PATTERNS=zzleakzz
    assert_equals "1" "$RUN_RC" "hit in $f exits 1"
    assert_contains "$RUN_OUT" "$f:" "prints the hit in $f"
    assert_false "$([ -e "$out" ] && echo kept)" "failed out-dir removed ($f)"
  done
}

test_bad_version_fails() {
  test_suite "VERSION must be exactly x.y.z"
  local src="$T/badver-src" v
  make_src "$src"
  for v in 1 1.2 1.2.3.4 v1.2.3 1..3; do
    echo "$v" >"$src/VERSION"
    git -C "$src" -c user.name=Ada -c user.email=ada@example.com commit -q -am "version $v"
    run_build "$src" "$T/badver-out"
    assert_equals "1" "$RUN_RC" "VERSION '$v' refused"
    assert_false "$([ -e "$T/badver-out" ] && echo kept)" "failed out-dir removed ($v)"
  done
}

test_blank_name_refused() {
  test_suite "A name of only blanks is refused"
  local src="$T/blank-src"
  make_src "$src"
  run_build "$src" "$T/blank-out" "MACLIFT_PUBLIC_NAME=   "
  assert_equals "64" "$RUN_RC" "blank name is bad usage"
}

test_dirty_checked_before_sourcing() {
  test_suite "The dirty check runs before the leak scan is sourced"
  local src="$T/order-src"
  make_src "$src"
  rm "$src/tests/lib/leak-scan.sh"
  run_build "$src" "$T/order-out"
  assert_equals "1" "$RUN_RC" "dirty tree refused"
  assert_contains "$RUN_OUT" "uncommitted" "refused as dirty, not a source error"
}

test_interrupt_exits_130() {
  test_suite "An interrupt exits 130 and removes the out-dir"
  local src="$T/int-src" out="$T/int-out" stub="$T/int-stub"
  make_src "$src"
  mkdir -p "$stub"
  # tar is the last pipeline element, so its parent is the script's shell.
  printf '#!/bin/sh\ncat >/dev/null\nkill -TERM "$PPID"\nsleep 2\n' >"$stub/tar"
  chmod +x "$stub/tar"
  run_build "$src" "$out" PATH="$stub:$PATH"
  assert_equals "130" "$RUN_RC" "TERM exits 130"
  assert_false "$([ -e "$out" ] && echo kept)" "interrupted out-dir removed"
}

test_repo_release_files() {
  local v line
  v="$(tr -d '[:space:]' <"$PROJECT_ROOT/VERSION")"
  test_suite "install's MACLIFT_TAG follows VERSION ($v)"
  assert_not_equals "" "$v" "VERSION is set"
  line="$(grep -cxF "MACLIFT_TAG=\"\${MACLIFT_TAG:-v$v}\"" "$PROJECT_ROOT/install" || true)"
  assert_equals "1" "$line" "install defaults MACLIFT_TAG to v$v"
}

test_usage
test_refuses_non_noreply_email
test_refuses_existing_out_dir
test_refuses_out_dir_inside_source
test_refuses_dirty_tree
test_builds_one_commit
test_version_drives_subject
test_planted_leak_fails
test_generic_leak_fails
test_no_patterns_refused
test_scan_error_fails
test_tag_mismatch_fails
test_excluded_files_scanned_for_owner_patterns
test_bad_version_fails
test_blank_name_refused
test_dirty_checked_before_sourcing
test_interrupt_exits_130
test_repo_release_files
test_summary
