# maclift demo: records docs/demo.gif.  Run from a copy of the repo at a
# neutral path, e.g.  cd /tmp/maclift && vhs docs/demo.tape
# The recording changes nothing on the Mac and does not depend on it:
#   - MACLIFT_HOME is a throwaway folder, and --dry-run only prints what
#     would happen;
#   - brew and asdf are stubbed out (MACLIFT_BREW, MACLIFT_ASDF), so no
#     package manager is queried;
#   - MACLIFT_APP_ROOT is an empty folder, so /Applications is not consulted.
# The group step assumes 8 optional groups (one Enter each in the fine-tune
# loop below); change the loop if the catalog gains or loses groups.

Output docs/demo.gif

Set Shell bash
Set Theme "Catppuccin Mocha"
Set Width 1000
Set Height 600
Set FontSize 16
Set Padding 16
Set TypingSpeed 60ms
Set Framerate 15

# Hidden setup: a plain prompt and a fresh sandbox home (no real names or paths).
Hide
Type "PS1='$ '" Enter
Type "rm -rf /tmp/ada-home && mkdir -p /tmp/ada-home/root" Enter
Type "export MACLIFT_HOME=/tmp/ada-home MACLIFT_SKIP_BOOTSTRAP=1 MACLIFT_BREW=false MACLIFT_ASDF=false MACLIFT_APP_ROOT=/tmp/ada-home/root" Enter
Type "clear" Enter
Show

Type "./maclift --dry-run"
Sleep 600ms
Enter
Sleep 3s

# Who you are
Type "Ada Lovelace"
Sleep 400ms
Enter
Sleep 800ms
Type "ada@example.com"
Sleep 400ms
Enter
Sleep 800ms
# GitHub username is optional: skip it.
Enter
Sleep 1500ms

# Pick groups: accept the defaults.
Sleep 2s
Enter
Sleep 1s

# Fine-tune each group: accept the defaults (8 groups).
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 1s

# Review box, then "Ready?" with Install preselected.
Sleep 3s
Enter

# Dry-run install view: nothing is installed.
Sleep 8s

# Hold on the summary.
Sleep 3s
