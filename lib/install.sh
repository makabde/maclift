#!/usr/bin/env bash
#
# maclift install runner: installs items one by one with a status line each,
# skips what is already there, supports --dry-run, and logs all command
# output to $MACLIFT_CONFIG_DIR/logs/<run-id>.log. A failing item never stops
# the run. bash 3.2 compatible. Meant to be sourced after lib/core.sh,
# lib/catalog.sh, lib/ui.sh, lib/dotfiles.sh and lib/asdf.sh.

# Space-separated ids that failed in the last install_run (plain string).
MACLIFT_FAILED=""
# Space-separated "id:reason" pairs for items skipped because a runtime they
# need is missing (script exit 3) in the last install_run.
MACLIFT_NEEDS=""
# Set by install_item when it returns 3: the missing thing's name.
MACLIFT_NEED_REASON=""

# Session extras from Brewfile.local (not in the catalog).
# MACLIFT_EXTRA_IDS: one id per line. MACLIFT_EXTRA_NAMES: "id<TAB>name" lines.
MACLIFT_EXTRA_IDS=""
MACLIFT_EXTRA_NAMES=""

_install_brew() { "${MACLIFT_BREW:-brew}" "$@"; }
_install_asdf() { "${MACLIFT_ASDF:-asdf}" "$@"; }

_install_kind() { printf '%s\n' "${1%%:*}"; }
_install_name() { printf '%s\n' "${1#*:}"; }

_install_is_extra() {
  [ -n "$MACLIFT_EXTRA_IDS" ] && printf '%s\n' "$MACLIFT_EXTRA_IDS" | grep -Fxq -- "$1"
}

# _install_args <id>: catalog args field (empty for extras).
_install_args() {
  _install_is_extra "$1" && return 0
  catalog_item_field "$1" args 2>/dev/null || true
}

# _install_label <id>: id, plus the display name for extra mas items.
_install_label() {
  local name=""
  if [ -n "$MACLIFT_EXTRA_NAMES" ]; then
    name="$(printf '%s\n' "$MACLIFT_EXTRA_NAMES" | awk -F'\t' -v id="$1" '$1 == id { print $2; exit }')"
  fi
  if [ -n "$name" ]; then printf '%s (%s)\n' "$1" "$name"; else printf '%s\n' "$1"; fi
}

# install_is_present <id>: returns 0 if the item is already installed.
install_is_present() {
  local id="$1" kind name args app pin
  kind="$(_install_kind "$id")"
  name="$(_install_name "$id")"
  case "$kind" in
    brew) _install_brew list --formula -- "$name" >/dev/null 2>&1 ;;
    cask)
      args="$(_install_args "$id")"
      case "$args" in
        skip-if-app:*)
          app="${args#skip-if-app:}"
          # MACLIFT_APP_ROOT (empty by default) lets tests and sandboxes fake /Applications.
          [ -e "${MACLIFT_APP_ROOT:-}$app" ] && return 0
          ;;
      esac
      _install_brew list --cask -- "$name" >/dev/null 2>&1
      ;;
    asdf)
      pin="$(pins_get "$name" 2>/dev/null)" || return 1
      [ -n "$pin" ] || return 1
      _install_asdf where "$name" "$pin" >/dev/null 2>&1
      ;;
    dotfiles) dotfiles_item_linked "$id" ;;
    script)
      args="$(_install_args "$id")"
      [ -n "$args" ] || return 1
      bash "$MACLIFT_DIR/scripts/items/$args" --check >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

# _install_item_body <id>: the work; its output is redirected by install_item.
_install_item_body() {
  local id="$1" kind name args pin
  kind="$(_install_kind "$id")"
  name="$(_install_name "$id")"
  args="$(_install_args "$id")"
  case "$kind" in
    brew) _install_brew install -- "$name" ;;
    cask) _install_brew install --cask -- "$name" ;;
    mas) "${MACLIFT_MAS:-mas}" install "$name" ;;
    asdf)
      pin="$(pins_get "$name")" || { echo "no pinned version for $name"; return 1; }
      # pins_resolve usually added it already. asdf exits non-zero when it is
      # already there, which is fine.
      _pins_plugin_present "$name" || pins_plugin_add "$name" || true
      _install_asdf install "$name" "$pin"
      ;;
    dotfiles) dotfiles_link_item "$id" 0 ;;
    script)
      [ -n "$args" ] || { echo "no script given for $id"; return 1; }
      # Exit 3 means "needs a runtime"; the script names it in $MACLIFT_NEED_FILE.
      MACLIFT_NEED_FILE="${MACLIFT_NEED_FILE:-}" bash "$MACLIFT_DIR/scripts/items/$args"
      ;;
    *) echo "unknown item kind: $kind"; return 1 ;;
  esac
}

