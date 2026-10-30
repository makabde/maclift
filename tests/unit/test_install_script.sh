#!/usr/bin/env bash
#
# Unit tests for the one-line installer (./install). Stubs only: a temp HOME,
# a temp MACLIFT_DIR and the curl stub; never the network.
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
STUB="$T/stub"
mkdir -p "$STUB" "$T/home"

# A tiny release tarball: maclift-1.0.0/{maclift,VERSION}. The fake maclift
# records its arguments.
mkdir -p "$T/src/maclift-1.0.0"
cat >"$T/src/maclift-1.0.0/maclift" <<'EOT'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$MACLIFT_STUB_DIR/maclift.args"
EOT
echo 1.0.0 >"$T/src/maclift-1.0.0/VERSION"
tar -czf "$STUB/release.tar.gz" -C "$T/src" maclift-1.0.0

export HOME="$T/home" MACLIFT_STUB_DIR="$STUB" MACLIFT_CURL="$PROJECT_ROOT/tests/stubs/curl"
export MACLIFT_UNAME=Darwin MACLIFT_TTY=/dev/null
# The installer's temporary folder must not land here: it goes next to the
# target folder (checked by tmp_left).
mkdir -p "$T/tmp"
export TMPDIR="$T/tmp"
unset MACLIFT_REPO MACLIFT_TAG

reset() {
  rm -rf "$T/home/maclift" "$T/other"
  rm -f "$STUB/curl.calls" "$STUB/curl.fail" "$STUB/maclift.args"
}

# Leftover temporary folders: in TMPDIR, or next to the default target.
tmp_left() {
  ls -A "$T/tmp"
  (cd "$T/home" && ls -d .maclift-install.* 2>/dev/null) || true
}

run_install() { bash "$PROJECT_ROOT/install" "$@" 2>&1; }

test_install_fresh() {
  test_suite "install: fresh"
  local out rc dir="$T/home/maclift"
  reset
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_equals "0" "$rc" "fresh install succeeds"
  assert_file_exists "$dir/maclift" "maclift unpacked into MACLIFT_DIR"
  assert_file_exists "$dir/VERSION" "VERSION unpacked"
  assert_equals 'MACLIFT_RELEASE_REPO="makabde/maclift"
MACLIFT_RELEASE_TAG="v'"$(cat "$PROJECT_ROOT/VERSION")"'"' "$(cat "$dir/.maclift-release")" "marker names repo and tag"
  assert_equals "-y" "$(cat "$STUB/maclift.args" 2>/dev/null)" "maclift ran with the given args"
  assert_equals "-fsSL -o" "$(cut -d' ' -f1-2 "$STUB/curl.calls")" "curl -fsSL"
  assert_contains "$(cat "$STUB/curl.calls")" "https://github.com/makabde/maclift/archive/refs/tags/v$(cat "$PROJECT_ROOT/VERSION").tar.gz" "downloads the tagged release"
  assert_equals "" "$(tmp_left)" "temporary folder removed"
  local where
  where="$(cut -d' ' -f3 "$STUB/curl.calls")"
  case "$where" in "$T/home/.maclift-install."*/release.tar.gz) where=next-to-target ;; esac
  assert_equals "next-to-target" "$where" "temporary folder is next to the target"

  # Piped, as in curl … | bash -s -- -y.
  reset
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=0 bash -s -- -y <"$PROJECT_ROOT/install" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "piped run succeeds"
  assert_equals "-y" "$(cat "$STUB/maclift.args" 2>/dev/null)" "piped run passes the args"

  # Default folder is ~/maclift (HOME is a temp dir here).
  reset
  rc=0; out="$(MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_equals "0" "$rc" "default folder: succeeds"
  assert_file_exists "$T/home/maclift/maclift" "default folder is ~/maclift"
}

