#!/usr/bin/env bash
#
# maclift preflight: machine checks before anything is installed.
# bash 3.2 compatible. Meant to be sourced.
#
# Test overrides: MACLIFT_UNAME, MACLIFT_SW_VERS, MACLIFT_DF.

MACLIFT_MIN_MACOS=14
MACLIFT_MIN_FREE_GB=20

# Prints the chip type; returns 1 with a how-to-fix message on failure.
preflight_check() {
  local arch ver major free

  arch="$("${MACLIFT_UNAME:-uname}" -m 2>/dev/null)"
  case "$arch" in
    arm64) echo "Apple silicon" ;;
    x86_64) echo "Intel" ;;
    *) echo "✗ Unrecognized processor '$arch'. maclift supports Apple silicon and Intel Macs." >&2; return 1 ;;
  esac

  ver="$("${MACLIFT_SW_VERS:-sw_vers}" -productVersion 2>/dev/null)"
  major="${ver%%.*}"
  case "$major" in
    '' | *[!0-9]*)
      echo "✗ Could not read your macOS version. Make sure you are running this on a Mac." >&2
      return 1
      ;;
  esac
  if [ "$major" -lt "$MACLIFT_MIN_MACOS" ]; then
    echo "✗ maclift needs macOS $MACLIFT_MIN_MACOS or newer (you have $ver). Update in System Settings > General > Software Update, then run maclift again." >&2
    return 1
  fi

  # df -g /: available GB is column 4 of line 2.
  free="$("${MACLIFT_DF:-df}" -g / 2>/dev/null | awk 'NR==2 {print $4}')"
  case "$free" in
    '' | *[!0-9]*)
      echo "✗ Could not read free disk space. Check that you have at least $MACLIFT_MIN_FREE_GB GB free." >&2
      return 1
      ;;
  esac
  if [ "$free" -lt "$MACLIFT_MIN_FREE_GB" ]; then
    echo "✗ Only $free GB free; maclift needs at least $MACLIFT_MIN_FREE_GB GB. Free up space (empty the Trash, remove large files), then run maclift again." >&2
    return 1
  fi
  return 0
}
