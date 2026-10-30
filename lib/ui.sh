#!/usr/bin/env bash
#
# maclift UI: gum when available, plain text otherwise.
# bash 3.2 compatible. Meant to be sourced.
#
# In plain mode, prompts and menus go to stderr and only answers go to
# stdout, so $(ui_input ...) captures just the value.

# Terminal state is recorded once at source time: inside $(ui_mode) stdout is a
# pipe, so -t 1 would always be false there.
_UI_TTY=0
[ -t 1 ] && _UI_TTY=1

# MACLIFT_ASSUME_TTY=1 forces the TTY condition. Test-only.
_ui_is_tty() { [ "${MACLIFT_ASSUME_TTY:-}" = "1" ] || [ "$_UI_TTY" = "1" ]; }

_ui_gum() { "${MACLIFT_GUM:-gum}" "$@"; }

# Prints "gum" or "plain".
ui_mode() {
  if [ "${MACLIFT_PLAIN:-}" = "1" ] || [ -n "${NO_COLOR:-}" ] || [ -n "${CI:-}" ] \
    || ! _ui_is_tty || ! command -v "${MACLIFT_GUM:-gum}" >/dev/null 2>&1; then
    echo plain
  else
    echo gum
  fi
}

# Prints an escape code for a foreground colour: true colour, 256 colour or
# nothing (always nothing when output is not a terminal).
ui_color() {
  local r="$1" g="$2" b="$3" colors
  [ -z "${NO_COLOR:-}" ] || return 0
  _ui_is_tty || return 0
  case "${COLORTERM:-}" in
    truecolor | 24bit)
      printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
      return 0
      ;;
  esac
  colors="$(tput colors 2>/dev/null || echo 0)"
  if [ "$colors" -ge 256 ] 2>/dev/null; then
    printf '\033[38;5;%dm' "$((16 + 36 * (r * 5 / 255) + 6 * (g * 5 / 255) + b * 5 / 255))"
  fi
}

_ui_reset() { [ -n "$(ui_color 0 0 0)" ] && printf '\033[0m' || true; }

# ui_input <prompt> <default>
ui_input() {
  local prompt="$1" default="${2:-}" line
  if [ "$(ui_mode)" = gum ]; then
    _ui_gum input --prompt "$prompt: " --value "$default"
    return
  fi
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r line || true
  printf '%s\n' "${line:-$default}"
}

# ui_choose_many <header> <preselected-csv> <item>...
ui_choose_many() {
  local header="$1" pre="$2" item i n line tok sel
  shift 2
  if [ "$(ui_mode)" = gum ]; then
    _ui_gum choose --no-limit --header "$header" --selected "$pre" "$@"
    return
  fi
  n=$#
  sel=",$pre,"
  while :; do
    printf '%s\n' "$header" >&2
    i=0
    for item in "$@"; do
      i=$((i + 1))
      case "$sel" in
        *",$item,"*) printf '  %d) [x] %s\n' "$i" "$item" >&2 ;;
        *) printf '  %d) [ ] %s\n' "$i" "$item" >&2 ;;
      esac
    done
    printf 'Numbers to toggle (Enter to accept): ' >&2
    line=""
    IFS= read -r line || line=""
    [ -n "$line" ] || break
    for tok in $(printf '%s' "$line" | tr ',' ' '); do
      case "$tok" in
        '' | *[!0-9]*) continue ;;
      esac
      [ "$tok" -ge 1 ] && [ "$tok" -le "$n" ] || continue
      eval "item=\${$tok}"
      case "$sel" in
        *",$item,"*) sel="${sel%%,"$item",*},${sel#*,"$item",}" ;;
        *) sel="${sel}${item}," ;;
      esac
    done
  done
  for item in "$@"; do
    case "$sel" in *",$item,"*) printf '%s\n' "$item" ;; esac
  done
}

# ui_confirm <prompt> <default y|n>; returns 0 for yes, 1 for no.
ui_confirm() {
  local prompt="$1" default="${2:-n}" line hint
  if [ "$(ui_mode)" = gum ]; then
    if [ "$default" = y ]; then
      _ui_gum confirm --default=true "$prompt"
    else
      _ui_gum confirm --default=false "$prompt"
    fi
    return
  fi
  if [ "$default" = y ]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s]: ' "$prompt" "$hint" >&2
  IFS= read -r line || line=""
  case "${line:-$default}" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ui_choose_one <header> <option>...
ui_choose_one() {
  local header="$1" item i line
  shift
  if [ "$(ui_mode)" = gum ]; then
    _ui_gum choose --header "$header" "$@"
    return
  fi
  printf '%s\n' "$header" >&2
  i=0
  for item in "$@"; do
    i=$((i + 1))
    printf '  %d) %s\n' "$i" "$item" >&2
  done
  printf 'Choice [1]: ' >&2
  IFS= read -r line || line=""
  line="${line:-1}"
  case "$line" in
    '' | *[!0-9]*) line=1 ;;
  esac
  [ "$line" -ge 1 ] && [ "$line" -le "$#" ] || line=1
  eval "printf '%s\\n' \"\${$line}\""
}

# ui_box <text>...
ui_box() {
  local t
  if [ "$(ui_mode)" = gum ]; then
    _ui_gum style --border rounded --padding "0 2" "$@"
    return
  fi
  for t in "$@"; do printf '== %s ==\n' "$t"; done
}

# ui_status <run|ok|skip|fail|need> <label> [seconds | reason for need]
ui_status() {
  local state="$1" label="$2" secs="${3:-}" suffix="" c r
  r="$(_ui_reset)"
  [ "$state" = need ] || [ -z "$secs" ] || suffix=" (${secs}s)"
  case "$state" in
    run) printf '%s⠋ %s%s\n' "$(ui_color 249 226 175)" "$label" "$r" ;;
    ok) printf '%s✓%s %s%s\n' "$(ui_color 166 227 161)" "$r" "$label" "$suffix" ;;
    skip) printf '%s✓ already installed%s %s\n' "$(ui_color 166 227 161)" "$r" "$label" ;;
    need) printf '%s– skipped %s (needs %s)%s\n' "$(ui_color 249 226 175)" "$label" "$secs" "$r" ;;
    fail) c="$(ui_color 243 139 168)"; printf '%s✗%s %s%s\n' "$c" "$r" "$label" "$suffix" ;;
    *) printf '%s\n' "$label" ;;
  esac
}

# ui_progress <done> <total> <label>
ui_progress() {
  local done="$1" total="$2" label="$3" cells=10 filled i bar=""
  if [ "$total" -gt 0 ] 2>/dev/null; then
    filled=$((done * cells / total))
  else
    filled=0
  fi
  [ "$filled" -le "$cells" ] || filled=$cells
  for ((i = 0; i < cells; i++)); do
    if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
  done
  printf '[%s] %s/%s · Installing %s\n' "$bar" "$done" "$total" "$label"
}
