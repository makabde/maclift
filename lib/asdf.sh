#!/usr/bin/env bash
#
# maclift asdf pins: resolve exact language versions once, keep them
# ("a lockfile for your Mac's toolchain"). Pins live in
# $MACLIFT_CONFIG_DIR/tool-versions in asdf .tool-versions format and are
# parsed with plain string ops, never sourced. bash 3.2 compatible.
# Meant to be sourced after lib/core.sh, lib/catalog.sh and lib/dotfiles.sh.

_pins_file() { printf '%s\n' "$MACLIFT_CONFIG_DIR/tool-versions"; }

_pins_asdf() { "${MACLIFT_ASDF:-asdf}" "$@"; }

# _pins_read <file> <plugin>: prints the first version listed for plugin.
_pins_read() {
  local file="$1" plugin="$2" line name ver _noglob
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '#'* | '') continue ;; esac
    # Split on whitespace without glob expansion; restore -f afterwards.
    case "$-" in *f*) _noglob=1 ;; *) _noglob=0; set -f ;; esac
    # shellcheck disable=SC2086
    set -- $line
    [ "$_noglob" = 1 ] || set +f
    name="${1:-}"
    ver="${2:-}"
    if [ "$name" = "$plugin" ] && [ -n "$ver" ]; then
      printf '%s\n' "$ver"
      return 0
    fi
  done <"$file"
  return 1
}

# _pins_version_ok <string>: 0 if it looks like a version (asdf can print an
# error message with exit 0, which must never become a pin).
_pins_version_ok() {
  [[ $1 =~ ^[0-9][0-9A-Za-z._+-]*$ ]]
}

# pins_plugin_add <plugin>: adds the asdf plugin from its catalog URL. Used by
# pins_resolve and the asdf item install.
pins_plugin_add() {
  _pins_asdf plugin add "$1" "$(catalog_item_field "asdf:$1" args 2>/dev/null || true)"
}

# _pins_plugin_present <plugin>: 0 if `asdf plugin list` lists it.
_pins_plugin_present() {
  local list nl='
'
  list="$(_pins_asdf plugin list 2>/dev/null)" || return 1
  list="$(printf '%s\n' "$list" | tr -d ' \r')"
  case "$nl$list$nl" in *"$nl$1$nl"*) return 0 ;; esac
  return 1
}

# pins_get <plugin>: prints the pinned version.
pins_get() {
  _pins_read "$(_pins_file)" "$1"
}

# _pins_rank <plugin>: sort rank, erlang elixir nodejs python then others.
_pins_rank() {
  case "$1" in
    erlang) echo 1 ;;
    elixir) echo 2 ;;
    nodejs) echo 3 ;;
    python) echo 4 ;;
    *) echo 5 ;;
  esac
}

# _pins_store <plugin> <version>: records a pin, keeping the file ordered.
_pins_store() {
  local plugin="$1" version="$2" file tmp line name
  file="$(_pins_file)"
  tmp="$(mktemp)" || return 1
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      name="${line%% *}"
      [ "$name" = "$plugin" ] && continue
      [ -n "$line" ] && printf '%s %s\n' "$(_pins_rank "$name")" "$line" >>"$tmp"
    done <"$file"
  fi
  printf '%s %s %s\n' "$(_pins_rank "$plugin")" "$plugin" "$version" >>"$tmp"
  # Stable ordering: rank, then name. Strip the rank column afterwards.
  sort -k1,1n -k2,2 "$tmp" | cut -d' ' -f2- >"$file"
  rm -f "$tmp"
}