# install_item <id>: installs one item; all output goes to the log.
install_item() {
  local rc=0 need_file
  need_file="$(mktemp "${TMPDIR:-/tmp}/maclift-need.XXXXXX")"
  MACLIFT_NEED_REASON=""
  log_line "installing $1"
  MACLIFT_NEED_FILE="$need_file" _install_item_body "$1" >>"${MACLIFT_LOG:-/dev/null}" 2>&1 || rc=$?
  # Exit 3 is a needs-skip only for script items; anything else is a failure.
  if [ "$rc" -eq 3 ] && [ "$(_install_kind "$1")" = script ]; then
    MACLIFT_NEED_REASON="$(head -n 1 "$need_file" 2>/dev/null | tr -d '[:space:]')"
    rm -f "$need_file"
    [ -n "$MACLIFT_NEED_REASON" ] || MACLIFT_NEED_REASON="a runtime"
    log_line "SKIPPED $1 (needs $MACLIFT_NEED_REASON)"
    return 3
  fi
  rm -f "$need_file"
  if [ "$rc" -ne 0 ]; then
    log_line "FAILED $1 (exit $rc)"
    return 1
  fi
  log_line "installed $1"
  return 0
}

# install_notes: prints this run's notes from item scripts, one "  • note"
# line each, skipping blank lines; nothing when there are none. Returns 0.
install_notes() {
  local l
  [ -n "${MACLIFT_NOTES:-}" ] && [ -s "$MACLIFT_NOTES" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    [ -n "$l" ] || continue
    printf '  • %s\n' "$l"
  done <"$MACLIFT_NOTES"
  return 0
}

# _install_kind_ids <kind> <id>...: the ids of that kind, one per line. Script
# ids come in catalog order (the ones not in the catalog follow, as given);
# every other kind keeps the given order.
_install_kind_ids() {
  local kind="$1" id cat_id
  shift
  if [ "$kind" != script ]; then
    for id in "$@"; do
      [ "$(_install_kind "$id")" = "$kind" ] && printf '%s\n' "$id"
    done
    return 0
  fi
  while IFS= read -r cat_id; do
    for id in "$@"; do
      [ "$id" = "$cat_id" ] && { printf '%s\n' "$id"; break; }
    done
  done <<EOT
$(catalog_table | awk -F'\t' '$2 ~ /^script:/ { print $2 }')
EOT
  for id in "$@"; do
    [ "$(_install_kind "$id")" = script ] || continue
    catalog_table | awk -F'\t' -v id="$id" '$2 == id { f = 1 } END { exit !f }' || printf '%s\n' "$id"
  done
  return 0
}

# install_run <dry_run:0|1> <id>...
install_run() {
  local dry="${1:-0}" ordered="" kind id total=0 n=0 asdf_plugins="" start secs label rc=0
  shift || true
  dotfiles_run_id
  mkdir -p "$MACLIFT_CONFIG_DIR/logs"
  MACLIFT_LOG="$MACLIFT_CONFIG_DIR/logs/$MACLIFT_RUN_ID.log"
  # Item scripts append notes for the user here (maclift_note); see install_notes.
  MACLIFT_NOTES="$MACLIFT_CONFIG_DIR/logs/$MACLIFT_RUN_ID.notes"
  export MACLIFT_LOG MACLIFT_NOTES
  MACLIFT_FAILED=""
  MACLIFT_NEEDS=""

  for kind in brew cask mas asdf dotfiles script; do
    for id in $(_install_kind_ids "$kind" "$@"); do
      ordered="$ordered$id
"
      total=$((total + 1))
      [ "$kind" = asdf ] && asdf_plugins="$asdf_plugins $(_install_name "$id")"
    done
  done
  for id in "$@"; do
    case "$(_install_kind "$id")" in
      brew | cask | mas | asdf | dotfiles | script) ;;
      *) echo "skipping unknown item: $id" >&2 ;;
    esac
  done

  if [ -n "$asdf_plugins" ]; then
    if [ "$dry" = "1" ]; then
      # stdout shows "would pin ..." for plugins asdf does not have yet.
      # shellcheck disable=SC2086
      pins_resolve --dry-run $asdf_plugins 2>>"$MACLIFT_LOG" || log_line "could not resolve every asdf pin"
    else
      # shellcheck disable=SC2086
      pins_resolve $asdf_plugins >>"$MACLIFT_LOG" 2>&1 || log_line "could not resolve every asdf pin"
    fi
    if [ "$dry" = "1" ]; then
      pins_apply 1 || true
    else
      pins_apply 0 >>"$MACLIFT_LOG" 2>&1 || log_line "could not apply asdf pins"
    fi
  fi

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    label="$(_install_label "$id")"
    ui_progress "$((n - 1))" "$total" "$label"
    if install_is_present "$id"; then
      ui_status skip "$label"
      log_line "already installed $id"
      continue
    fi
    if [ "$dry" = "1" ]; then
      printf 'would install %s\n' "$label"
      continue
    fi
    ui_status run "$label"
    start="$(date +%s)"
    install_item "$id" && rc=0 || rc=$?
    secs=$(($(date +%s) - start))
    if [ "$rc" -eq 0 ]; then
      ui_status ok "$label" "$secs"
    elif [ "$rc" -eq 3 ]; then
      ui_status need "$label" "$MACLIFT_NEED_REASON"
      MACLIFT_NEEDS="${MACLIFT_NEEDS:+$MACLIFT_NEEDS }$id:$MACLIFT_NEED_REASON"
    else
      ui_status fail "$label" "$secs"
      MACLIFT_FAILED="${MACLIFT_FAILED:+$MACLIFT_FAILED }$id"
    fi
  done <<EOT
