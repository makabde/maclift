#!/usr/bin/env bash
#
# maclift bootstrap: Xcode command-line tools, Homebrew, gum.
# bash 3.2 compatible. Meant to be sourced. Uses a plain spinner because gum
# may not exist yet.
#
# Test overrides: MACLIFT_XCODE_SELECT, MACLIFT_BREW, MACLIFT_CURL, MACLIFT_GIT,
# MACLIFT_BOOTSTRAP_POLL (seconds between checks, default 5),
# MACLIFT_BOOTSTRAP_TIMEOUT (seconds to wait for the tools, default 1800).

_bs_xcode() { "${MACLIFT_XCODE_SELECT:-xcode-select}" "$@"; }

# Resolves the brew binary: override (only if executable), PATH, then the
# standard locations.
_bs_brew_path() {
  if [ -n "${MACLIFT_BREW:-}" ]; then
    [ -x "$MACLIFT_BREW" ] || return 1
    echo "$MACLIFT_BREW"
  elif command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [ -x /opt/homebrew/bin/brew ]; then
    echo /opt/homebrew/bin/brew
  elif [ -x /usr/local/bin/brew ]; then
    echo /usr/local/bin/brew
  else
    return 1
  fi
}

# Runs a command with a plain spinner labelled "Getting ready…". Runs in a
# subshell with its own traps, so the caller's traps are untouched. INT/TERM
# kill the child, restore the cursor and stop with status 130.
_bs_spin() {
  (
    pid=""
    # shellcheck disable=SC2329
    cleanup() {
      [ -z "$pid" ] || kill "$pid" 2>/dev/null
      [ -z "$pid" ] || wait "$pid" 2>/dev/null
      [ -t 2 ] && printf '\r\033[K\033[?25h' >&2
    }
    trap 'cleanup; exit 130' INT TERM
    "$@" &
    pid=$!
    if [ -t 2 ]; then
      i=0
      # shellcheck disable=SC1003
      frames='|/-\'
      printf '\033[?25l' >&2
      while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s Getting ready…' "$(printf '%s' "$frames" | cut -c$((i % 4 + 1)))" >&2
        i=$((i + 1))
        sleep 0.2
      done
      printf '\r\033[K\033[?25h' >&2
    else
      echo "Getting ready…" >&2
    fi
    wait "$pid"
  )
}

# Waits until the command-line tools exist, up to MACLIFT_BOOTSTRAP_TIMEOUT seconds.
_bs_wait_for_clt() {
  local deadline=$((SECONDS + ${MACLIFT_BOOTSTRAP_TIMEOUT:-1800}))
  until _bs_xcode -p >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "✗ Command-line tools were not installed. Run xcode-select --install, accept the dialog, then run maclift again." >&2
      return 1
    fi
    sleep "${MACLIFT_BOOTSTRAP_POLL:-5}"
  done
}

_bs_install_brew() {
  local script rc=0
  script="$(mktemp)" || return 1
  if ! "${MACLIFT_CURL:-curl}" -fsSL -o "$script" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh; then
    rm -f "$script"
    echo "✗ Could not download the Homebrew installer (check your internet connection)." >&2
    return 1
  fi
  if [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; then
    NONINTERACTIVE=1 /bin/bash "$script" || rc=$?
  else
    /bin/bash "$script" || rc=$?
  fi
  rm -f "$script"
  return "$rc"
}

# Puts brew on PATH for this process.
_bs_brew_env() {
  local brew
  brew="$(_bs_brew_path)" || return 1
  # The one allowed eval: Homebrew's own shellenv output, never user or config content.
  eval "$("$brew" shellenv)"
}

# Usage: bootstrap_git_clone <dry_run:0|1>
# A folder unpacked by the one-line installer has a .maclift-release marker
# and no .git. Once git exists (after the command-line tools), turn it into a
# clone of the release tag tracking origin/main, so maclift update can pull.
# Never fails the run: on failure the marker stays for the next run.
bootstrap_git_clone() {
  local dry_run="${1:-0}" dir="${MACLIFT_DIR:-}" marker repo tag
  [ -n "$dir" ] || return 0
  marker="$dir/.maclift-release"
  [ -f "$marker" ] || return 0
  [ -e "$dir/.git" ] && return 0
  repo="$(conf_get "$marker" MACLIFT_RELEASE_REPO 2>/dev/null || true)"
  tag="$(conf_get "$marker" MACLIFT_RELEASE_TAG 2>/dev/null || true)"
  if [ -z "$repo" ] || [ -z "$tag" ]; then
    echo "✗ could not make $dir a git clone; maclift update will skip pulling" >&2
    return 0
  fi
  if [ "$dry_run" = "1" ]; then
    echo "would turn $dir into a git clone of $repo"
    return 0
  fi
  local git="${MACLIFT_GIT:-git}"
  # GIT_TERMINAL_PROMPT=0: a 401 fails instead of waiting on a password prompt.
  # checkout -f overwrites edits made in the unpacked folder before this first
  # clone; fine, as that folder is a pristine release.
  if GIT_TERMINAL_PROMPT=0 "$git" -C "$dir" init -q &&
    GIT_TERMINAL_PROMPT=0 "$git" -C "$dir" remote add origin "https://github.com/$repo.git" &&
    GIT_TERMINAL_PROMPT=0 "$git" -C "$dir" fetch -q origin main --tags &&
    GIT_TERMINAL_PROMPT=0 "$git" -C "$dir" checkout -q -f -B main "$tag" &&
    GIT_TERMINAL_PROMPT=0 "$git" -C "$dir" branch -q -u origin/main main; then
    rm -f "$marker"
    echo "✓ $dir is now a git clone (maclift update keeps it current)"
  else
    # This .git is ours (there was none above): drop it so the next run retries.
    rm -rf "$dir/.git"
    echo "✗ could not make $dir a git clone; run maclift again to retry (until then maclift update skips pulling)" >&2
  fi
  return 0
}

# Usage: bootstrap_run <dry_run:0|1>. Each step runs only if missing.
bootstrap_run() {
  local dry_run="${1:-0}" brew out

  if _bs_xcode -p >/dev/null 2>&1; then
    log_line "bootstrap: command-line tools present"
  elif [ "$dry_run" = "1" ]; then
    echo "would install: Xcode command-line tools"
  else
    echo "Installing Xcode command-line tools: accept the pop-up window." >&2
    # "already requested" is not fatal: keep waiting. Any other failure is shown.
    if ! out="$(_bs_xcode --install 2>&1)"; then
      case "$out" in
        *already*) ;;
        *) echo "✗ xcode-select --install failed: $out" >&2; return 1 ;;
      esac
    fi
    _bs_spin _bs_wait_for_clt || return $?
  fi

  bootstrap_git_clone "$dry_run"

  if brew="$(_bs_brew_path)"; then
    _bs_brew_env || true
  elif [ "$dry_run" = "1" ]; then
    echo "would install: Homebrew"
    brew=""
  else
    echo "Installing Homebrew…" >&2
    _bs_install_brew || { echo "✗ Homebrew install failed. Fix the error above and run maclift again." >&2; return 1; }
    _bs_brew_env || { echo "✗ Homebrew installed but brew was not found in /opt/homebrew or /usr/local." >&2; return 1; }
    brew="$(_bs_brew_path)"
  fi

  if [ -n "$brew" ] && command -v gum >/dev/null 2>&1; then
    log_line "bootstrap: gum present"
  elif [ "$dry_run" = "1" ]; then
    echo "would install: gum"
  else
    _bs_spin "$brew" install gum || { echo "✗ Could not install gum with Homebrew." >&2; return 1; }
  fi
  return 0
}
