#!/usr/bin/env bash
#
# maclift restore: puts dotfiles back from a backup run (backups/<run-id>/
# manifest.tsv, written by backup_path). Never deletes: whatever is in the
# way is moved into this run's backup folder first, so a restore can be undone.
# bash 3.2 compatible.
# Meant to be sourced after lib/core.sh, ui.sh and dotfiles.sh.

# restore_runs
# Prints "run-id<TAB>count" lines, newest first, for every backup run with at
# least one manifest line. Leaves out the current run (MACLIFT_RUN_ID).
restore_runs() {
  local root="$MACLIFT_CONFIG_DIR/backups" d id n
  [ -d "$root" ] || return 0
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    [ "$id" != "${MACLIFT_RUN_ID:-}" ] || continue
    [ -f "$d/manifest.tsv" ] || continue
    n="$(_restore_first_entries "$d/manifest.tsv" | grep -c . || true)"
    [ "${n:-0}" -gt 0 ] || continue
    printf '%s\t%s\n' "$id" "$n"
  done | LC_ALL=C sort -r
}

# _restore_inside_home <path>: 0 if path is absolute, has no "." or ".."
# segments, is not the home folder itself, and its parent folder (resolved)
# is MACLIFT_HOME or below.
_restore_inside_home() {
  local parent home
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in */. | */./* | */.. | */../*) return 1 ;; esac
  home="$(maclift_real_path "$MACLIFT_HOME")"
  [ "$(maclift_real_path "$1")" != "$home" ] || return 1
  parent="$(maclift_real_path "$(dirname "$1")")"
  case "$parent" in
    "$home" | "$home"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# _restore_inside_backups <backup>: 0 if backup is absolute, has no "." or
# ".." segments, and its parent folder (resolved) is inside
# $MACLIFT_CONFIG_DIR/backups/. The manifest is a plain file, so restore never
# copies from anywhere else.
_restore_inside_backups() {
  local root parent
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in */. | */./* | */.. | */../*) return 1 ;; esac
  root="$(maclift_real_path "$MACLIFT_CONFIG_DIR/backups")"
  parent="$(maclift_real_path "$(dirname "$1")")"
  case "$parent" in
    "$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# _restore_identical <original> <backup>: 0 if both are the same symlink text,
# the same file content, or folders with no difference.
_restore_identical() {
  if [ -L "$1" ] && [ -L "$2" ]; then
    [ "$(readlink "$1")" = "$(readlink "$2")" ]
    return
  fi
  [ ! -L "$1" ] && [ ! -L "$2" ] || return 1
  if [ -d "$1" ] && [ -d "$2" ]; then
    diff -rq "$1" "$2" >/dev/null 2>&1
    return
  fi
  [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"
}

# _restore_first_entries <manifest>: prints the manifest's lines, keeping only
# the first line for each original. A path backed up twice in one run has the
# user's own file on its first line; later lines are files maclift made.
_restore_first_entries() {
  local original backup seen="
"
  while IFS=$'\t' read -r original backup; do
    [ -n "$original" ] || continue
    case "$seen" in *"
$original
"*) continue ;; esac
    seen="$seen$original
"
    printf '%s\t%s\n' "$original" "$backup"
  done <"$1"
}

# _restore_count <manifest>: how many originals restore_run would put back
# (first line per original, inside the home folder, backup present and inside
# backups/, different).
_restore_count() {
  local original backup n=0
  while IFS=$'\t' read -r original backup; do
    [ -n "$original" ] || continue
    _restore_inside_home "$original" || continue
    [ -e "$backup" ] || [ -L "$backup" ] || continue
    _restore_inside_backups "$backup" || continue
    _restore_identical "$original" "$backup" && continue
    n=$((n + 1))
  done <<EOF_ENTRIES
$(_restore_first_entries "$1")
EOF_ENTRIES
  printf '%s\n' "$n"
}

# restore_run <dry_run:0|1> <run-id>
# Puts back every file listed in that run's manifest (the first backup of each
# path). Returns 0, or 1 if the run is unknown or any entry was skipped with a
# cross.
# Sets RESTORE_MOVED_ASIDE=1 when it moved something out of the way.
restore_run() {
  local dry="$1" id="$2" manifest entries original backup rc=0
  RESTORE_MOVED_ASIDE=0
  manifest="$MACLIFT_CONFIG_DIR/backups/$id/manifest.tsv"
  case "$id" in */* | '' | . | ..) manifest="" ;; esac
  if [ -n "$manifest" ] && [ ! -f "$manifest" ] && [ -f "${manifest%/*}/migrate.tsv" ]; then
    echo "$id is a migration, not a dotfile backup; undo it with: maclift migrate --rollback --run $id" >&2
    return 1
  fi
  if [ -z "$manifest" ] || [ ! -f "$manifest" ]; then
    echo "no backup run $id" >&2
    return 1
  fi
  dotfiles_run_id
  # Read the manifest up front: restoring into the run being restored appends to it.
  entries="$(_restore_first_entries "$manifest")"
  while IFS=$'\t' read -r original backup; do
    [ -n "$original" ] || continue
    if ! _restore_inside_home "$original"; then
      echo "✗ $original: outside the home folder, skipped" >&2
      rc=1
      continue
    fi
    if [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
      echo "✗ $original: backup $backup is missing" >&2
      rc=1
      continue
    fi
    if ! _restore_inside_backups "$backup"; then
      echo "✗ $original: backup $backup is not inside $MACLIFT_CONFIG_DIR/backups, skipped" >&2
      rc=1
      continue
    fi
    if _restore_identical "$original" "$backup"; then
      echo "ok $original"
      continue
    fi
    if [ "$dry" = "1" ]; then
      echo "would restore $original from $backup"
      continue
    fi
    if [ -e "$original" ] || [ -L "$original" ]; then
      backup_path "$original" >/dev/null || { echo "✗ $original: could not move it aside" >&2; rc=1; continue; }
      RESTORE_MOVED_ASIDE=1
    fi
    if mkdir -p "$(dirname "$original")" && cp -PRp "$backup" "$original"; then
      echo "restored $original"
    else
      echo "✗ $original: could not copy $backup" >&2
      rc=1
    fi
  done <<EOF_ENTRIES
$entries
EOF_ENTRIES
  return "$rc"
}

