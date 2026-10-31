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

# _identity_lc <text>: prints text in lower case (ASCII only; bash 3.2 has
# no ${x,,}). Git section and key names are case-insensitive.
_identity_lc() {
  printf '%s\n' "$1" | LC_ALL=C tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# _identity_owned <kind> <name> <value> [<signing>]: succeeds when maclift
# writes this setting itself in that file (kind: local or alt), so the old
# value must not be carried over. signing (see _identity_sign_mode): with
# "keep" the signing settings are not maclift's (set up by hand); with
# "gpg" gpg.format is maclift's too, so a GPG key never ends up
# next to gpg.format = ssh. In .gitconfig.local maclift also owns includeIf
# paths that point at ~/.gitconfig.alt (it adds its own when the second
# identity is active).
_identity_owned() {
  local kind="$1" name value="$3" signing="${4:-}"
  name="$(_identity_lc "$2")"
  case "$name" in
    user.name | user.email) return 0 ;;
    user.signingkey | commit.gpgsign | tag.gpgsign)
      [ "$signing" = keep ] && return 1
      return 0
      ;;
    gpg.format)
      [ "$signing" = gpg ] && return 0
      return 1
      ;;
  esac
  [ "$kind" = local ] || return 1
  case "$name" in
    includeif.gitdir:*.path)
      # shellcheck disable=SC2088 # the literal ~/ form maclift writes
      case "$value" in "~/.gitconfig.alt" | "$MACLIFT_HOME/.gitconfig.alt") return 0 ;; esac
      ;;
  esac
  return 1
}

# _identity_carry <kind> <old> <new> [<signing>]: appends every setting of the old file
# that maclift does not own (see _identity_owned) to new, in file order,
# with --add so keys with several values keep all of them. Comments and
# layout are not kept; values are. A missing old file carries nothing. An
# old file git cannot read is reported on stderr and carries nothing (it is
# still backed up before being replaced). Returns 1 if a write fails.
_identity_carry() {
  local kind="$1" old="$2" new="$3" signing="${4:-}" entry name value
  [ -f "$old" ] || return 0
  if ! git config -f "$old" --list >/dev/null 2>&1; then
    echo "maclift: could not read the settings in $old; only maclift's own settings are written; signing settings in it could not be kept; the old file is backed up" >&2
    return 0
  fi
  while IFS= read -r -d '' entry; do
    case "$entry" in
      *$'\n'*)
        name="${entry%%$'\n'*}"
        value="${entry#*$'\n'}"
        ;;
      *)
        # A key with no "= value" means true.
        name="$entry"
        value=true
        ;;
    esac
    _identity_owned "$kind" "$name" "$value" "$signing" && continue
    git config -f "$new" --add "$name" "$value" || return 1
  done < <(git config -f "$old" --null --list 2>/dev/null)
}

# _identity_foreign_signing <conf_key> <file>: succeeds when user.conf has
# no conf_key line, and file signs with a key in another format than GPG
# (gpg.format ssh or x509 with a non-empty user.signingkey). maclift then
# leaves that signing setup exactly as it is.
_identity_foreign_signing() {
  local fmt key
  conf_get "$(_identity_conf)" "$1" >/dev/null 2>&1 && return 1
  [ -f "$2" ] || return 1
  fmt="$(git config -f "$2" gpg.format 2>/dev/null)" || return 1
  case "$(_identity_lc "$fmt")" in "" | openpgp) return 1 ;; esac
  key="$(git config -f "$2" user.signingkey 2>/dev/null)" || return 1
  [ -n "$key" ]
}

# _identity_sign_mode <kind> <conf_key> <file>: prints how signing is
# handled: "gpg" when conf_key has a value (maclift writes GPG signing).
# With no conf_key line at all: "keep" in .gitconfig.local (kind local),
# so whatever signing settings the file has (ssh/x509, or gpgsign with no
# key, signing by email) are carried over unchanged; in .gitconfig.alt
# "keep" only for hand-made ssh/x509 signing with a key (see
# _identity_foreign_signing), else nothing, which writes signing off and a
# blank key so the alt identity never signs with the personal key.
# conf_key="" prints nothing: signing off on purpose.
_identity_sign_mode() {
  local key
  if key="$(conf_get "$(_identity_conf)" "$2" 2>/dev/null)"; then
    [ -n "$key" ] && echo gpg
    return 0
  fi
  if [ "$1" = local ] || _identity_foreign_signing "$2" "$3"; then
    echo keep
  fi
  return 0
}

