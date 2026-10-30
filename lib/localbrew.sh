#!/usr/bin/env bash
#
# Brewfile.local writer: builds and appends the lines that install_brewfile_local
# reads back ($MACLIFT_CONFIG_DIR/Brewfile.local). Used by `maclift add` and
# `maclift snapshot`. bash 3.2 compatible.
# Meant to be sourced after lib/core.sh and lib/install.sh.

# localbrew_line <id> [display-name]
# Prints brew "x", cask "x" or mas "Name", id: N. Returns 1 for other kinds.
localbrew_line() {
  local id="$1" name="${2:-}"
  case "$id" in
    brew:*) printf 'brew "%s"\n' "${id#brew:}" ;;
    cask:*) printf 'cask "%s"\n' "${id#cask:}" ;;
    mas:*) printf 'mas "%s", id: %s\n' "${name:-${id#mas:}}" "${id#mas:}" ;;
    *) return 1 ;;
  esac
}

# localbrew_has <id>: 0 if Brewfile.local already lists the id.
localbrew_has() {
  local ids
  ids="$(install_brewfile_local 2>/dev/null)"
  case "
$ids
" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

# localbrew_append <dry_run:0|1> <comment> <line>...
# Appends "# <comment>" and the lines, creating the file if needed. A missing
# final newline is added first. Dry run only prints what would be added.
localbrew_append() {
  local dry="$1" comment="$2" file="$MACLIFT_CONFIG_DIR/Brewfile.local" line
  shift 2
  if [ "$dry" = "1" ]; then
    for line in "$@"; do printf 'would add to %s: %s\n' "$file" "$line"; done
    return 0
  fi
  mkdir -p "$MACLIFT_CONFIG_DIR"
  {
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n'; fi
    printf '# %s\n' "$comment"
    for line in "$@"; do printf '%s\n' "$line"; done
  } >>"$file"
}
