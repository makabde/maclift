#!/usr/bin/env bash
#
# For the initial public release (v1.0.0) ONLY. After v1.0.0, public `main`
# moves only by normal fast-forward commits: never rebuild it with this script
# and never force-push it. Installed copies run `maclift update`, which follows
# `main` (not tags) with pull --ff-only, so `main` must always be releasable.
# New releases are tagged commits on `main`; bump VERSION and the MACLIFT_TAG
# default in `install` together. See CONTRIBUTING.md, "Releases".
#
# Build the one-commit public tree of maclift, locally. Never pushes and never
# touches a remote: the new repo in <out-dir> has none.
#
#   MACLIFT_PUBLIC_NAME="Ada Lovelace" \
#   MACLIFT_PUBLIC_EMAIL="12345+ada@users.noreply.github.com" \
#     scripts/release/build-public-tree.sh <out-dir>
#
# Source: the HEAD commit of the repo this script lives in (git archive HEAD,
# so only tracked, committed files). Fails closed: any failed check exits 1
# and removes the out-dir it created. Exit codes: 0 ready, 1 refused or a
# check failed, 64 bad usage.
#
# The commit uses the caller's git config, so it is GPG-signed when
# commit.gpgsign is set. Signing is neither forced on nor off here.
#
# Owner deny-list: MACLIFT_PRIVATE_PATTERNS (newline-separated EREs) or
# ${MACLIFT_PRIVATE_PATTERNS_FILE:-~/.config/maclift/private-patterns}.
# Without one, the release is refused.

set -euo pipefail

# Git must work on the repos named below, not on one picked up from the env.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

_rel_die() {
  local code="$1"
  shift
  printf 'build-public-tree: %s\n' "$*" >&2
  exit "$code"
}

_rel_usage() {
  _rel_die 64 "usage: MACLIFT_PUBLIC_NAME=... MACLIFT_PUBLIC_EMAIL=<id>+<login>@users.noreply.github.com $0 <out-dir>"
}

[ "$#" -eq 1 ] && [ -n "$1" ] || _rel_usage
OUT_ARG="$1"

PUBLIC_NAME="${MACLIFT_PUBLIC_NAME:-}"
PUBLIC_EMAIL="${MACLIFT_PUBLIC_EMAIL:-}"
case "$PUBLIC_NAME" in
  *[![:space:]]*) ;;
  *) _rel_die 64 "MACLIFT_PUBLIC_NAME is not set (or only blanks)" ;;
esac
case "$PUBLIC_NAME" in
  *[[:cntrl:]]* | *'<'* | *'>'*) _rel_die 64 "MACLIFT_PUBLIC_NAME has a control character or <>" ;;
esac
case "$PUBLIC_EMAIL" in
  *[!A-Za-z0-9._+-]*@users.noreply.github.com | @users.noreply.github.com | '')
    _rel_die 64 "MACLIFT_PUBLIC_EMAIL must be <id>+<login>@users.noreply.github.com (got '${PUBLIC_EMAIL}')"
    ;;
  *@users.noreply.github.com) ;;
  *) _rel_die 64 "MACLIFT_PUBLIC_EMAIL must end in @users.noreply.github.com (got '${PUBLIC_EMAIL}')" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
  _rel_die 1 "not inside a git work tree: $SCRIPT_DIR"
SRC="$(cd "$SRC" && pwd -P)"

# --- out-dir: must not exist, parent must, and it must sit outside the source.
if [ -e "$OUT_ARG" ] || [ -L "$OUT_ARG" ]; then
  _rel_die 1 "out-dir already exists: $OUT_ARG"
fi
OUT_PARENT="$(cd "$(dirname "$OUT_ARG")" 2>/dev/null && pwd -P)" ||
  _rel_die 1 "parent of out-dir does not exist: $(dirname "$OUT_ARG")"