test_install_existing_dir() {
  test_suite "install: existing folder"
  local out rc dir="$T/other"
  reset
  mkdir -p "$dir"; echo keep >"$dir/notes.txt"
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_equals "1" "$rc" "unrelated folder fails"
  assert_contains "$out" "$dir already exists and isn't maclift; move it or set MACLIFT_DIR" "says what to do"
  assert_equals "notes.txt" "$(ls -A "$dir")" "folder content unchanged"
  assert_equals "keep" "$(cat "$dir/notes.txt")" "file content unchanged"
  assert_command_fails "[ -e '$STUB/curl.calls' ]" "no download"
}

test_install_reuse() {
  test_suite "install: reuse"
  local out rc dir="$T/home/maclift"
  reset
  mkdir -p "$dir"; cp "$T/src/maclift-1.0.0/maclift" "$T/src/maclift-1.0.0/VERSION" "$dir/"
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y --dry-run)" || rc=$?
  assert_equals "0" "$rc" "reuse succeeds"
  assert_command_fails "[ -e '$STUB/curl.calls' ]" "no curl call"
  assert_command_fails "[ -e '$dir/.maclift-release' ]" "no marker written on reuse"
  assert_equals "-y --dry-run" "$(cat "$STUB/maclift.args" 2>/dev/null)" "maclift ran with the given args"
}

test_install_bad_tarball() {
  test_suite "install: failed download"
  local out rc dir="$T/home/maclift"
  reset
  : >"$STUB/curl.fail"
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_not_equals "0" "$rc" "failed download fails"
  assert_command_fails "[ -e '$dir' ]" "folder absent after a failed download"
  assert_equals "" "$(tmp_left)" "temporary folder removed after a failed download"
  assert_command_fails "[ -e '$STUB/maclift.args' ]" "maclift not run"

  # A tarball without maclift in its top folder.
  reset
  mkdir -p "$T/bad/x"; echo hi >"$T/bad/x/README"
  cp "$STUB/release.tar.gz" "$T/good.tar.gz"
  tar -czf "$STUB/release.tar.gz" -C "$T/bad" x
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  cp "$T/good.tar.gz" "$STUB/release.tar.gz"
  assert_not_equals "0" "$rc" "tarball without maclift fails"
  assert_command_fails "[ -e '$dir' ]" "folder absent after a bad tarball"
  assert_equals "" "$(tmp_left)" "temporary folder removed after a bad tarball"

  # Not a tarball at all.
  reset
  echo "<html>not found</html>" >"$T/junk"
  cp "$T/junk" "$STUB/release.tar.gz"
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  cp "$T/good.tar.gz" "$STUB/release.tar.gz"
  assert_not_equals "0" "$rc" "junk download fails"
  assert_command_fails "[ -e '$dir' ]" "folder absent after a junk download"
}

test_install_no_tty() {
  test_suite "install: no terminal"
  local out rc dir="$T/home/maclift"
  reset
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=0 run_install)" || rc=$?
  assert_equals "1" "$rc" "no terminal without -y fails"
  assert_contains "$out" "no terminal: run it from Terminal, or add -y to reuse saved answers" "says what to do"
  assert_command_fails "[ -e '$STUB/maclift.args' ]" "maclift not run"
  assert_command_fails "[ -e '$dir' ]" "refused before creating the folder"
  assert_command_fails "[ -e '$STUB/curl.calls' ]" "refused before downloading"

  reset
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=0 run_install --yes)" || rc=$?
  assert_equals "0" "$rc" "no terminal with --yes runs"
  assert_equals "--yes" "$(cat "$STUB/maclift.args" 2>/dev/null)" "maclift ran with --yes"
}