# _identity_adoptable <conf_key> <file>: prints the user.signingkey of file
# and succeeds when user.conf has no conf_key line at all and that key is
# not empty (and not an ssh/x509 key, see _identity_foreign_signing). A
# present but empty conf_key means signing is off on purpose.
_identity_adoptable() {
  local key
  conf_get "$(_identity_conf)" "$1" >/dev/null 2>&1 && return 1
  [ -f "$2" ] || return 1
  _identity_foreign_signing "$1" "$2" && return 1
  key="$(git config -f "$2" user.signingkey 2>/dev/null)" || return 1
  [ -n "$key" ] || return 1
  printf '%s\n' "$key"
}

# _identity_adopt <conf_key> <file> <dry_run>: when file has a signing key
# user.conf does not know about (see _identity_adoptable), saves it to
# user.conf so the re-render keeps signing, and says so. A dry run only
# says what it would do. Returns 1 if saving fails.
_identity_adopt() {
  local conf_key="$1" file="$2" dry_run="${3:-0}" key
  key="$(_identity_adoptable "$conf_key" "$file")" || return 0
  if [ "$dry_run" = "1" ]; then
    echo "would keep commit signing with key $key and save it to user.conf as $conf_key"
    return 0
  fi
  conf_set "$(_identity_conf)" "$conf_key" "$key" || {
    echo "maclift: could not save $conf_key to user.conf" >&2
    return 1
  }
  if [ "$(git config -f "$file" --bool commit.gpgsign 2>/dev/null)" = true ]; then
    maclift_note "Kept commit signing with key $key; saved it to user.conf as $conf_key (set it to \"\" to turn signing off)"
  else
    maclift_note "Kept signing key $key and turned on commit and tag signing; saved it to user.conf as $conf_key (set it to \"\" to turn signing off)"
  fi
}