# _pins_newest: reads versions (X.Y.Z[-pre][-otp-N]) on stdin, prints the
# newest. No sort -V (not on older macOS). The numbers decide first; with the
# same numbers a pre-release (-rc.1, -beta, a letter after the numbers) is
# older than the release. -otp-N is ignored here (see pins_is_newer).
_pins_newest() {
  awk '
    # cmp: 1 if a is newer than b, -1 if older, 0 if the same.
    function cmp(a, b,   na, nb, ra, rb, x, y, n, m, i, p, q, pa, pb) {
      na = ""; ra = a
      if (match(a, /^[0-9][0-9.]*/)) { na = substr(a, 1, RLENGTH); ra = substr(a, RLENGTH + 1) }
      nb = ""; rb = b
      if (match(b, /^[0-9][0-9.]*/)) { nb = substr(b, 1, RLENGTH); rb = substr(b, RLENGTH + 1) }
      n = split(na, x, "."); m = split(nb, y, ".")
      for (i = 1; i <= (n > m ? n : m); i++) {
        p = (i <= n) ? x[i] + 0 : 0; q = (i <= m) ? y[i] + 0 : 0
        if (p > q) return 1
        if (p < q) return -1
      }
      # Two pre-releases compare as strings, so rc.2 ranks above rc.10. Rare:
      # asdf latest returns stable versions.
      pa = (ra ~ /[A-Za-z]/); pb = (rb ~ /[A-Za-z]/)
      if (pa && !pb) return -1
      if (!pa && pb) return 1
      if (pa && pb && ra != rb) return (ra > rb) ? 1 : -1
      return 0
    }
    {
      v = $0; core = v; sub(/-otp-[0-9]+$/, "", core)
      if (best == "" || cmp(core, bestcore) > 0) { best = v; bestcore = core }
    }
    END { if (best != "") print best }
  '
}

# _pins_elixir: newest stable elixir built for the erlang pin's OTP major.
_pins_elixir() {
  local erl major
  erl="$(pins_get erlang)" || {
    log_line "elixir pin needs an erlang pin first" 2>/dev/null
    return 1
  }
  major="${erl%%.*}"
  _pins_asdf list all elixir 2>/dev/null |
    tr -d ' \r' |
    grep -E "^[0-9]+\.[0-9]+\.[0-9]+-otp-${major}\$" |
    _pins_newest
}

# pins_latest <plugin>: prints the newest stable version. elixir is matched
# against the current erlang pin; everything else asks asdf. Returns 1 when
# the answer is not a version (asdf may print an error and exit 0).
pins_latest() {
  local v
  if [ "$1" = elixir ]; then
    v="$(_pins_elixir)" || v=""
  else
    v="$(_pins_asdf latest "$1" 2>/dev/null | head -n 1 | tr -d '\r')" || v=""
    # Trim surrounding blanks only; inner spaces mean it is not a version.
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
  fi
  _pins_version_ok "$v" || return 1
  printf '%s\n' "$v"
}

# pins_is_newer <old> <new>: 0 when new is strictly newer. Equal numbers are
# not newer, except X.Y.Z-otp-N builds of the same X.Y.Z with a higher N.
pins_is_newer() {
  local old="$1" new="$2" newest
  [ "$old" != "$new" ] || return 1
  case "$old" in
    *-otp-[0-9]*)
      case "$new" in
        *-otp-[0-9]*)
          if [ "${old%-otp-*}" = "${new%-otp-*}" ]; then
            [ "${new##*-otp-}" -gt "${old##*-otp-}" ] 2>/dev/null
            return
          fi
          ;;
      esac
      ;;
  esac
  newest="$(printf '%s\n%s\n' "$old" "$new" | _pins_newest)"
  [ "$newest" = "$new" ]
}