# cmd_restore <dry_run:0|1> [run-id]
# Without a run id, asks which backup to restore (-y needs --run).
cmd_restore() {
  local dry="$1" id="${2:-}" runs line label n rc=0
  local labels=()
  runs="$(restore_runs)"
  if [ -z "$runs" ] && [ -z "$id" ]; then
    echo "No backups in $MACLIFT_CONFIG_DIR/backups."
    return 0
  fi
  if [ -z "$id" ]; then
    if [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; then
      echo "maclift restore -y needs --run <id> to pick a backup. Runs:" >&2
      printf '%s\n' "$runs" | while IFS=$'\t' read -r line n; do echo "  $line" >&2; done
      return 64
    fi
    # The same count as the prompt below, next to the run's total.
    while IFS=$'\t' read -r line n; do
      labels+=("$line ($n files, $(_restore_count "$MACLIFT_CONFIG_DIR/backups/$line/manifest.tsv") to restore)")
    done <<EOF_RUNS
$runs
EOF_RUNS
    label="$(ui_choose_one "Restore which backup?" "${labels[@]}")" || return 1
    id="${label%% *}"
  fi
  n=0
  if [ -f "$MACLIFT_CONFIG_DIR/backups/$id/manifest.tsv" ]; then
    n="$(_restore_count "$MACLIFT_CONFIG_DIR/backups/$id/manifest.tsv")"
  fi
  if [ "$dry" != "1" ] && [ "${MACLIFT_ASSUME_YES:-}" != "1" ] && [ "$n" -gt 0 ]; then
    ui_confirm "Restore $n files from $id?" n || { echo "Nothing restored."; return 0; }
  fi
  restore_run "$dry" "$id" || rc=$?
  if [ "${RESTORE_MOVED_ASIDE:-0}" = "1" ]; then
    echo "Undo with: maclift restore --run $MACLIFT_RUN_ID"
  fi
  return "$rc"
}
