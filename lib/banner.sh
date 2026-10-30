#!/usr/bin/env bash
#
# maclift banner and launch animation. Needs lib/ui.sh (ui_mode, ui_color).
# bash 3.2 compatible. Meant to be sourced.

_banner_oneline() { printf '🚀 maclift · liftoff for your new Mac\n'; }

banner_show() {
  local LC_ALL=en_US.UTF-8
  local cols="${COLUMNS:-}" osv S F1 F2 F3 P W D R
  [ -n "$cols" ] || cols="$(tput cols 2>/dev/null || echo 80)"
  if [ "$cols" -lt 66 ] 2>/dev/null \
    || { [ "$(ui_mode)" = plain ] && [ -z "$(ui_color 0 0 0)" ]; }; then
    _banner_oneline
    return 0
  fi
  osv="$(${MACLIFT_SW_VERS:-sw_vers} -productVersion 2>/dev/null || echo unknown)"
  S="$(ui_color 186 194 222)"
  P="$(ui_color 203 166 247)"
  F1="$(ui_color 249 226 175)"
  F2="$(ui_color 250 179 135)"
  F3="$(ui_color 243 139 168)"
  W="$F2"
  D=""
  R=""
  if [ -n "$S" ]; then D=$'\033[2m'; R=$'\033[0m'; fi
  cat <<EOT
${S}          /\\${R}
${S}         /  \\${R}
${S}        |    |${R}
${S}        | ${P}()${S} |${R}         ${W}m a c l i f t${R}
${S}        |    |${R}         ${D}─────────────────────${R}
${S}       /|    |\\${R}        liftoff for your new Mac
${S}      /_|____|_\\${R}       ${D}v${MACLIFT_VERSION:-0.0.0}  ·  macOS ${osv}${R}
${F1}         )  (${R}
${F2}        ( )( )${R}
${F3}         '  '${R}
EOT
}

_banner_restore() { printf '\033[?25h\033[?1049l'; }

# Runs in a subshell with its own traps, so the caller's traps are untouched.
# INT/TERM restore the screen and stop with status 130.
banner_launch() {
  [ "$(ui_mode)" = gum ] || return 0
  (
    LC_ALL=en_US.UTF-8
    S="$(ui_color 186 194 222)"
    P="$(ui_color 203 166 247)"
    F1="$(ui_color 249 226 175)"
    F2="$(ui_color 250 179 135)"
    D=$'\033[2m'
    R=$'\033[0m'
    trap _banner_restore EXIT
    trap 'exit 130' INT TERM
    printf '\033[?1049h\033[?25l'
    for h in 0 0 1 2 3 5 7 9 12 15; do
      printf '\033[H\033[2J'
      printf '%s\n' "${S}     /\\${R}" "${S}    /  \\${R}" "${S}    |${P}()${S}|${R}" \
        "${S}   /|__|\\${R}" "${F1}    )()(${R}" "${F2}   ( )( )${R}"
      for ((k = 0; k < h; k++)); do printf '\n'; done
      printf '%s\n' "${D}  ══════════${R}"
      sleep 0.12
    done
    sleep 0.4
    _banner_restore
    trap - EXIT
    printf '%s✓ Your Mac is ready. 🚀%s\n' "$F1" "$R"
  )
}
