#!/usr/bin/env bash
#
# Match the catppuccin flavor to the macOS appearance: latte in Light mode,
# mocha in Dark mode. Then colour the parts catppuccin doesn't (pane
# borders, copy-mode selection, bell, pane numbers) from the same flavor.
#
# Usage: theme.sh [light|dark]
#   No argument reads the macOS setting (tmux start, see tmux.conf).
#   light/dark come from the client-light-theme and client-dark-theme
#   hooks (plugins.conf), which fire when iTerm2 reports an appearance change.

set -u

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$HOME/.tmux/plugins/tmux/catppuccin.tmux"
[ -f "$plugin" ] || exit 0

case "${1:-}" in
    light) flavor=latte ;;
    dark) flavor=mocha ;;
    *)
        if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
            flavor=mocha
        else
            flavor=latte
        fi
        ;;
esac

if [ "$(tmux show -gqv @catppuccin_flavor)" != "$flavor" ]; then
    # catppuccin sets its colours only when they're unset, so clear the
    # previous flavor's, put our catppuccin options back, then reload it.
    tmux show -g | awk '$1 ~ /^@(thm_|_ctp_|catppuccin_)/ { print $1 }' |
        while read -r option; do tmux set -gu "$option"; done
    tmux source-file "$dir/plugins.conf"
    tmux set -g @catppuccin_flavor "$flavor"
    bash "$plugin"
fi

tmux set -gF pane-border-style 'fg=#{@thm_overlay_0}' \; \
    set -gF pane-active-border-style 'fg=#{@thm_mauve}' \; \
    set -gF display-panes-colour '#{@thm_overlay_0}' \; \
    set -gF display-panes-active-colour '#{@thm_mauve}' \; \
    set -gF mode-style 'fg=#{@thm_fg},bg=#{@thm_surface_1}' \; \
    setw -gF window-status-bell-style 'fg=#{@thm_bg},bg=#{@thm_yellow},bold'
