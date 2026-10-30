#!/usr/bin/env bash
#
# Unit tests for lib/ui.sh and lib/banner.sh (plain mode)
#

set -eo pipefail

# Make the suite independent of the environment (GitHub Actions sets CI=true,
# which forces plain mode); the CI test below sets CI explicitly.
unset CI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=lib/ui.sh
source "$PROJECT_ROOT/lib/ui.sh"
# shellcheck source=lib/banner.sh
source "$PROJECT_ROOT/lib/banner.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
MACLIFT_HOME="$(mktemp -d)"
export MACLIFT_HOME
maclift_init_paths
export MACLIFT_PLAIN=1
fake_sw_vers() { echo "27.0"; }
export MACLIFT_SW_VERS=fake_sw_vers

test_mode() {
  test_suite "ui_mode"
  assert_equals "plain" "$(ui_mode)" "MACLIFT_PLAIN=1 gives plain"
  assert_equals "plain" "$(MACLIFT_PLAIN='' NO_COLOR=1 ui_mode)" "NO_COLOR gives plain"
}

test_input() {
  test_suite "ui_input"
  assert_equals "Ada" "$(printf '\n' | ui_input "Name" "Ada" 2>/dev/null)" "empty line returns default"
  assert_equals "Bob" "$(printf 'Bob\n' | ui_input "Name" "Ada" 2>/dev/null)" "typed value wins"
}

test_choose() {
  test_suite "ui_choose_*"
  assert_equals "a" "$(printf '2\n\n' | ui_choose_many h "a,b" a b c 2>/dev/null)" "toggle b off leaves a"
  assert_equals "a
b" "$(printf '\n' | ui_choose_many h "a,b" a b c 2>/dev/null)" "empty accepts preselection"
  assert_equals "c" "$(printf '3\n' | ui_choose_one h a b c 2>/dev/null)" "choose_one by number"
  assert_command_succeeds "printf 'y\n' | ui_confirm 'Go?' n 2>/dev/null" "confirm y"
  assert_command_fails "printf '\n' | ui_confirm 'Go?' n 2>/dev/null" "confirm default n"
  assert_command_succeeds "printf '\n' | ui_confirm 'Go?' y 2>/dev/null" "confirm default y"
}

test_display() {
  test_suite "ui display"
  assert_equals "[█████░░░░░] 5/10 · Installing bat" "$(ui_progress 5 10 bat)" "progress bar"
  local s
  s="$(ui_status ok bat 3)"
  assert_contains "$s" "✓" "status ok has check"
  assert_contains "$s" "bat" "status ok has label"
  assert_contains "$(ui_status fail bat)" "✗" "status fail"
  assert_contains "$(ui_status skip bat)" "already installed" "status skip"
  assert_contains "$(ui_status need script:hex elixir)" "skipped script:hex (needs elixir)" "status need"
  assert_contains "$(ui_box hello)" "== hello ==" "plain box"
}

test_banner() {
  test_suite "banner"
  assert_equals "0" "$(NO_COLOR=1 banner_show | grep -c $'\e' || true)" "no escapes with NO_COLOR"
  assert_equals "1" "$(COLUMNS=60 banner_show | wc -l | tr -d ' ')" "narrow gives one line"
  assert_contains "$(COLUMNS=60 banner_show)" "liftoff for your new Mac" "narrow tagline"
  local wide
  wide="$(MACLIFT_ASSUME_TTY=1 COLORTERM=truecolor COLUMNS=100 banner_show)"
  assert_contains "$wide" "m a c l i f t" "wide has wordmark"
  assert_contains "$wide" "macOS 27.0" "wide has macOS version"
  assert_command_succeeds "banner_launch" "launch is a no-op in plain mode"
}

test_no_tty_no_escapes() {
  test_suite "no escape codes when output is not a terminal"
  local out term esc
  esc=$'\e'
  for term in dumb xterm-256color; do
    out="$(unset MACLIFT_ASSUME_TTY NO_COLOR; _UI_TTY=0 TERM=$term COLORTERM=truecolor COLUMNS=100 banner_show; _UI_TTY=0 TERM=$term COLORTERM=truecolor ui_status ok bat 1; _UI_TTY=0 TERM=$term COLORTERM=truecolor ui_status fail bat; _UI_TTY=0 TERM=$term COLORTERM=truecolor ui_status skip bat)"
    case "$out" in *"$esc"*) assert_equals "no ESC" "ESC found" "TERM=$term piped output";; *) assert_equals "ok" "ok" "TERM=$term piped output has no ESC";; esac
    assert_contains "$out" "liftoff for your new Mac" "TERM=$term falls back to the one-line banner"
  done
  out="$(unset NO_COLOR; _UI_TTY=0 TERM=xterm-256color COLORTERM='' ui_status ok bat)"
  case "$out" in *"$esc"*) assert_equals "no ESC" "ESC found" "256-colour piped output";; *) assert_equals "ok" "ok" "256-colour piped output has no ESC";; esac
  assert_contains "$(MACLIFT_ASSUME_TTY=1 COLORTERM=truecolor ui_status ok bat)" "38;2;166;227;161" "colours still used on a terminal"
}

test_gum_reachable() {
  test_suite "gum mode reachable"
  local d out
  d="$(mktemp -d)"
  cat >"$d/gum" <<'STUB'
#!/usr/bin/env bash
echo "gum-called $1"
STUB
  chmod +x "$d/gum"
  assert_equals "gum" "$(MACLIFT_PLAIN='' MACLIFT_ASSUME_TTY=1 MACLIFT_GUM="$d/gum" ui_mode)" "gum mode with assumed TTY"
  assert_equals "gum-called input" "$(MACLIFT_PLAIN='' MACLIFT_ASSUME_TTY=1 MACLIFT_GUM="$d/gum" ui_input Name Ada)" "ui_input routes to gum stub"
  assert_equals "plain" "$(MACLIFT_PLAIN='' MACLIFT_GUM="$d/gum" ui_mode)" "plain without TTY"
  assert_equals "plain" "$(MACLIFT_PLAIN='' MACLIFT_ASSUME_TTY=1 CI=1 MACLIFT_GUM="$d/gum" ui_mode)" "CI forces plain"

  # banner_launch: caller traps survive, normal run restores the screen
  out="$(
    export MACLIFT_PLAIN='' MACLIFT_ASSUME_TTY=1 MACLIFT_GUM="$d/gum"
    sleep() { :; }
    trap 'echo CALLER_INT' INT
    banner_launch
    trap -p INT
  )"
  assert_contains "$out" "CALLER_INT" "caller INT trap preserved"
  assert_contains "$out" "Your Mac is ready" "launch completes"
  assert_contains "$out" "$(printf '\033\[?1049l')" "alternate screen left"

  # interrupt mid-animation: screen restored, stops with 130, no completion message
  out="$(
    export MACLIFT_PLAIN='' MACLIFT_ASSUME_TTY=1 MACLIFT_GUM="$d/gum"
    sleep() { sh -c 'kill -INT $PPID'; }
    banner_launch
    echo "status=$?"
  )"
  assert_contains "$out" "status=130" "interrupt returns 130"
  assert_contains "$out" "$(printf '\033\[?25h')" "cursor restored on interrupt"
  assert_equals "0" "$(printf '%s' "$out" | grep -c 'Your Mac is ready' || true)" "no completion message after interrupt"
}

test_mode
test_gum_reachable
test_input
test_choose
test_display
test_banner
test_no_tty_no_escapes
test_summary
