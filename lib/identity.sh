#!/usr/bin/env bash
#
# maclift identity: ask for name/email/GitHub once, keep them in user.conf,
# render ~/.gitconfig.local. bash 3.2 compatible.
# Meant to be sourced after lib/core.sh, lib/conf.sh, lib/catalog.sh,
# lib/selection.sh, lib/ui.sh and lib/dotfiles.sh.

_identity_conf() { printf '%s\n' "$MACLIFT_CONFIG_DIR/user.conf"; }

# identity_ask: prompts (pre-filled from user.conf) and saves MACLIFT_NAME,
# MACLIFT_EMAIL, MACLIFT_GITHUB. With MACLIFT_ASSUME_YES=1 uses saved values.
identity_ask() {
  local conf name email github tries
  conf="$(_identity_conf)"
  name="$(conf_get "$conf" MACLIFT_NAME 2>/dev/null || true)"
  email="$(conf_get "$conf" MACLIFT_EMAIL 2>/dev/null || true)"
  github="$(conf_get "$conf" MACLIFT_GITHUB 2>/dev/null || true)"

  if [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; then
    if [ -z "$name" ] || [ -z "$email" ]; then
      die "run maclift once interactively first"
    fi
    return 0
  fi

  tries=0
  while :; do
    name="$(ui_input "Full name" "$name")"
    [ -n "$name" ] && break
    tries=$((tries + 1))
    [ "$tries" -ge 5 ] && die "a name is required"
  done

  tries=0
  while :; do
    email="$(ui_input "Email" "$email")"
    case "$email" in
      *[[:space:]]*) ;;
      *) printf '%s\n' "$email" | grep -Eq '^[^@ ]+@[^@ ]+\.[^@ ]+$' && break ;;
    esac
    echo "That does not look like an email address." >&2
    email=""
    tries=$((tries + 1))
    [ "$tries" -ge 5 ] && die "a valid email is required"
  done

  github="$(ui_input "GitHub username (optional)" "$github")"

  conf_set "$conf" MACLIFT_NAME "$name" || return 1
  conf_set "$conf" MACLIFT_EMAIL "$email" || return 1
  conf_set "$conf" MACLIFT_GITHUB "$github" || return 1
}

# identity_alt_active: succeeds when MACLIFT_ALT_DIR is set and the
# second-identity item is in the saved selection (a deselected item leaves
# its answers in user.conf but must not change git).
identity_alt_active() {
  local d ids
  d="$(conf_get "$(_identity_conf)" MACLIFT_ALT_DIR 2>/dev/null || true)"
  [ -n "$d" ] || return 1
  ids="$(selection_load)"
  case "
$ids
" in *"
script:second-identity
"*) return 0 ;; esac
  return 1
}

# _identity_install <tmp> <target>: puts the finished temp file in place.
# Identical to target: removes tmp, prints "ok <target>". Otherwise backs up
# the existing target, moves tmp in and prints "wrote <target>".
_identity_install() {
  local tmp="$1" target="$2"
  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    echo "ok $target"
    return 0
  fi
  dotfiles_run_id
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup_path "$target" >/dev/null || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  echo "wrote $target"
}

