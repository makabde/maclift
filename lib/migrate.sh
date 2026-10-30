#!/usr/bin/env bash
#
# maclift migrate: plan which home-folder symlinks point into an old
# dotfiles folder and where maclift's copies live.
# bash 3.2 compatible. Meant to be sourced (needs lib/core.sh).

# Physical path of a link target, resolved against the link's own folder.
# Works for files, folders and dangling targets: the parent folder is
# resolved physically and the basename is appended.
_migrate_resolve_target() {
  local link="$1" target dir base
  target="$(readlink "$link")" || return 1
  case "$target" in
    /*) ;;
    *) target="$(dirname "$link")/$target" ;;
  esac
  while [ "${#target}" -gt 1 ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done
  dir="$(dirname "$target")"
  base="$(basename "$target")"
  if [ -d "$target" ]; then
    maclift_real_path "$target"
  elif [ -d "$dir" ]; then
    printf '%s/%s\n' "$(maclift_real_path "$dir")" "$base"
  else
    printf '%s\n' "$target"
  fi
}

# Prints link<TAB>old_target<TAB>new_target<TAB>status, sorted by link.
# Returns 1 if old_dir is not a folder.
migrate_plan() {
  local old_dir="$1" old_real link target rel name cand new status
  [ -d "$old_dir" ] || return 1
  old_real="$(maclift_real_path "$old_dir")"
  for link in "$MACLIFT_HOME"/.[!.]* "$MACLIFT_HOME"/.config/*; do
    [ -L "$link" ] || continue
    target="$(_migrate_resolve_target "$link")" || continue
    case "$target" in
      "$old_real"/*) ;;
      *) continue ;;
    esac
    rel="${target#"$old_real"/}"
    name="$(basename "$link")"
    new="-"
    status="unmapped"
    cand="$MACLIFT_DIR/$rel"
    case "$rel" in
      dotfiles/*)
        if [ -e "$cand" ]; then
          new="$MACLIFT_HOME/.maclift/$rel"
          status="repoint"
        fi
        ;;
    esac
    if [ "$status" = "unmapped" ] && [ -e "$MACLIFT_CONFIG_DIR/dotfiles/${name#.}" ]; then
      new="$MACLIFT_CONFIG_DIR/dotfiles/${name#.}"
      status="repoint"
    fi
    printf '%s\t%s\t%s\t%s\n' "$link" "$target" "$new" "$status"
  done | LC_ALL=C sort
}

# migrate_apply <dry_run:0|1> <old_dir>: repoints every "repoint" link from
# migrate_plan to its maclift copy. Writes the manifest
# $MACLIFT_CONFIG_DIR/backups/<run-id>/migrate.tsv BEFORE changing anything:
#   #created-maclift-link<TAB>yes|no
#   link<TAB>old_target<TAB>new_target     (one per repointed link)
# Only symlinks are replaced (ln -sfn); file contents are never touched.
# Returns 0, or 1 if a link could not be replaced. Needs lib/dotfiles.sh.
migrate_apply() {
  local dry_run="${1:-0}" old_dir="$2" plan link old new status
  local repo_link="$MACLIFT_HOME/.maclift" created="yes" dir manifest tmp
  local n_repoint=0 n_left=0 failed=0
  plan="$(migrate_plan "$old_dir")" || return 1
  if ! printf '%s\n' "$plan" | awk -F'\t' '$4=="repoint"{f=1} END{exit !f}'; then
    echo "nothing to migrate"
    return 0
  fi
  dotfiles_run_id
  if [ -e "$repo_link" ] && [ "$(maclift_real_path "$repo_link")" = "$(maclift_real_path "$MACLIFT_DIR")" ]; then
    created="no"
  fi

  if [ "$dry_run" = "1" ]; then
    while IFS="$(printf '\t')" read -r link old new status; do
      [ -n "$link" ] || continue
      if [ "$status" = "repoint" ]; then
        echo "would repoint $link: $old → $new"
      else
        echo "left alone (no maclift copy): $link"
      fi
    done <<EOF_PLAN
$plan
EOF_PLAN
    [ "$created" = "yes" ] && echo "would link ~/.maclift → $MACLIFT_DIR"
    return 0
  fi

  # Manifest first, atomically (temp file in the same folder, then mv).
  dir="$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID"
  manifest="$dir/migrate.tsv"
  mkdir -p "$dir" || return 1
  tmp="$manifest.tmp.$$"
  {
    printf '#created-maclift-link\t%s\n' "$created"
    # old_target is the RAW link text (not migrate_plan's physical path), so
    # rollback can restore relative links byte-identically.
    while IFS="$(printf '\t')" read -r link old new status; do
      [ "$status" = "repoint" ] || continue
      printf '%s\t%s\t%s\n' "$link" "$(readlink "$link")" "$new"
    done <<EOF_PLAN
$plan
EOF_PLAN
  } >"$tmp" && mv "$tmp" "$manifest" || { rm -f "$tmp"; return 1; }
  log_line "migrate: manifest $manifest"

  dotfiles_link_repo 0 >/dev/null || { echo "✗ could not link $repo_link" >&2; return 1; }

  while IFS="$(printf '\t')" read -r link old new status; do
    [ -n "$link" ] || continue
    if [ "$status" != "repoint" ]; then
      n_left=$((n_left + 1))
      echo "left alone (no maclift copy): $link"
      continue
    fi
    if [ ! -L "$link" ]; then
      echo "✗ $link is no longer a symlink; left alone" >&2
      failed=1
      continue
    fi
    if ln -sfn "$new" "$link"; then
      n_repoint=$((n_repoint + 1))
      log_line "migrate: repointed $link -> $new (was $old)"
      echo "repointed $link"
    else
      echo "✗ could not repoint $link" >&2
      failed=1
    fi
  done <<EOF_PLAN
$plan
EOF_PLAN
  echo "$n_repoint repointed, $n_left left alone; manifest: $manifest"
  [ "$failed" = "0" ]
}

# migrate_rollback <dry_run:0|1> [run-id]: undoes a migration from its manifest
# (default: the newest backups/*/migrate.tsv; folder names sort by time).
# A link is restored (ln -sfn <raw old text>) only if it still points at the
# manifest's new target; otherwise it is skipped. If the run created
# ~/.maclift, that link is removed (only when it points at MACLIFT_DIR) and an
# earlier ~/.maclift saved in the run's manifest.tsv is moved back. Afterwards
# the manifest is renamed to migrate.rolled-back.tsv.
# Returns 0, or 1 if there is no manifest or something could not be restored.
migrate_rollback() {
  local dry_run="${1:-0}" run_id="${2:-}" base="$MACLIFT_CONFIG_DIR/backups"
  local dir="" manifest d link old new created="no" failed=0 cur
  local repo_link="$MACLIFT_HOME/.maclift" orig bk saved="" removing=0
  if [ -n "$run_id" ]; then
    [ -f "$base/$run_id/migrate.tsv" ] && dir="$base/$run_id"
  else
    for d in "$base"/*/; do
      [ -f "${d}migrate.tsv" ] && dir="${d%/}"
    done
  fi
  if [ -z "$dir" ]; then
    echo "nothing to roll back"
    return 1
  fi
  manifest="$dir/migrate.tsv"
  created="$(awk -F'\t' '$1=="#created-maclift-link"{print $2}' "$manifest")"

  while IFS="$(printf '\t')" read -r link old new; do
    case "$link" in ''|'#'*) continue ;; esac
    cur="$(readlink "$link" 2>/dev/null)" || cur=""
    if [ -L "$link" ] && [ "$cur" = "$new" ]; then
      if [ "$dry_run" = "1" ]; then
        echo "would restore $link: $new → $old"
      elif ln -sfn "$old" "$link"; then
        log_line "migrate: restored $link -> $old"
        echo "restored $link"
      else
        echo "✗ could not restore $link" >&2
        failed=1
      fi
    elif [ -L "$link" ] && [ "$cur" = "$old" ]; then
      echo "already restored $link"
    else
      echo "skipped $link (changed since migration)"
    fi
  done <"$manifest"

  if [ "$created" = "yes" ]; then
    if [ -f "$dir/manifest.tsv" ]; then
      while IFS="$(printf '\t')" read -r orig bk; do
        [ "$orig" = "$repo_link" ] && saved="$bk"
      done <"$dir/manifest.tsv"
    fi
    if [ -L "$repo_link" ] && [ "$(maclift_real_path "$repo_link")" = "$(maclift_real_path "$MACLIFT_DIR")" ]; then
      if [ "$dry_run" = "1" ]; then
        echo "would remove ~/.maclift"
        removing=1
      elif rm -f "$repo_link"; then
        echo "removed ~/.maclift"
      else
        failed=1
      fi
    fi
    if [ -n "$saved" ] && { [ -e "$saved" ] || [ -L "$saved" ]; }; then
      if [ "$removing" = "0" ] && { [ -e "$repo_link" ] || [ -L "$repo_link" ]; }; then
        [ "$dry_run" = "1" ] || echo "skipped ~/.maclift backup (a different ~/.maclift is in place)"
      elif [ "$dry_run" = "1" ]; then
        echo "would restore ~/.maclift from $saved"
      elif mv "$saved" "$repo_link"; then
        echo "restored ~/.maclift"
      else
        echo "✗ could not restore ~/.maclift from $saved" >&2
        failed=1
      fi
    fi
  fi

  [ "$dry_run" = "1" ] && return 0
  if [ "$failed" = "0" ]; then
    mv "$manifest" "$dir/migrate.rolled-back.tsv" || return 1
    return 0
  fi
  return 1
}
