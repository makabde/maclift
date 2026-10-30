#!/usr/bin/env bash
#
# maclift snapshot: finds installed Homebrew formulae, casks and Mac App Store
# apps that maclift does not know yet and saves the ones you pick to
# Brewfile.local. bash 3.2 compatible.
# Meant to be sourced after lib/catalog.sh, ui.sh, install.sh and localbrew.sh.

# snapshot_candidates
# Prints "id<TAB>name" lines, sorted, for installed packages that are neither
# in the catalog nor in Brewfile.local.
snapshot_candidates() {
  local brew="${MACLIFT_BREW:-brew}" mas="${MACLIFT_MAS:-mas}" id name line
  {
    "$brew" leaves --installed-on-request 2>/dev/null | while IFS= read -r name; do
      [ -n "$name" ] && printf 'brew:%s\t%s\n' "$name" "$name"
    done
    "$brew" list --cask 2>/dev/null | while IFS= read -r name; do
      [ -n "$name" ] && printf 'cask:%s\t%s\n' "$name" "$name"
    done
    if command -v "$mas" >/dev/null 2>&1; then
      "$mas" list 2>/dev/null | while IFS= read -r line; do
        id="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*([0-9]+).*/\1/')"
        case "$id" in '' | *[!0-9]*) continue ;; esac
        name="$(printf '%s\n' "$line" |
          sed -E -e 's/^[[:space:]]*[0-9]+[[:space:]]+//' -e 's/[[:space:]]+\([^)]*\)[[:space:]]*$//')"
        printf 'mas:%s\t%s\n' "$id" "$name"
      done
    else
      echo "note: mas not found, so App Store apps were not checked (brew install mas)" >&2
    fi
  } | LC_ALL=C sort | while IFS="	" read -r id name; do
    catalog_find "$id" && continue
    localbrew_has "$id" && continue
    printf '%s\t%s\n' "$id" "$name"
  done
}

# cmd_snapshot <dry_run:0|1>
# Offers the candidates (all preselected; -y takes them all) and saves the
# chosen ones to Brewfile.local.
cmd_snapshot() {
  local dry="$1" cands id name label chosen n=0 sel i skipped=0 lowcomma='‚'
  local labels=() ids=() names=() args=() pre="" file="$MACLIFT_CONFIG_DIR/Brewfile.local"
  cands="$(snapshot_candidates)"
  if [ -z "$cands" ]; then
    echo "Nothing to save: everything installed is already known to maclift."
    return 0
  fi
  while IFS="	" read -r id name; do
    case "$id" in
      mas:*)
        case "$name" in
          *'"'*)
            echo "warning: skipping $id: name contains a quote" >&2
            skipped=$((skipped + 1))
            continue
            ;;
        esac
        # gum's --selected list is comma-separated: show commas as U+201A
        # (looks the same, like _item_label); the choice maps back by position.
        label="$id  ${name//,/$lowcomma}"
        ;;
      *) label="$id" ;;
    esac
    labels+=("$label")
    ids+=("$id")
    names+=("$name")
    pre="${pre:+$pre,}$label"
  done <<EOF
$cands
EOF
  if [ "${#labels[@]}" -eq 0 ]; then
    echo "Nothing to save: skipped $skipped App Store app(s) whose name contains a quote, which Brewfile.local cannot hold. Add them by hand."
    return 0
  fi
  if [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; then
    chosen="$(printf '%s\n' "${labels[@]}")"
  else
    chosen="$(ui_choose_many "Save to Brewfile.local" "$pre" "${labels[@]}")"
  fi
  while IFS= read -r sel; do
    [ -n "$sel" ] || continue
    i=0
    while [ "$i" -lt "${#labels[@]}" ] && [ "${labels[$i]}" != "$sel" ]; do i=$((i + 1)); done
    [ "$i" -lt "${#labels[@]}" ] || continue
    args+=("$(localbrew_line "${ids[$i]}" "${names[$i]}")")
    n=$((n + 1))
  done <<EOF
$chosen
EOF
  if [ "$n" -eq 0 ]; then
    echo "Nothing saved."
    return 0
  fi
  localbrew_append "$dry" "added by maclift snapshot on $(date +%Y-%m-%d)" "${args[@]}"
  [ "$dry" = "1" ] || printf '✓ Saved %d package(s) to %s\n' "$n" "$file"
  return 0
}