# identity_render_gitconfig <dry_run>: writes $MACLIFT_HOME/.gitconfig.local.
# With MACLIFT_SIGNING_KEY set it also turns on commit/tag signing.
# With MACLIFT_ALT_DIR set it ends with an includeIf for that folder, so the
# second identity (~/.gitconfig.alt) overrides everything above it.
# Existing file that differs is backed up first; identical file is left alone.
identity_render_gitconfig() {
  local dry_run="${1:-0}" conf name email signing target tmp alt_dir
  conf="$(_identity_conf)"
  target="$MACLIFT_HOME/.gitconfig.local"
  name="$(conf_get "$conf" MACLIFT_NAME 2>/dev/null || true)"
  email="$(conf_get "$conf" MACLIFT_EMAIL 2>/dev/null || true)"
  signing="$(conf_get "$conf" MACLIFT_SIGNING_KEY 2>/dev/null || true)"
  alt_dir=""
  if identity_alt_active; then
    alt_dir="$(conf_get "$conf" MACLIFT_ALT_DIR 2>/dev/null || true)"
    if ! alt_dir="$(_identity_alt_dir "$alt_dir")"; then
      log_line "skipped includeIf: MACLIFT_ALT_DIR in $conf is not an absolute path or ~/ folder"
      alt_dir=""
    fi
  fi
  if [ -z "$name" ] || [ -z "$email" ]; then
    die "name/email missing in $conf; run maclift interactively first"
  fi
  if [ "$dry_run" = "1" ]; then
    echo "would write $target"
    return 0
  fi
  tmp="$(mktemp "$target.XXXXXX")" || return 1
  cp "$MACLIFT_DIR/templates/gitconfig.local.tmpl" "$tmp" || { rm -f "$tmp"; return 1; }
  if ! git config -f "$tmp" user.name "$name" || ! git config -f "$tmp" user.email "$email"; then
    rm -f "$tmp"
    return 1
  fi
  if [ -n "$signing" ]; then
    if ! git config -f "$tmp" user.signingkey "$signing" \
      || ! git config -f "$tmp" commit.gpgsign true \
      || ! git config -f "$tmp" tag.gpgsign true; then
      rm -f "$tmp"
      return 1
    fi
  fi
  if [ -n "$alt_dir" ]; then
    # shellcheck disable=SC2088 # git expands the literal ~/ itself
    if ! git config -f "$tmp" "includeIf.gitdir:${alt_dir}/.path" "~/.gitconfig.alt"; then
      rm -f "$tmp"
      return 1
    fi
  fi
  _identity_install "$tmp" "$target"
}

# _identity_alt_dir <value>: prints the folder with one trailing slash removed;
# collapses repeated slashes. Returns 1 unless it is an absolute path or
# starts with ~/, or when that leaves only / or ~ (the whole home or root).
_identity_alt_dir() {
  local d="$1"
  # shellcheck disable=SC2088 # a literal ~/ prefix, not a path
  case "$d" in
    /* | "~/"*) ;;
    *) return 1 ;;
  esac
  while :; do
    case "$d" in *//*) d="${d%%//*}/${d#*//}" ;; *) break ;; esac
  done
  d="${d%/}"
  case "$d" in "" | "~") return 1 ;; esac
  printf '%s\n' "$d"
}

# _identity_alt_email_ok <email>: has an @ and no whitespace.
_identity_alt_email_ok() {
  case "$1" in
    *[[:space:]]* | "") return 1 ;;
    *@*) return 0 ;;
  esac
  return 1
}

