#!/usr/bin/env bash
#
# maclift catalog: reads catalog/*.tsv (group headers "@key value", then
# tab-separated items). Parsed with awk, never sourced. bash 3.2 compatible.
# Meant to be sourced after lib/core.sh (needs MACLIFT_DIR).

# Prints the catalog file path for a group id, or nothing.
_catalog_file_for_group() {
  local f
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    [ -e "$f" ] || continue
    if [ "$(_catalog_header "$f" id)" = "$1" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

# Value of "@key value" in a file (first match).
_catalog_header() {
  awk -v k="@$2" '{
    i = index($0, " ")
    if (i > 0 && substr($0, 1, i - 1) == k) { print substr($0, i + 1); exit }
  }' "$1"
}

# Prints group ids in display (file prefix) order.
catalog_groups() {
  local f
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    [ -e "$f" ] || continue
    _catalog_header "$f" id
  done
}

# catalog_group_field <group> <title|description|default|required>
catalog_group_field() {
  local f
  case "$2" in title | description | default | required) ;; *) return 1 ;; esac
  f="$(_catalog_file_for_group "$1")" || return 1
  _catalog_header "$f" "$2"
}

# catalog_items <group>: prints item ids (kind:name).
catalog_items() {
  local f
  f="$(_catalog_file_for_group "$1")" || return 1
  awk -F'\t' '/^@/ || /^#/ || NF < 4 { next } { print $1 ":" $2 }' "$f"
}

# catalog_item_field <id> <group|default|description|args>
catalog_item_field() {
  local id="$1" field="$2" f
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    [ -e "$f" ] || continue
    if awk -F'\t' -v id="$id" -v fld="$field" -v g="$(_catalog_header "$f" id)" '
      /^@/ || /^#/ || NF < 4 { next }
      $1 ":" $2 == id {
        if (fld == "group") print g
        else if (fld == "default") print $3
        else if (fld == "description") print $4
        else if (fld == "args") print $5
        found = 1; exit
      }
      END { exit(found ? 0 : 1) }' "$f"; then
      return 0
    fi
  done
  return 1
}

# catalog_table: every item in display order, one per line:
# "group<TAB>id<TAB>default<TAB>description". Two awk calls per file instead
# of one per item, for callers that need the whole catalog.
catalog_table() {
  local f
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    [ -e "$f" ] || continue
    awk -F'\t' -v g="$(_catalog_header "$f" id)" '
      /^@/ || /^#/ || NF < 4 { next }
      { print g "\t" $1 ":" $2 "\t" $3 "\t" $4 }' "$f"
  done
}

# catalog_find <id>: returns 0 if the item exists, else 1.
catalog_find() {
  local f
  for f in "$MACLIFT_DIR"/catalog/*.tsv; do
    [ -e "$f" ] || continue
    awk -F'\t' -v id="$1" '/^@/ || /^#/ || NF < 4 { next }
      $1 ":" $2 == id { found = 1; exit }
      END { exit(found ? 0 : 1) }' "$f" && return 0
  done
  return 1
}