OUT="$OUT_PARENT/$(basename "$OUT_ARG")"
case "$OUT/" in
  "$SRC"/*) _rel_die 1 "out-dir must be outside the source repo ($SRC): $OUT" ;;
esac

# --- source: a commit, no uncommitted changes to tracked files.
git -C "$SRC" rev-parse --verify -q 'HEAD^{commit}' >/dev/null ||
  _rel_die 1 "source repo has no HEAD commit: $SRC"
DIRTY="$(git -C "$SRC" status --porcelain --untracked-files=no)" ||
  _rel_die 1 "git status failed in $SRC"
[ -z "$DIRTY" ] || _rel_die 1 "uncommitted changes to tracked files in $SRC:
$DIRTY"
SRC_TREE="$(git -C "$SRC" rev-parse 'HEAD^{tree}')"

# shellcheck source=tests/lib/leak-scan.sh
source "$SRC/tests/lib/leak-scan.sh"

# --- build. From here on a failure removes the out-dir this run created.
CREATED=""
READY=""
_rel_cleanup() {
  if [ -z "$READY" ] && [ -n "$CREATED" ] && [ -d "$CREATED" ]; then
    rm -rf -- "$CREATED"
    printf 'build-public-tree: removed %s (not ready)\n' "$CREATED" >&2
  fi
}
trap _rel_cleanup EXIT
trap 'exit 130' INT TERM

mkdir -- "$OUT" || _rel_die 1 "cannot create out-dir: $OUT"
CREATED="$OUT"

git -C "$SRC" archive HEAD | tar -x -C "$OUT" || _rel_die 1 "git archive HEAD | tar -x failed"

VERSION="$(cat "$OUT/VERSION" 2>/dev/null)" || _rel_die 1 "VERSION missing from HEAD"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _rel_die 1 "VERSION is not x.y.z: '$VERSION'"

# Fresh repo with no template (no hooks, no info/exclude); -f because every
# file here came from the archive, so none may be skipped by a .gitignore.
git init -q -b main --template= "$OUT" || _rel_die 1 "git init failed in $OUT"
git -C "$OUT" add -A -f . || _rel_die 1 "git add failed in $OUT"
SUBJECT="maclift $VERSION: initial release"
GIT_AUTHOR_NAME="$PUBLIC_NAME" GIT_AUTHOR_EMAIL="$PUBLIC_EMAIL" \
  GIT_COMMITTER_NAME="$PUBLIC_NAME" GIT_COMMITTER_EMAIL="$PUBLIC_EMAIL" \
  git -C "$OUT" commit -q -m "$SUBJECT" || _rel_die 1 "git commit failed in $OUT (signing?)"

# --- checks. Each failure prints why and exits 1.
FAIL=0
_rel_fail() {
  printf 'build-public-tree: FAIL: %s\n' "$*" >&2
  FAIL=1
}

COUNT="$(git -C "$OUT" rev-list --count HEAD)"
[ "$COUNT" = 1 ] || _rel_fail "expected 1 commit, found $COUNT"
GOT_SUBJECT="$(git -C "$OUT" log -1 --format=%s)"
[ "$GOT_SUBJECT" = "$SUBJECT" ] || _rel_fail "commit subject is '$GOT_SUBJECT', expected '$SUBJECT'"
GOT_BODY="$(git -C "$OUT" log -1 --format=%b)"
[ -z "$GOT_BODY" ] || _rel_fail "commit has an unexpected body: $GOT_BODY"
IDENT="$(git -C "$OUT" log --format='%an%n%ae%n%cn%n%ce')"
WANT="$(printf '%s\n%s\n%s\n%s' "$PUBLIC_NAME" "$PUBLIC_EMAIL" "$PUBLIC_NAME" "$PUBLIC_EMAIL")"
[ "$IDENT" = "$WANT" ] || _rel_fail "git log identity is not only the public one:
$IDENT"
REMOTES="$(git -C "$OUT" remote)"
[ -z "$REMOTES" ] || _rel_fail "out-dir repo has remotes: $REMOTES"
OUT_TREE="$(git -C "$OUT" rev-parse 'HEAD^{tree}')"
[ "$OUT_TREE" = "$SRC_TREE" ] || _rel_fail "public tree $OUT_TREE differs from source HEAD tree $SRC_TREE"
LEFTOVER="$(git -C "$OUT" status --porcelain --ignored)"
[ -z "$LEFTOVER" ] || _rel_fail "out-dir has files outside the commit:
$LEFTOVER"

# The tag the one-liner downloads must be this version's.
TAG_LINES="$(sed -n 's/^MACLIFT_TAG="\${MACLIFT_TAG:-\(.*\)}"$/\1/p' "$OUT/install" 2>/dev/null || true)"
if [ "$TAG_LINES" != "v$VERSION" ]; then
  _rel_fail "install's MACLIFT_TAG default is '${TAG_LINES:-<none>}', expected v$VERSION"
fi

# Leak scans: 0 clean; 1 hits; 2 error; 3 (owner scan) no patterns configured.
HITS=""
RC=0
HITS="$(_scan_patterns "$OUT")" || RC=$?
case "$RC" in
  0) ;;
  1) _rel_fail "owner pattern hits:
$HITS" ;;
  3) _rel_fail "no owner patterns configured, so nothing was scanned; refusing to release. Set MACLIFT_PRIVATE_PATTERNS (newline-separated EREs) or put one ERE per line in ~/.config/maclift/private-patterns (or the file named by MACLIFT_PRIVATE_PATTERNS_FILE)" ;;
  *) _rel_fail "owner pattern scan failed (rc $RC)" ;;
esac
RC=0
HITS="$(_scan_generic "$OUT")" || RC=$?
case "$RC" in
  0) ;;
  1) _rel_fail "generic leak hits:
$HITS" ;;
  *) _rel_fail "generic leak scan failed (rc $RC)" ;;
esac

# The scans above skip the files in _LEAK_EXCLUDES (they hold the generic
# regexes), but those files ship too. Owner patterns come only from the env or
# the patterns file, so they never belong in them: scan them with no excludes.
EXCLUDED=()
for spec in "${_LEAK_EXCLUDES[@]}"; do
  EXCLUDED+=("${spec#:!}")
done
PATS="$(_private_patterns)"
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  RC=0
  HITS="$(git -C "$OUT" grep -n -i -E -e "$pat" -- "${EXCLUDED[@]}" 2>&1)" || RC=$?
  case "$RC" in
    0) _rel_fail "owner pattern hits in scan-excluded files:
$HITS" ;;
    1) ;;
    *) _rel_fail "owner pattern scan of scan-excluded files failed (rc $RC): $HITS" ;;
  esac
done <<EOT
$PATS
EOT

[ "$FAIL" -eq 0 ] || exit 1

FILES="$(git -C "$OUT" ls-files | wc -l | tr -d ' ')"
READY=1
echo "public tree ready: $OUT (1 commit, $FILES files)"