# identity_ask_alt: prompts (pre-filled from user.conf) and saves
# MACLIFT_ALT_NAME, MACLIFT_ALT_EMAIL, MACLIFT_ALT_DIR. With
# MACLIFT_ASSUME_YES=1 uses the saved values; returns 1 if any is missing.
identity_ask_alt() {
  local conf name email dir tries clean
  conf="$(_identity_conf)"
  name="$(conf_get "$conf" MACLIFT_ALT_NAME 2>/dev/null || true)"
  email="$(conf_get "$conf" MACLIFT_ALT_EMAIL 2>/dev/null || true)"
  dir="$(conf_get "$conf" MACLIFT_ALT_DIR 2>/dev/null || true)"

  if [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; then
    if [ -z "$name" ] || [ -z "$email" ] || [ -z "$dir" ]; then
      echo "second identity needs MACLIFT_ALT_NAME, MACLIFT_ALT_EMAIL and MACLIFT_ALT_DIR in user.conf" >&2
      return 1
    fi
    if ! _identity_alt_email_ok "$email" || ! _identity_alt_dir "$dir" >/dev/null; then
      echo "second identity: MACLIFT_ALT_EMAIL or MACLIFT_ALT_DIR in user.conf is not valid" >&2
      return 1
    fi
    return 0
  fi

  tries=0
  while :; do
    name="$(ui_input "Second identity: full name" "$name")"
    [ -n "$name" ] && break
    tries=$((tries + 1))
    [ "$tries" -ge 5 ] && { echo "a name is required" >&2; return 1; }
  done

  tries=0
  while :; do
    email="$(ui_input "Second identity: email" "$email")"
    _identity_alt_email_ok "$email" && break
    echo "That does not look like an email address." >&2
    email=""
    tries=$((tries + 1))
    [ "$tries" -ge 5 ] && { echo "a valid email is required" >&2; return 1; }
  done

  tries=0
  while :; do
    dir="$(ui_input "Folder that uses it (for example ~/Work)" "$dir")"
    if clean="$(_identity_alt_dir "$dir")"; then
      dir="$clean"
      break
    fi
    echo "Use an absolute path or one starting with ~/" >&2
    dir=""
    tries=$((tries + 1))
    [ "$tries" -ge 5 ] && { echo "a folder is required" >&2; return 1; }
  done

  conf_set "$conf" MACLIFT_ALT_NAME "$name" || return 1
  conf_set "$conf" MACLIFT_ALT_EMAIL "$email" || return 1
  conf_set "$conf" MACLIFT_ALT_DIR "$dir" || return 1
}

# _identity_alt_require: returns 1 with a message unless user.conf has
# MACLIFT_ALT_NAME and MACLIFT_ALT_EMAIL.
_identity_alt_require() {
  local conf
  conf="$(_identity_conf)"
  if [ -z "$(conf_get "$conf" MACLIFT_ALT_NAME 2>/dev/null || true)" ] \
    || [ -z "$(conf_get "$conf" MACLIFT_ALT_EMAIL 2>/dev/null || true)" ]; then
    echo "MACLIFT_ALT_NAME or MACLIFT_ALT_EMAIL missing in $conf" >&2
    return 1
  fi
}

# _identity_alt_build <file>: writes the second identity config into file
# (overwriting it). With MACLIFT_ALT_SIGNING_KEY it signs commits and tags
# with that key; without one it turns both off and blanks user.signingkey so
# work in that folder never uses the personal key. Returns 1 if a value is
# missing or git config fails.
_identity_alt_build() {
  local file="$1" conf name email key
  conf="$(_identity_conf)"
  name="$(conf_get "$conf" MACLIFT_ALT_NAME 2>/dev/null || true)"
  email="$(conf_get "$conf" MACLIFT_ALT_EMAIL 2>/dev/null || true)"
  key="$(conf_get "$conf" MACLIFT_ALT_SIGNING_KEY 2>/dev/null || true)"
  _identity_alt_require || return 1
  printf '# Generated by maclift from ~/.config/maclift/user.conf. Do not edit by hand.\n# Second git identity, used inside the folder named by MACLIFT_ALT_DIR.\n' >"$file" || return 1
  git config -f "$file" user.name "$name" || return 1
  git config -f "$file" user.email "$email" || return 1
  if [ -n "$key" ]; then
    git config -f "$file" user.signingkey "$key" \
      && git config -f "$file" commit.gpgsign true \
      && git config -f "$file" tag.gpgsign true
    return
  fi
  # No alt key: switch signing off and blank the key, so an explicit -S fails
  # instead of signing as the personal identity.
  git config -f "$file" commit.gpgsign false \
    && git config -f "$file" tag.gpgsign false \
    && git config -f "$file" user.signingkey ""
}

# identity_alt_current: 0 when $MACLIFT_HOME/.gitconfig.alt is exactly what
# user.conf renders to now. Writes only a temp file outside the home folder.
identity_alt_current() {
  local tmp rc=0
  [ -f "$MACLIFT_HOME/.gitconfig.alt" ] || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/maclift-alt.XXXXXX")" || return 1
  if _identity_alt_build "$tmp" 2>/dev/null; then
    cmp -s "$tmp" "$MACLIFT_HOME/.gitconfig.alt" || rc=1
  else
    rc=1
  fi
  rm -f "$tmp"
  return "$rc"
}

# identity_render_alt <dry_run>: writes $MACLIFT_HOME/.gitconfig.alt from
# user.conf (see _identity_alt_build). An identical file is left alone.
identity_render_alt() {
  local dry_run="${1:-0}" target tmp
  target="$MACLIFT_HOME/.gitconfig.alt"
  _identity_alt_require || return 1
  if [ "$dry_run" = "1" ]; then
    echo "would write $target"
    return 0
  fi
  tmp="$(mktemp "$target.XXXXXX")" || return 1
  _identity_alt_build "$tmp" || { rm -f "$tmp"; return 1; }
  _identity_install "$tmp" "$target"
}