# _pins_say <text>: a note for the user (the run's notes when set, else stderr).
_pins_say() {
  if [ -n "${MACLIFT_NOTES:-}" ]; then
    maclift_note "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

# pins_resolve [--dry-run] <plugin>...: writes a pin for each plugin that
# lacks one: the version in ~/.tool-versions (any token but "system", e.g.
# pypy3.10-7.3.12 or ref:main), else asdf's latest. A plugin asdf does not
# have yet is added first. A dry run never stores a pin and never adds a
# plugin; it prints "would pin <plugin> <version>" instead.
pins_resolve() {
  local plugin ver dry=0
  if [ "${1:-}" = --dry-run ]; then
    dry=1
    shift
  fi
  for plugin in "$@"; do
    if pins_get "$plugin" >/dev/null 2>&1; then
      continue
    fi
    # elixir depends on the erlang pin, so erlang always goes first.
    if [ "$plugin" = elixir ] && ! pins_get erlang >/dev/null 2>&1; then
      if [ "$dry" = 1 ]; then
        # The elixir build follows the erlang pin, which a dry run never stores.
        pins_resolve --dry-run erlang || return 1
        printf 'would pin %s to its latest version for that erlang\n' "$plugin"
        continue
      fi
      pins_resolve erlang || return 1
    fi
    ver="$(_pins_read "$MACLIFT_HOME/.tool-versions" "$plugin" || true)"
    if [ "$ver" = system ]; then
      # shellcheck disable=SC2088 # literal ~ in the message
      _pins_say "~/.tool-versions says $plugin system; pinning the latest version instead"
      ver=""
    fi
    if [ -z "$ver" ] && ! _pins_plugin_present "$plugin"; then
      if [ "$dry" = 1 ]; then
        printf 'would pin %s to its latest version\n' "$plugin"
        continue
      fi
      if ! pins_plugin_add "$plugin"; then
        printf 'could not add the asdf plugin %s\n' "$plugin" >&2
        return 1
      fi
      log_line "added asdf plugin $plugin"
    fi
    if [ -z "$ver" ]; then
      ver="$(pins_latest "$plugin" || true)"
    fi
    if [ -z "$ver" ]; then
      printf 'could not resolve a version for %s\n' "$plugin" >&2
      return 1
    fi
    if [ "$dry" = 1 ]; then
      printf 'would pin %s %s\n' "$plugin" "$ver"
      continue
    fi
    _pins_store "$plugin" "$ver" || return 1
    log_line "pinned $plugin $ver"
  done
}

# pins_apply <dry_run>: merges the pins into $MACLIFT_HOME/.tool-versions,
# keeping unrelated lines and comments; backs the old file up if it changes.
pins_apply() {
  local dry="${1:-0}" pins target tmp line name ver pv pname seen _noglob
  pins="$(_pins_file)"
  target="$MACLIFT_HOME/.tool-versions"
  [ -f "$pins" ] || return 0
  tmp="$(mktemp)" || return 1
  seen=" "
  if [ -f "$target" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      # Split on whitespace without glob expansion; restore -f afterwards.
      case "$-" in *f*) _noglob=1 ;; *) _noglob=0; set -f ;; esac
      # shellcheck disable=SC2086
      set -- $line
      [ "$_noglob" = 1 ] || set +f
      name="${1:-}"
      case "$line" in
        '#'* | '') printf '%s\n' "$line" >>"$tmp"; continue ;;
      esac
      if pv="$(_pins_read "$pins" "$name")"; then
        seen="$seen$name "
        ver="${2:-}"
        if [ "$ver" = "$pv" ]; then
          printf '%s\n' "$line" >>"$tmp"
        else
          printf '%s %s\n' "$name" "$pv" >>"$tmp"
        fi
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$target"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '#'* | '') continue ;; esac
    pname="${line%% *}"
    case "$seen" in *" $pname "*) continue ;; esac
    printf '%s\n' "$line" >>"$tmp"
  done <"$pins"
  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    return 0
  fi
  if [ "$dry" = 1 ]; then
    printf 'would write %s\n' "$target"
    rm -f "$tmp"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    dotfiles_run_id
    backup_path "$target" >/dev/null || { rm -f "$tmp"; return 1; }
  fi
  cp "$tmp" "$target" && rm -f "$tmp"
  printf 'wrote %s\n' "$target"
}
