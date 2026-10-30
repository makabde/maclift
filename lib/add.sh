#!/usr/bin/env bash
#
# maclift add: installs Homebrew formulae and casks by name and remembers them
# (in the selection for catalog items, in Brewfile.local for everything else).
# bash 3.2 compatible.
# Meant to be sourced after lib/catalog.sh, selection.sh, ui.sh, install.sh and
# localbrew.sh.

# add_resolve <arg>
# Prints an id and returns 0, or prints a message on stderr and returns
# 1 (not found), 2 (ambiguous) or 3 (invalid name).
add_resolve() {
  local arg="$1" name kind="" formula=0 cask=0
  local valid='^[A-Za-z0-9][A-Za-z0-9@._+/-]*$'
  # One brew: or cask: prefix, never two.
  case "$arg" in
    brew:* | cask:*) name="${arg#*:}" ;;
    *) name="$arg" ;;
  esac
  case "$name" in
    brew:* | cask:*)
      echo "maclift add: $arg has two prefixes; use one: brew:<name> or cask:<name>" >&2
      return 3
      ;;
  esac
  # whole-string match: a newline in the name must not pass
  if ! [[ $name =~ $valid ]]; then
    echo "maclift add: invalid package name: $arg" >&2
    return 3
  fi
  case "$arg" in
    brew:* | cask:*)
      printf '%s\n' "$arg"
      return 0
      ;;
  esac
  for kind in brew cask; do
    if catalog_find "$kind:$name"; then
      printf '%s:%s\n' "$kind" "$name"
      return 0
    fi
  done
  "${MACLIFT_BREW:-brew}" info --formula -- "$name" >/dev/null 2>&1 && formula=1
  "${MACLIFT_BREW:-brew}" info --cask -- "$name" >/dev/null 2>&1 && cask=1
  if [ "$formula" = 1 ] && [ "$cask" = 1 ]; then
    echo "$name is both a formula and a cask: use brew:$name or cask:$name" >&2
    return 2
  fi
  if [ "$formula" = 1 ]; then
    printf 'brew:%s\n' "$name"
  elif [ "$cask" = 1 ]; then
    printf 'cask:%s\n' "$name"
  else
    echo "no Homebrew formula or cask named $name" >&2
    return 1
  fi
}

# cmd_add <dry_run:0|1> <name>...
# Returns 1 if any argument failed to resolve or install; keeps going.
cmd_add() {
  local dry="$1" arg id rc=0
  shift
  for arg in "$@"; do
    id="$(add_resolve "$arg")" || {
      rc=1
      continue
    }
    if catalog_find "$id"; then
      # shellcheck disable=SC2046 # ids never contain spaces
      if selection_save $(selection_load) "$id"; then
        printf '✓ %s is in the catalog: added to your selection\n' "$id"
      else
        printf '✗ %s is in the catalog, but your selection could not be saved\n' "$id"
        rc=1
      fi
      install_run "$dry" "$id" || rc=1
    else
      MACLIFT_EXTRA_IDS="${MACLIFT_EXTRA_IDS:+$MACLIFT_EXTRA_IDS
}$id"
      install_run "$dry" "$id" || rc=1
      case " $MACLIFT_FAILED " in *" $id "*) continue ;; esac
      localbrew_has "$id" ||
        localbrew_append "$dry" "added by maclift add" "$(localbrew_line "$id")"
    fi
  done
  return "$rc"
}