test_install_marker_before_move() {
  test_suite "install: marker written before the move"
  local out rc dir="$T/home/maclift"
  reset
  # An mv that records whether the folder it moves already has the marker.
  mkdir -p "$T/bin"
  cat >"$T/bin/mv" <<EOT
#!/bin/bash
if [ -f "\$1/.maclift-release" ]; then echo yes >"$STUB/mv.marker"; else echo no >"$STUB/mv.marker"; fi
exec /bin/mv "\$@"
EOT
  chmod +x "$T/bin/mv"
  rm -f "$STUB/mv.marker"
  rc=0; out="$(PATH="$T/bin:$PATH" MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_equals "0" "$rc" "install succeeds"
  assert_equals "yes" "$(cat "$STUB/mv.marker" 2>/dev/null)" "marker is in the folder before it is moved"
  assert_file_exists "$dir/.maclift-release" "marker in the final folder"
  rm -rf "${T:?}/bin" "$STUB/mv.marker"
}

test_install_not_macos() {
  test_suite "install: not macOS"
  local out rc dir="$T/home/maclift"
  reset
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_UNAME=Linux MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_equals "1" "$rc" "Linux is refused"
  assert_contains "$out" "maclift is for macOS" "says why"
  assert_command_fails "[ -e '$dir' ]" "nothing created"
  assert_command_fails "[ -e '$STUB/curl.calls' ]" "no download"
}

test_install_parent_cleanup() {
  test_suite "install: parents removed after a failed download"
  local out rc dir="$T/other/a/b/maclift"
  reset
  : >"$STUB/curl.fail"
  rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_not_equals "0" "$rc" "failed download fails"
  assert_command_fails "[ -e '$T/other' ]" "created parents removed"
  # A parent that already existed is kept.
  mkdir -p "$T/other/keep"
  rc=0; out="$(MACLIFT_DIR="$T/other/keep/x/maclift" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_not_equals "0" "$rc" "failed download fails (existing parent)"
  assert_dir_exists "$T/other/keep" "existing parent kept"
  assert_command_fails "[ -e '$T/other/keep/x' ]" "only the new parent removed"
}

test_install_signal() {
  test_suite "install: interrupted download"
  local out rc sig dir="$T/other/a/maclift"
  for sig in TERM HUP INT; do
    reset
    echo "$sig" >"$STUB/curl.signal"
    rc=0; out="$(MACLIFT_DIR="$dir" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
    rm -f "$STUB/curl.signal"
    assert_equals "130" "$rc" "$sig: exits 130"
    assert_command_fails "[ -e '$T/other' ]" "$sig: nothing left (temp folder, parents)"
    assert_command_fails "[ -e '$STUB/maclift.args' ]" "$sig: maclift not run"
  done
}

test_install_partial_mkdir() {
  test_suite "install: parents removed when mkdir stops partway"
  local out rc long
  reset
  long="$(printf 'n%.0s' $(seq 1 300))"
  rc=0; out="$(MACLIFT_DIR="$T/other/a/$long/maclift" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
  assert_not_equals "0" "$rc" "a name too long fails"
  assert_command_fails "[ -e '$T/other' ]" "the parents mkdir made are removed"
}

test_install_dot_parts() {
  test_suite "install: MACLIFT_DIR with . or .. parts"
  local out rc d
  for d in "$T/other/new/../keep/maclift" "$T/other/new/./maclift" "$T/other/keep/.."; do
    reset
    mkdir -p "$T/other/keep"
    rc=0; out="$(MACLIFT_DIR="$d" MACLIFT_HAS_TTY=1 run_install -y)" || rc=$?
    assert_equals "1" "$rc" "$d: refused"
    assert_contains "$out" "MACLIFT_DIR can't contain . or .. parts" "$d: says why"
    assert_dir_exists "$T/other/keep" "$d: existing folder kept"
    assert_command_fails "[ -e '$T/other/new' ]" "$d: nothing created"
    assert_equals "" "$(cat "$STUB/curl.calls" 2>/dev/null)" "$d: nothing downloaded"
  done
}

test_install_fresh
test_install_existing_dir
test_install_reuse
test_install_bad_tarball
test_install_no_tty
test_install_marker_before_move
test_install_not_macos
test_install_parent_cleanup
test_install_signal
test_install_partial_mkdir
test_install_dot_parts
test_summary