# identity_render_gitconfig <dry_run>: writes $MACLIFT_HOME/.gitconfig.local.
# Name and email come from user.conf. With MACLIFT_SIGNING_KEY set it also
# turns on commit/tag signing; with no MACLIFT_SIGNING_KEY line at all a
# signing key already in the file is first saved to user.conf (see
# _identity_adopt); MACLIFT_SIGNING_KEY="" means no signing. Other signing
# settings with no MACLIFT_SIGNING_KEY line (ssh/x509, or gpgsign without
# a key) are kept as is.
# Every other setting already in the file is kept (see _identity_carry).
# With MACLIFT_ALT_DIR set it ends with an includeIf for that folder, so the
# second identity (~/.gitconfig.alt) overrides everything above it.
# Existing file that differs is backed up first; identical file is left alone.
identity_render_gitconfig() {
  local dry_run="${1:-0}" conf name email signing mode target tmp alt_dir
  conf="$(_identity_conf)"
  target="$MACLIFT_HOME/.gitconfig.local"
  name="$(conf_get "$conf" MACLIFT_NAME 2>/dev/null || true)"
  email="$(conf_get "$conf" MACLIFT_EMAIL 2>/dev/null || true)"
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
  _identity_adopt MACLIFT_SIGNING_KEY "$target" "$dry_run" || return 1
  if [ "$dry_run" = "1" ]; then
    echo "would write $target"
    return 0
  fi
  signing="$(conf_get "$conf" MACLIFT_SIGNING_KEY 2>/dev/null || true)"
  mode="$(_identity_sign_mode local MACLIFT_SIGNING_KEY "$target")"
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
  _identity_carry local "$target" "$tmp" "$mode" || { rm -f "$tmp"; return 1; }
  if [ -n "$alt_dir" ]; then
    # --add: the user's own include paths for the same folder stay too.
    # shellcheck disable=SC2088 # git expands the literal ~/ itself
    if ! git config -f "$tmp" --add "includeIf.gitdir:${alt_dir}/.path" "~/.gitconfig.alt"; then
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

# _identity_alt_build <file> [<old>]: writes the second identity config
# into file (overwriting it), keeping every setting of old (default
# $MACLIFT_HOME/.gitconfig.alt) that maclift does not own. With
# MACLIFT_ALT_SIGNING_KEY it signs commits and tags with that key; with no
# MACLIFT_ALT_SIGNING_KEY line it uses a non-empty key found in old (the one
# identity_render_alt adopts); hand-made ssh/x509 signing in old is kept as
# is; otherwise it turns both off and blanks user.signingkey so work in
# that folder never uses the personal key.
# Returns 1 if a value is missing or git config fails.
_identity_alt_build() {
  local file="$1" old="${2:-$MACLIFT_HOME/.gitconfig.alt}" conf name email key mode
  conf="$(_identity_conf)"
  name="$(conf_get "$conf" MACLIFT_ALT_NAME 2>/dev/null || true)"
  email="$(conf_get "$conf" MACLIFT_ALT_EMAIL 2>/dev/null || true)"
  key="$(conf_get "$conf" MACLIFT_ALT_SIGNING_KEY 2>/dev/null)" \
    || key="$(_identity_adoptable MACLIFT_ALT_SIGNING_KEY "$old")" \
    || key=""
  mode="$(_identity_sign_mode alt MACLIFT_ALT_SIGNING_KEY "$old")"
  [ -n "$key" ] && mode=gpg
  _identity_alt_require || return 1
  printf '# Generated by maclift from ~/.config/maclift/user.conf. Name, email and\n# signing come from user.conf; other settings added here are kept.\n# Second git identity, used inside the folder named by MACLIFT_ALT_DIR.\n' >"$file" || return 1
  git config -f "$file" user.name "$name" || return 1
  git config -f "$file" user.email "$email" || return 1
  if [ "$mode" = keep ]; then
    : # ssh/x509 signing set up by hand: carried over below
  elif [ -n "$key" ]; then
    git config -f "$file" user.signingkey "$key" \
      && git config -f "$file" commit.gpgsign true \
      && git config -f "$file" tag.gpgsign true \
      || return 1
  else
    # No alt key: switch signing off and blank the key, so an explicit -S
    # fails instead of signing as the personal identity.
    git config -f "$file" commit.gpgsign false \
      && git config -f "$file" tag.gpgsign false \
      && git config -f "$file" user.signingkey "" \
      || return 1
  fi
  _identity_carry alt "$old" "$file" "$mode"
}

# identity_alt_current: 0 when $MACLIFT_HOME/.gitconfig.alt is exactly what
# user.conf renders to now (with the file's own extra settings kept), and
# there is no signing key waiting to be saved to user.conf. Writes only a
# temp file outside the home folder.
identity_alt_current() {
  local tmp rc=0
  [ -f "$MACLIFT_HOME/.gitconfig.alt" ] || return 1
  _identity_adoptable MACLIFT_ALT_SIGNING_KEY "$MACLIFT_HOME/.gitconfig.alt" >/dev/null && return 1
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
# user.conf (see _identity_alt_build), first saving a hand-set signing key
# to user.conf (see _identity_adopt). An identical file is left alone.
identity_render_alt() {
  local dry_run="${1:-0}" target tmp
  target="$MACLIFT_HOME/.gitconfig.alt"
  _identity_alt_require || return 1
  _identity_adopt MACLIFT_ALT_SIGNING_KEY "$target" "$dry_run" || return 1
  if [ "$dry_run" = "1" ]; then
    echo "would write $target"
    return 0
  fi
  tmp="$(mktemp "$target.XXXXXX")" || return 1
  _identity_alt_build "$tmp" || { rm -f "$tmp"; return 1; }
  _identity_install "$tmp" "$target"
}
