#!/usr/bin/env bash
#
# maclift doctor: read-only health checks for a maclift-configured Mac.
# Each check prints "✓ label" or "✗ label" plus a "  fix: ..." line and
# returns 0/1; cmd_doctor runs them all and never stops early. Nothing is
# changed. bash 3.2 compatible.
# Meant to be sourced after lib/core.sh, conf.sh, catalog.sh, selection.sh,
# ui.sh, dotfiles.sh, identity.sh, asdf.sh and bootstrap.sh.
#
# Test overrides: MACLIFT_LOGIN_SHELL (login shell path), MACLIFT_DOCTOR_PATH
# (the PATH a new terminal would get), MACLIFT_DOCTOR_SHELL_TIMEOUT (seconds
# to wait for the login shell, default 10), MACLIFT_BREW, MACLIFT_ASDF,
# MACLIFT_GPG.

DOCTOR_FAILS=0
DOCTOR_CHECKS="brew path shell repo_link links asdf toolchains git ssh"
NL_DOCTOR='
'

# _doctor_ok <label>
_doctor_ok() {
  ui_status ok "$1"
}

# _doctor_fail <label> <fix>: prints the problem and how to fix it; counts it.
_doctor_fail() {
  ui_status fail "$1"
  printf '  fix: %s\n' "$2"
  DOCTOR_FAILS=$((DOCTOR_FAILS + 1))
  return 1
}

# _doctor_note <label> [hint]: an observation that is not a problem. Printed
# with a bullet, never counted in DOCTOR_FAILS.
_doctor_note() {
  ui_status note "$1"
  [ -z "${2:-}" ] || printf '  hint: %s\n' "$2"
  return 0
}

# The user's login shell: override, else the directory service, else $SHELL.
_doctor_login_shell() {
  local sh="${MACLIFT_LOGIN_SHELL:-}"
  if [ -z "$sh" ]; then
    sh="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{ print $2 }')"
  fi
  printf '%s\n' "${sh:-${SHELL:-}}"
}

# _doctor_shell_timeout: seconds to wait for the login shell:
# MACLIFT_DOCTOR_SHELL_TIMEOUT, or 10 when that is empty, not a number, or 0.
_doctor_shell_timeout() {
  local t="${MACLIFT_DOCTOR_SHELL_TIMEOUT:-}"
  case "$t" in '' | *[!0-9]*) t=10 ;; esac
  [ "$((10#$t))" -gt 0 ] 2>/dev/null || t=10
  printf '%s\n' "$((10#$t))"
}

