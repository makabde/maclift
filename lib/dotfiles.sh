#!/usr/bin/env bash
#
# maclift dotfiles: link repo dotfiles into MACLIFT_HOME, backing up
# whatever is in the way (never deleting). bash 3.2 compatible.
# Meant to be sourced after lib/core.sh and lib/catalog.sh.

# dotfiles_run_id: makes sure MACLIFT_RUN_ID is set and exported. Call it in
# the main shell (not inside $(...)) so the value survives; the entry script
# (Task 11) sets it once at run start, and every public function here also
# calls it first, so one run always uses one backups/<run-id>/ folder.
dotfiles_run_id() {
  if [ -z "${MACLIFT_RUN_ID:-}" ]; then
    MACLIFT_RUN_ID="$(date +%Y-%m-%d_%H%M%S)"
  fi
  export MACLIFT_RUN_ID
}

# backup_path <path>: moves path (file, folder or symlink) into this run's
# backup folder, records "original<TAB>backup" in manifest.tsv, prints the
# backup path. Uses mv so symlinks stay symlinks.
backup_path() {
  local src="$1" rel dest dir
  dotfiles_run_id
  case "$src" in
    "$MACLIFT_HOME"/*) rel="${src#"$MACLIFT_HOME"/}" ;;
    *) rel="$(basename "$src")" ;;
  esac
  dir="$MACLIFT_CONFIG_DIR/backups/$MACLIFT_RUN_ID"
  dest="$dir/$rel"
  # Never overwrite an earlier backup from the same run.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    dest="$dest.$$.$RANDOM"
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  mv "$src" "$dest" || return 1
  printf '%s\t%s\n' "$src" "$dest" >>"$dir/manifest.tsv"
  log_line "backed up $src -> $dest"
  printf '%s\n' "$dest"
}

# Where a repo-relative dotfile path gets linked.
_dotfiles_target() {
  local base
  base="$(basename "$1")"
  if [ "$1" = "nvim" ]; then
    printf '%s\n' "$MACLIFT_HOME/.config/nvim"
  else
    printf '%s\n' "$MACLIFT_HOME/.$base"
  fi
}

# What the target should point at: the user's override if present, else the repo.
_dotfiles_source() {
  local base
  base="$(basename "$1")"
  if [ -e "$MACLIFT_CONFIG_DIR/dotfiles/$base" ]; then
    printf '%s\n' "$MACLIFT_CONFIG_DIR/dotfiles/$base"
  else
    printf '%s\n' "$MACLIFT_DIR/dotfiles/$1"
  fi
}

# _dotfiles_is_linked <source> <link>: true when <link> is a symlink that
# leads to <source>, directly or through another link such as ~/.maclift.
_dotfiles_is_linked() {
  local to
  [ -L "$2" ] || return 1
  to="$(readlink "$2")"
  [ "$to" = "$1" ] && return 0
  case "$to" in /*) ;; *) to="$(dirname "$2")/$to" ;; esac
  [ -e "$to" ] || return 1
  [ "$(_dotfiles_real "$to")" = "$(_dotfiles_real "$1")" ]
}

# Resolves the folder part of a path through any links (the last part is
# kept as it is, so a link to a link still has to name the same file).
_dotfiles_real() {
  printf '%s/%s\n' "$(maclift_real_path "$(dirname "$1")")" "$(basename "$1")"
}

# _dotfiles_link_one <src> <target> <dry_run>: skip / back up / link one path.
_dotfiles_link_one() {
  local src="$1" target="$2" dry_run="$3" bk=""
  if _dotfiles_is_linked "$src" "$target"; then
    echo "skip"
    return 0
  fi
  if [ "$dry_run" = "1" ]; then
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo "would back up $target"
    fi
    echo "would link $target → $src"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    bk="$(backup_path "$target")" || { echo "✗ could not back up $target" >&2; return 1; }
  fi
  mkdir -p "$(dirname "$target")" || return 1
  ln -sfn "$src" "$target" || return 1
  log_line "linked $target -> $src"
  if [ -n "$bk" ]; then echo "ok $bk"; else echo "ok"; fi
}

# dotfiles_link_item <id> <dry_run:0|1>
dotfiles_link_item() {
  local id="$1" dry_run="${2:-0}" p
  dotfiles_run_id
  for p in $(catalog_item_field "$id" args); do
    _dotfiles_link_one "$(_dotfiles_source "$p")" "$(_dotfiles_target "$p")" "$dry_run" || return 1
  done
}

# dotfiles_link_user <dry_run:0|1> [selected_id...]: links every file in
# $MACLIFT_CONFIG_DIR/dotfiles/ whose target is not covered by one of the
# selected dotfiles:* ids (those are handled by dotfiles_link_item). With no
# ids, nothing is covered and every user file is linked here. A user file is named by its
# target without the leading dot: npmrc -> ~/.npmrc, nvim -> ~/.config/nvim.
dotfiles_link_user() {
  local dry_run="${1:-0}" covered="" id p f name
  shift || true
  dotfiles_run_id
  [ -d "$MACLIFT_CONFIG_DIR/dotfiles" ] || return 0
  for id in "$@"; do
    case "$id" in dotfiles:*) ;; *) continue ;; esac
    for p in $(catalog_item_field "$id" args); do
      covered="$covered
$(_dotfiles_target "$p")"
    done
  done
  for f in "$MACLIFT_CONFIG_DIR"/dotfiles/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    name="$(basename "$f")"
    if printf '%s\n' "$covered" | grep -Fxq "$(_dotfiles_target "$name")"; then
      continue
    fi
    _dotfiles_link_one "$f" "$(_dotfiles_target "$name")" "$dry_run" || return 1
  done
}

# dotfiles_item_linked <id>: returns 0 when every link of the item is correct.
dotfiles_item_linked() {
  local p
  for p in $(catalog_item_field "$1" args); do
    _dotfiles_is_linked "$(_dotfiles_source "$p")" "$(_dotfiles_target "$p")" || return 1
  done
  return 0
}

# dotfiles_link_repo <dry_run:0|1>: makes $MACLIFT_HOME/.maclift a link to
# the clone ($MACLIFT_DIR), so config files can use the fixed path
# ~/.maclift/dotfiles/... wherever the repo lives. Anything else in the way
# is backed up; a clone that already lives at ~/.maclift is left alone.
dotfiles_link_repo() {
  local dry_run="${1:-0}" target="$MACLIFT_HOME/.maclift"
  dotfiles_run_id
  if [ -e "$target" ] && [ "$(maclift_real_path "$target")" = "$(maclift_real_path "$MACLIFT_DIR")" ]; then
    echo "skip"
    return 0
  fi
  _dotfiles_link_one "$MACLIFT_DIR" "$target" "$dry_run"
}
