#!/usr/bin/env bash
#
# Leak scanning helpers. Standalone: no test-framework dependency, so both
# tests/unit/test_no_personal_data.sh and scripts/release/build-public-tree.sh
# can source it. Sourcing sets no shell options.
#
# Contract (all scan functions):
#   - hits are printed to stdout, one "file:line:text" per line
#   - return codes: 0 = scanned, no hits; 1 = at least one hit;
#     2 = error (bad regex, not a git work tree, missing dir; message on stderr);
#     3 = _scan_patterns only: no patterns configured, nothing was scanned
#     (message on stderr). Callers must NOT treat 3 as "clean".
#   - <dir> must be a git work tree; only tracked files are scanned
#   - tests/unit/test_no_personal_data.sh and this file are excluded, because
#     they necessarily contain the regexes
#
# _private_patterns        print the owner's deny-list, one ERE per line:
#                          1. $MACLIFT_PRIVATE_PATTERNS (newline separated)
#                          2. else ${MACLIFT_PRIVATE_PATTERNS_FILE:-$HOME/.config/maclift/private-patterns}
#                             ('#' comments and blank lines ignored)
#                          prints nothing when neither source exists
# _owner_patterns_missing_notice  print the "patterns not found" line
# _scan_patterns [dir]     scan dir (default $MACLIFT_SCAN_DIR) for those patterns
# _scan_generic [dir]      scan for non-allowed email domains (case-insensitive),
#                          private key headers and /Users/<name> paths (both
#                          case-sensitive)

_LEAK_EXCLUDES=(':!tests/unit/test_no_personal_data.sh' ':!tests/lib/leak-scan.sh')

_private_patterns() {
  local line file
  if [ -n "${MACLIFT_PRIVATE_PATTERNS:-}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] && printf '%s\n' "$line"
    done <<EOT
$MACLIFT_PRIVATE_PATTERNS
EOT
    return 0
  fi
  file="${MACLIFT_PRIVATE_PATTERNS_FILE:-$HOME/.config/maclift/private-patterns}"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    printf '%s\n' "$line"
  done <"$file"
}

_owner_patterns_missing_notice() {
  echo "owner patterns not found; only generic checks ran"
}

# _leak_grep <dir> <git grep args...>: prints matches; 0 = matches, 1 = none,
# 2 = git grep failed (stderr message).
_leak_grep() {
  local dir="$1" out rc=0
  shift
  out="$(git -C "$dir" grep "$@" 2>&1)" || rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    1) ;;
    *)
      printf 'leak-scan: git grep failed (%s) in %s: %s\n' "$rc" "$dir" "$out" >&2
      return 2
      ;;
  esac
  return "$rc"
}

_leak_check_dir() {
  if [ -z "$1" ] || ! git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'leak-scan: not a git work tree: %s\n' "$1" >&2
    return 2
  fi
}

_scan_patterns() {
  local dir="${1:-${MACLIFT_SCAN_DIR:-}}" pattern pats rc found=0 n=0
  _leak_check_dir "$dir" || return 2
  pats="$(_private_patterns)"
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    n=$((n + 1))
    rc=0
    _leak_grep "$dir" -n -i -E -e "$pattern" -- . "${_LEAK_EXCLUDES[@]}" || rc=$?
    case "$rc" in 0) found=1 ;; 1) ;; *) return 2 ;; esac
  done <<EOT
$pats
EOT
  if [ "$n" -eq 0 ]; then
    echo "leak-scan: no private patterns configured; nothing scanned" >&2
    return 3
  fi
  [ "$found" -eq 0 ]
}

_scan_generic() {
  local dir="${1:-${MACLIFT_SCAN_DIR:-}}" out emails rc found=0
  _leak_check_dir "$dir" || return 2
  rc=0
  emails="$(_leak_grep "$dir" -n -i -E -o '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' -- . "${_LEAK_EXCLUDES[@]}")" || rc=$?
  [ "$rc" -le 1 ] || return 2
  emails="$(printf '%s\n' "$emails" | grep -v -i -E '^$|@(example\.com|example\.org|users\.noreply\.github\.com|noreply\.anthropic\.com)$' || true)"
  rc=0
  out="$(_leak_grep "$dir" -n -E -e 'BEGIN [A-Z ]*PRIVATE KEY' -e '/Users/[a-z]' -- . "${_LEAK_EXCLUDES[@]}")" || rc=$?
  [ "$rc" -le 1 ] || return 2
  if [ -n "$emails" ]; then
    printf '%s\n' "$emails"
    found=1
  fi
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    found=1
  fi
  [ "$found" -eq 0 ]
}