# _doctor_login_path <shell>: prints the PATH that shell sets up as an
# interactive login shell, like a new terminal (asdf shims are often added in
# .zshrc, which only interactive shells read). The PATH is printed behind a
# marker and only that line is taken, so prompt or terminal escape output
# cannot leak in. Gives up after _doctor_shell_timeout seconds: a slow
# ~/.zprofile or ~/.zshrc must not hang doctor. Returns 2 on timeout, 1 on any
# other failure. bash 3.2 and macOS have no timeout command, so a watcher
# job kills the shell. Only the shell itself is killed: a child it started
# (say a sleep in .zshrc) may live on until it ends by itself.
_doctor_login_path() {
  local sh="$1" limit tmp pid p rc=0
  limit="$(_doctor_shell_timeout)"
  tmp="$(mktemp -d)" || return 1
  # shellcheck disable=SC2016 # the login shell expands $PATH
  env -i HOME="$MACLIFT_HOME" "$sh" -ilc 'printf "\n__MACLIFT_PATH__=%s\n" "$PATH"' >"$tmp/out" 2>/dev/null </dev/null &
  pid=$!
  # The watcher checks once a second, so it ends soon after the shell does.
  # Its output goes to /dev/null so $(...) callers never wait for it.
  (
    i=0
    while [ "$i" -lt "$limit" ] && kill -0 "$pid" 2>/dev/null; do
      sleep 1
      i=$((i + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      : >"$tmp/timeout"
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      ! kill -0 "$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
    fi
  ) >/dev/null 2>&1 &
  wait "$pid" 2>/dev/null || rc=$?
  if [ -e "$tmp/timeout" ]; then
    rm -rf "$tmp"
    return 2
  fi
  p="$(sed -n 's/^__MACLIFT_PATH__=//p' "$tmp/out" 2>/dev/null | tail -n 1)"
  rm -rf "$tmp"
  [ "$rc" = 0 ] && [ -n "$p" ] || return 1
  printf '%s\n' "$p"
}

# The PATH a new terminal gets: override, else ask a login shell, else this
# process's PATH. Returns 2 (printing nothing) when the login shell timed out.
# Asking runs the user's interactive startup files (~/.zprofile, ~/.zshrc),
# which may write their own caches; doctor itself writes nothing.
_doctor_path() {
  local sh p rc=0
  if [ -n "${MACLIFT_DOCTOR_PATH:-}" ]; then
    printf '%s\n' "$MACLIFT_DOCTOR_PATH"
    return 0
  fi
  sh="$(_doctor_login_shell)"
  if [ -n "$sh" ] && [ -x "$sh" ]; then
    p="$(_doctor_login_path "$sh")" || rc=$?
    [ "$rc" != 2 ] || return 2
    if [ "$rc" = 0 ]; then
      printf '%s\n' "$p"
      return 0
    fi
  fi
  printf '%s\n' "$PATH"
}

# Position (1-based) of a directory in a colon list; empty when absent. Plain
# shell: awk -v would turn backslashes in the paths into escapes.
_doctor_path_index() {
  local dir="$1" rest="$2:" entry i=1
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"
    rest="${rest#*:}"
    if [ "$entry" = "$dir" ]; then
      printf '%s\n' "$i"
      return 0
    fi
    i=$((i + 1))
  done
}

doctor_check_brew() {
  if _bs_brew_path >/dev/null 2>&1; then
    _doctor_ok "Homebrew found"
  else
    _doctor_fail "Homebrew not found" "run ./maclift to install Homebrew"
  fi
}

doctor_check_path() {
  local brew bin path bi si
  local fix="restart your terminal; if it persists, check ~/.zprofile and ~/.zshrc"
  brew="$(_bs_brew_path 2>/dev/null)" || brew=""
  if [ -z "$brew" ]; then
    _doctor_fail "PATH: Homebrew not found, cannot check" "$fix"
    return
  fi
  bin="$(dirname "$brew")"
  path="$(_doctor_path)" || {
    _doctor_fail "could not read your login PATH (your login shell took over $(_doctor_shell_timeout)s)" "check ~/.zprofile and ~/.zshrc (they must finish without waiting for input)"
    return
  }
  bi="$(_doctor_path_index "$bin" "$path")"
  if [ -z "$bi" ]; then
    _doctor_fail "PATH: $bin is missing" "$fix"
    return
  fi
  if [ -f "$(_pins_file)" ]; then
    si="$(_doctor_path_index "$MACLIFT_HOME/.asdf/shims" "$path")"
    if [ -z "$si" ] || [ "$si" -gt "$bi" ]; then
      _doctor_fail "PATH: asdf shims must come before $bin" "$fix"
      return
    fi
  fi
  _doctor_ok "PATH has Homebrew${si:+ after the asdf shims}"
}

doctor_check_shell() {
  local sh
  sh="$(_doctor_login_shell)"
  if [ "$(basename "${sh:-none}")" = zsh ]; then
    _doctor_ok "Login shell is zsh"
  else
    _doctor_fail "Login shell is ${sh:-unknown}, not zsh" "chsh -s /bin/zsh"
  fi
}

doctor_check_repo_link() {
  local link="$MACLIFT_HOME/.maclift"
  if [ -e "$link" ] && [ "$(maclift_real_path "$link")" = "$(maclift_real_path "$MACLIFT_DIR")" ]; then
    _doctor_ok "The .maclift link points at this clone"
  else
    _doctor_fail "The .maclift link does not point at $MACLIFT_DIR" "maclift -y"
  fi
}

# Dangling symlinks at depth 1 of the home folder and ~/.config whose target
# mentions .maclift or the clone: prints their paths.
_doctor_dangling() {
  local d l t
  for d in "$MACLIFT_HOME" "$MACLIFT_HOME/.config"; do
    [ -d "$d" ] || continue
    for l in "$d"/.[!.]* "$d"/*; do
      [ -L "$l" ] || continue
      [ ! -e "$l" ] || continue
      t="$(readlink "$l")"
      case "$t" in *.maclift* | *"$MACLIFT_DIR"*) printf '%s\n' "$l" ;; esac
    done
  done
}

doctor_check_links() {
  local id bad="" l
  for id in $(selection_load); do
    case "$id" in dotfiles:*) ;; *) continue ;; esac
    dotfiles_item_linked "$id" || bad="${bad:+$bad, }$id not linked"
  done
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    bad="${bad:+$bad, }broken link $l"
  done <<EOT
$(_doctor_dangling)
EOT
  if [ -z "$bad" ]; then
    _doctor_ok "Dotfiles linked, no broken links"
  else
    _doctor_fail "Links: $bad" "maclift -y (files in the way are backed up)"
  fi
}

doctor_check_asdf() {
  local pins line name ver bad="" _noglob
  pins="$(_pins_file)"
  if [ ! -f "$pins" ]; then
    _doctor_ok "No language versions pinned"
    return 0
  fi
  if ! command -v "${MACLIFT_ASDF:-asdf}" >/dev/null 2>&1; then
    _doctor_fail "asdf not found" "maclift -y"
    return
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '#'* | '') continue ;; esac
    # Split on whitespace (tabs too) without glob expansion.
    case "$-" in *f*) _noglob=1 ;; *) _noglob=0; set -f ;; esac
    # shellcheck disable=SC2086
    set -- $line
    [ "$_noglob" = 1 ] || set +f
    name="${1:-}"
    ver="${2:-}"
    [ -n "$name" ] || continue
    if [ -z "$ver" ]; then
      bad="${bad:+$bad, }broken pin line '$name' (no version)"
      continue
    fi
    _pins_asdf where "$name" "$ver" >/dev/null 2>&1 || bad="${bad:+$bad, }$name $ver not installed"
  done <"$pins"
  if [ -z "$bad" ] && [ -n "$(pins_apply 1 2>/dev/null)" ]; then
    bad="pins differ from ~/.tool-versions"
  fi
  if [ -z "$bad" ]; then
    _doctor_ok "Language versions installed and applied"
  else
    _doctor_fail "asdf: $bad" "maclift -y"
  fi
}

# _doctor_resolve <file>: the file's real path, following symlinks.
_doctor_resolve() {
  local f="$1" t i=0
  while [ -L "$f" ] && [ "$i" -lt 20 ]; do
    t="$(readlink "$f")"
    case "$t" in /*) f="$t" ;; *) f="$(dirname "$f")/$t" ;; esac
    i=$((i + 1))
  done
  printf '%s/%s\n' "$(maclift_real_path "$(dirname "$f")")" "$(basename "$f")"
}

# _doctor_selected <id>: true when the saved selection includes the item.
_doctor_selected() {
  case "$NL_DOCTOR$(selection_load)$NL_DOCTOR" in
    *"$NL_DOCTOR$1$NL_DOCTOR"*) return 0 ;;
  esac
  return 1
}

# Language tools the selection asks for must actually run, the way a new
# terminal would run them (asdf shims and ~/.local/bin first, from the home
# folder). Runs in a subshell so doctor's own PATH and cwd stay untouched.
# Also notes (without failing) which python answers and a second uv.
doctor_check_toolchains() {
  local bad=0 any=0 what="" arch="" path dir py="" seen="" real n=0 first="" second=""
  path="$(_doctor_path 2>/dev/null)" || path="$PATH"

  if _doctor_selected script:hex || _doctor_selected script:phx_new; then
    any=1
    if _doctor_selected script:hex; then
      # Capture first: grep -q closing the pipe early fails under pipefail.
      arch="$(toolchain_path_setup && toolchain_archives 2>/dev/null)" || arch=""
      case "$arch" in *"hex-"*) ;; *) what="hex" ;; esac
    fi
    if _doctor_selected script:phx_new; then
      (toolchain_path_setup && toolchain_mix phx.new --version) >/dev/null 2>&1 || what="${what:+$what, }phx_new"
    fi
    if [ -n "$what" ]; then
      _doctor_fail "Elixir tools: $what missing" "maclift -y" || true
      bad=1
    fi
  fi

  if _doctor_selected brew:pnpm; then
    any=1
    if ! (toolchain_path_setup && toolchain_pnpm --version && toolchain_node --version) >/dev/null 2>&1; then
      _doctor_fail "JavaScript tools: pnpm or node does not run" "maclift -y" || true
      bad=1
    fi
  fi

  if _doctor_selected script:python; then
    any=1
    py="$(PATH="$path" command -v python 2>/dev/null)" || py=""
    if [ -z "$py" ] || ! (toolchain_path_setup && "$py" --version) >/dev/null 2>&1; then
      _doctor_fail "Python: python --version fails" "maclift -y" || true
      bad=1
    else
      case "$py" in
        "$MACLIFT_HOME/.asdf/shims/"*) _doctor_note "python is $py (asdf)" ;;
        *) _doctor_note "python is $py (uv)" ;;
      esac
    fi
  fi

  # Two uv binaries: walk the PATH, keep distinct real paths.
  dir="$path:"
  while [ -n "$dir" ]; do
    real="${dir%%:*}"
    dir="${dir#*:}"
    [ -n "$real" ] && [ -x "$real/uv" ] && [ ! -d "$real/uv" ] || continue
    real="$(_doctor_resolve "$real/uv")"
    case "$seen" in *"|$real|"*) continue ;; esac
    seen="$seen|$real|"
    n=$((n + 1))
    if [ "$n" = 1 ]; then first="$real"; elif [ "$n" = 2 ]; then second="$real"; fi
  done
  if [ "$n" -gt 1 ]; then
    _doctor_note "two uv binaries on PATH: $first, $second" "rm ~/.local/bin/uv ~/.local/bin/uvx, or brew uninstall uv — keep one"
  fi

  [ "$bad" = 0 ] || return 1
  if [ "$any" = 1 ]; then
    _doctor_ok "Language tools ready"
  else
    _doctor_ok "No language tools selected"
  fi
}

doctor_check_git() {
  local want have key alt_want alt_have
  want="$(conf_get "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL 2>/dev/null)" || want=""
  key="$(conf_get "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_SIGNING_KEY 2>/dev/null)" || key=""
  have="$(git config -f "$MACLIFT_HOME/.gitconfig.local" user.email 2>/dev/null)" || have=""
  if [ -z "$want" ] || [ "$want" != "$have" ]; then
    _doctor_fail "Git identity: ~/.gitconfig.local has '${have:-nothing}', expected '${want:-your saved email}'" "maclift -y"
    return 1
  fi
  if identity_alt_active; then
    alt_want="$(conf_get "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_ALT_EMAIL 2>/dev/null)" || alt_want=""
    alt_have="$(git config -f "$MACLIFT_HOME/.gitconfig.alt" user.email 2>/dev/null)" || alt_have=""
    if [ -z "$alt_want" ] || [ "$alt_want" != "$alt_have" ]; then
      _doctor_fail "Second git identity: ~/.gitconfig.alt has '${alt_have:-nothing}', expected '${alt_want:-your saved email}'" "maclift -y"
      return 1
    fi
    if ! identity_alt_current; then
      _doctor_fail "Second git identity: ~/.gitconfig.alt is out of date with user.conf" "maclift -y"
      return 1
    fi
  fi
  if [ -n "$key" ] && ! command -v "${MACLIFT_GPG:-gpg}" >/dev/null 2>&1; then
    _doctor_fail "gpg not found, so the signing key $key cannot be checked" "brew install gnupg"
    return 1
  fi
  if [ -n "$key" ] && ! GNUPGHOME="$(maclift_gnupghome)" "${MACLIFT_GPG:-gpg}" --list-secret-keys -- "$key" >/dev/null 2>&1; then
    _doctor_fail "Signing key $key is not in your GPG keyring" "gpg --import your key, or remove MACLIFT_SIGNING_KEY from user.conf"
    return 1
  fi
  _doctor_ok "Git identity matches your saved answers"
}

# With script:ssh-key selected, a private key needs its .pub next to it
# (ssh-key.sh and gh upload read it). Read-only: never writes the .pub.
doctor_check_ssh() {
  local key="$MACLIFT_HOME/.ssh/id_ed25519"
  case "$NL_DOCTOR$(selection_load)$NL_DOCTOR" in
    *"${NL_DOCTOR}script:ssh-key${NL_DOCTOR}"*) ;;
    *)
      _doctor_ok "SSH key not managed by maclift"
      return 0
      ;;
  esac
  if [ ! -e "$key" ] && [ -e "$key.pub" ]; then
    # shellcheck disable=SC2088 # literal ~ in the message
    _doctor_fail "~/.ssh/id_ed25519.pub exists without its private key" "move ~/.ssh/id_ed25519.pub aside"
  elif [ ! -e "$key" ]; then
    _doctor_ok "No SSH key yet (maclift makes one on the next run)"
  elif [ -e "$key.pub" ]; then
    _doctor_ok "SSH key and its .pub are in place"
  else
    # shellcheck disable=SC2088 # literal ~ in the message
    _doctor_fail "~/.ssh/id_ed25519.pub is missing" "ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub"
  fi
}

# cmd_doctor <dry_run>: runs every check; 0 when all pass, else 1.
cmd_doctor() {
  local c n=0
  DOCTOR_FAILS=0
  for c in $DOCTOR_CHECKS; do
    n=$((n + 1))
    "doctor_check_$c" || true
  done
  echo
  if [ "$DOCTOR_FAILS" = 0 ]; then
    echo "All $n checks passed"
    return 0
  fi
  echo "$DOCTOR_FAILS problem(s) found"
  return 1
}