$ordered
EOT
  [ -z "$MACLIFT_FAILED" ]
}

# install_brewfile_local: parses $MACLIFT_CONFIG_DIR/Brewfile.local, registers
# the entries as session extras and prints their ids (one per line). Only
# brew "x", cask "x" and mas "Name", id: N lines are understood; anything
# else is skipped with a warning on stderr.
install_brewfile_local() {
  local file="$MACLIFT_CONFIG_DIR/Brewfile.local" line id name num rest
  MACLIFT_EXTRA_IDS=""
  MACLIFT_EXTRA_NAMES=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in '' | '#'*) continue ;; esac
    id=""
    if printf '%s\n' "$line" | grep -Eq '^(brew|cask)[[:space:]]+"[^"]+"[[:space:]]*(#.*)?$'; then
      name="$(printf '%s\n' "$line" | sed -E 's/^(brew|cask)[[:space:]]+"([^"]+)".*/\2/')"
      id="${line%%[[:space:]]*}:$name"
    elif printf '%s\n' "$line" | grep -Eq '^mas[[:space:]]+"[^"]+"[[:space:]]*,[[:space:]]*id:[[:space:]]*[0-9]+[[:space:]]*(#.*)?$'; then
      name="$(printf '%s\n' "$line" | sed -E 's/^mas[[:space:]]+"([^"]+)".*/\1/')"
      num="$(printf '%s\n' "$line" | sed -E 's/.*id:[[:space:]]*([0-9]+).*/\1/')"
      id="mas:$num"
      MACLIFT_EXTRA_NAMES="$MACLIFT_EXTRA_NAMES$id	$name
"
    fi
    case "$id" in
      brew:-* | cask:-*) id="" ;;
    esac
    if [ -z "$id" ]; then
      rest="$line"
      echo "warning: Brewfile.local: skipping unsupported line: $rest" >&2
      continue
    fi
    MACLIFT_EXTRA_IDS="$MACLIFT_EXTRA_IDS$id
"
  done <"$file"
  MACLIFT_EXTRA_IDS="${MACLIFT_EXTRA_IDS%
}"
  [ -z "$MACLIFT_EXTRA_IDS" ] || printf '%s\n' "$MACLIFT_EXTRA_IDS"
  return 0
}
