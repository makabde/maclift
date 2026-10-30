command -v elixir >/dev/null 2>&1 || return 0

export ERL_AFLAGS="-kernel shell_history enabled"
