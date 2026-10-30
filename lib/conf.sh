#!/usr/bin/env bash
#
# maclift config parser: one KEY="value" per line. Files are parsed with
# plain string operations and never sourced or eval'ed.
# Format: KEY matches ^[A-Z][A-Z0-9_]*$; inside the value only \" and \\
# are escapes; '#' comments and blank lines are ignored; any other line is
# ignored with a warning on stderr.
# bash 3.2 compatible. Meant to be sourced.

# Character classes are spelled out: ranges like A-Z are locale-dependent.
# Parses one line. Sets _CONF_KEY and _CONF_VAL. Returns 0 for a valid
# assignment, 1 for a comment/blank line (silent), 2 for an invalid line.
_conf_parse_line() {
  local line="$1" key rest body c out="" i n esc=0
  case "$line" in
    '' | '#'*) return 1 ;;
  esac
  case "$line" in
    *=*) ;;
    *) return 2 ;;
  esac
  key="${line%%=*}"
  rest="${line#*=}"
  case "$key" in
    '' | [!ABCDEFGHIJKLMNOPQRSTUVWXYZ]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 2 ;;
  esac
  case "$rest" in
    '"'*'"') ;;
    *) return 2 ;;
  esac
  body="${rest#\"}"
  body="${body%\"}"
  n=${#body}
  i=0
  while [ "$i" -lt "$n" ]; do
    c="${body:$i:1}"
    if [ "$esc" = 1 ]; then
      case "$c" in
        '"' | '\') out="$out$c" ;;
        *) return 2 ;;
      esac
      esc=0
    else
      case "$c" in
        '\') esc=1 ;;
        '"') return 2 ;; # unescaped quote inside the value
        *) out="$out$c" ;;
      esac
    fi
    i=$((i + 1))
  done
  [ "$esc" = 0 ] || return 2 # dangling backslash (it escaped the closing quote)
  _CONF_KEY="$key"
  _CONF_VAL="$out"
  return 0
}

# Calls "$2" for each valid assignment; warns about invalid lines.
# Usage: _conf_each <file> <callback>
_conf_each() {
  local file="$1" cb="$2" line n=0 rc
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    rc=0
    _conf_parse_line "$line" || rc=$?
    case "$rc" in
      0) "$cb" ;;
      2) echo "maclift: $file: ignored line $n" >&2 ;;
    esac
  done <"$file"
  return 0
}

_conf_cb_get() {
  if [ "$_CONF_KEY" = "$_CONF_WANT" ]; then
    _CONF_FOUND=1
    _CONF_RESULT="$_CONF_VAL" # last assignment wins
  fi
}

_conf_cb_keys() {
  printf '%s\n' "$_CONF_KEY"
}

# Prints the value of KEY; returns 1 if the key or file is missing.
conf_get() {
  _CONF_WANT="$2"
  _CONF_FOUND=0
  _CONF_RESULT=""
  _conf_each "$1" _conf_cb_get || return 1
  [ "$_CONF_FOUND" = 1 ] || return 1
  printf '%s\n' "$_CONF_RESULT"
}

# Prints the valid keys, one per line.
conf_keys() {
  _conf_each "$1" _conf_cb_keys
}

# Sets KEY to value (replaces the key's line or appends), atomically.
conf_set() {
  local file="$1" key="$2" value="$3" esc tmp line found=0 rc
  case "$key" in
    '' | [!ABCDEFGHIJKLMNOPQRSTUVWXYZ]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      echo "maclift: invalid config key: $key" >&2
      return 1
      ;;
  esac
  case "$value" in
    *$'\n'* | *$'\r'*)
      echo "maclift: config value for $key must be a single line" >&2
      return 1
      ;;
  esac
  esc="${value//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  mkdir -p "$(dirname "$file")" || return 1
  tmp="$(mktemp "$file.XXXXXX")" || return 1
  {
    if [ -f "$file" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        rc=0
        _conf_parse_line "$line" || rc=$?
        if [ "$rc" = 0 ] && [ "$_CONF_KEY" = "$key" ]; then
          if [ "$found" = 0 ]; then
            printf '%s="%s"\n' "$key" "$esc"
            found=1
          fi
          continue # drop duplicates of this key
        fi
        printf '%s\n' "$line"
      done <"$file"
    fi
    if [ "$found" = 0 ]; then
      printf '%s="%s"\n' "$key" "$esc"
    fi
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$file"
}
