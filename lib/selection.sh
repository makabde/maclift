#!/usr/bin/env bash
#
# maclift selection: which catalog items are chosen. Stored in
# $MACLIFT_CONFIG_DIR/selection.conf (MACLIFT_GROUPS, MACLIFT_ITEMS), parsed
# with conf_get, never sourced. bash 3.2 compatible.
# Meant to be sourced after lib/core.sh, lib/conf.sh and lib/catalog.sh.

_selection_file() {
  printf '%s\n' "$MACLIFT_CONFIG_DIR/selection.conf"
}

# Items of groups with @required yes, one per line.
_selection_required() {
  local g
  for g in $(catalog_groups); do
    if [ "$(catalog_group_field "$g" required)" = yes ]; then
      catalog_items "$g"
    fi
  done
}

# Prints default item ids: default-on items of default-on groups, plus all
# items of required groups.
selection_defaults() {
  local g req def table grp id idef rest tab
  tab="$(printf '\t')"
  table="$(catalog_table)"
  for g in $(catalog_groups); do
    req="$(catalog_group_field "$g" required)"
    def="$(catalog_group_field "$g" default)"
    while IFS="$tab" read -r grp id idef rest; do
      [ "$grp" = "$g" ] || continue
      if [ "$req" = yes ]; then
        printf '%s\n' "$id"
      elif [ "$def" = on ] && [ "$idef" = on ]; then
        printf '%s\n' "$id"
      fi
    done <<EOT
$table
EOT
  done
}

# Prints saved item ids one per line (required items always included, like
# selection_save does); defaults when nothing is saved.
selection_load() {
  local items arr id seen=" "
  if items="$(conf_get "$(_selection_file)" MACLIFT_ITEMS 2>/dev/null)"; then
    read -r -a arr <<<"$items"
    for id in ${arr[@]+"${arr[@]}"} $(_selection_required); do
      case "$seen" in *" $id "*) continue ;; esac
      seen="$seen$id "
      printf '%s\n' "$id"
    done
  else
    selection_defaults
  fi
}

# selection_save <ids...>: adds required items, writes groups and items. It
# does not touch MACLIFT_SEEN: only the main flow and selection_import, which
# show the user the whole catalog, call selection_mark_seen after saving.
selection_save() {
  local id g items="" groups="" seen=" "
  for id in "$@" $(_selection_required); do
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    items="$items $id"
  done
  items="${items# }"
  for g in $(catalog_groups); do
    for id in $(catalog_items "$g"); do
      case " $items " in
        *" $id "*)
          groups="$groups $g"
          break
          ;;
      esac
    done
  done
  groups="${groups# }"
  conf_set "$(_selection_file)" MACLIFT_GROUPS "$groups" || return 1
  conf_set "$(_selection_file)" MACLIFT_ITEMS "$items" || return 1
}

# Items added to the catalog after 1.0.0 (asdf:python and brew:xz were removed
# from it and are simply unknown ids now). A saved selection without
# MACLIFT_SEEN predates them, so its baseline is every other catalog id.
SELECTION_ADDED_SINCE_1_0="brew:pnpm brew:rebar3 script:hex script:rebar script:phx_new script:python"

# Sets MACLIFT_SEEN to all current catalog ids.
selection_mark_seen() {
  local ids
  ids="$(catalog_table | cut -f2 | tr '\n' ' ')"
  conf_set "$(_selection_file)" MACLIFT_SEEN "${ids% }"
}

# Prints default-on ids a saved selection has not been offered yet (nothing
# when no selection is saved). Only ids in the current catalog.
selection_new_defaults() {
  local saved seen id groups="" g
  saved="$(conf_get "$(_selection_file)" MACLIFT_ITEMS 2>/dev/null)" || return 0
  if seen="$(conf_get "$(_selection_file)" MACLIFT_SEEN 2>/dev/null)"; then
    :
  else
    seen="$(catalog_table | cut -f2 | tr '\n' ' ')"
    for id in $SELECTION_ADDED_SINCE_1_0; do
      seen=" $seen "
      seen="${seen/ $id / }"
    done
  fi
  seen=" $seen "
  saved=" $saved "
  # A group switched off as a whole stays off.
  groups="$(conf_get "$(_selection_file)" MACLIFT_GROUPS 2>/dev/null)" && groups=" $groups " || groups=""
  for id in $(selection_defaults); do
    if [ -n "$groups" ]; then
      g="$(catalog_item_field "$id" group 2>/dev/null)" || g=""
      case "$groups" in *" $g "*) ;; *) continue ;; esac
    fi
    case "$seen" in *" $id "*) continue ;; esac
    case "$saved" in *" $id "*) continue ;; esac
    printf '%s\n' "$id"
  done
}

# selection_import <path|url>: loads a shared selection file safely.
selection_import() {
  local src="$1" file tmp="" items id keep="" rc=0 arr
  case "$src" in
    http://* | https://*)
      tmp="$(mktemp)" || return 1
      if ! "${MACLIFT_CURL:-curl}" -fsSL -o "$tmp" "$src"; then
        rm -f "$tmp"
        echo "maclift: could not download $src" >&2
        return 1
      fi
      file="$tmp"
      ;;
    *) file="$src" ;;
  esac
  if [ ! -f "$file" ]; then
    echo "maclift: no such file: $src" >&2
    return 1
  fi
  items="$(conf_get "$file" MACLIFT_ITEMS)" || rc=$?
  [ -z "$tmp" ] || rm -f "$tmp"
  if [ "$rc" != 0 ]; then
    echo "maclift: $src has no MACLIFT_ITEMS" >&2
    return 1
  fi
  read -r -a arr <<<"$items" # splits without globbing
  for id in ${arr[@]+"${arr[@]}"}; do
    case "$id" in
      script:*) echo "maclift: skipped $id (not in catalog)" >&2 ;;
      *)
        if catalog_find "$id"; then
          keep="$keep $id"
        else
          echo "maclift: skipped $id (not in catalog)" >&2
        fi
        ;;
    esac
  done
  # shellcheck disable=SC2086
  selection_save $keep || return 1
  selection_mark_seen
}
