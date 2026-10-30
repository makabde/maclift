#!/usr/bin/env bash
#
# Renumber sessions that have number names to 1, 2, 3... in the order they
# were created. Sessions with real names (like "work") are never touched.
# Run by the session-created and session-closed hooks in options.conf.

# Numbered sessions, oldest first.
numbered="$(tmux list-sessions -F '#{session_created} #{session_name}' 2>/dev/null |
    sort -n | awk '$2 ~ /^[0-9]+$/ { print $2 }')"

[ -n "$numbered" ] || exit 0

# Two passes, so renaming 2 -> 1 can't collide with a session already called 1.
n=1
for name in $numbered; do
    [ "$name" = "$n" ] || tmux rename-session -t "=$name" "renumber-$n"
    n=$((n + 1))
done

n=1
for name in $numbered; do
    [ "$name" = "$n" ] || tmux rename-session -t "=renumber-$n" "$n"
    n=$((n + 1))
done
