# Modern CLI Tools Configuration and Aliases

# ============================================================================
# BAT (better cat)
# ============================================================================
if command -v bat &>/dev/null; then
    export BAT_THEME="Nord"
    alias cat="bat --paging=never"
    alias catp="bat"  # with paging
fi

# ============================================================================
# EZA (better ls)
# ============================================================================
if command -v eza &>/dev/null; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza --icons --long --group-directories-first --git"
    alias la="eza --icons --long --all --group-directories-first --git"
    alias lt="eza --icons --tree --level=2 --group-directories-first"
    alias lta="eza --icons --tree --level=2 --all --group-directories-first"
fi

# ============================================================================
# ZOXIDE (smarter cd)
# ============================================================================
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
    # Use 'z' for zoxide and keep 'cd' as traditional
    alias zi="zoxide query -i"  # interactive selection
fi

# ============================================================================
# FZF (fuzzy finder)
# ============================================================================
if command -v fzf &>/dev/null; then
    # Load FZF keybindings and completions
    if [ -f ~/.fzf.zsh ]; then
        source ~/.fzf.zsh
    elif [ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ]; then
        source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
        source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
    fi

    # FZF Nord theme configuration
    export FZF_DEFAULT_OPTS="
        --height 40%
        --layout=reverse
        --border
        --color=bg+:#3B4252,bg:#2E3440,spinner:#81A1C1,hl:#616E88
        --color=fg:#D8DEE9,header:#616E88,info:#81A1C1,pointer:#81A1C1
        --color=marker:#81A1C1,fg+:#D8DEE9,prompt:#81A1C1,hl+:#81A1C1
        --preview-window=:hidden
        --preview '([[ -f {} ]] && (bat --style=numbers --color=always {} || cat {})) || ([[ -d {} ]] && (eza --tree --level=1 --icons {} || ls -l {})) 2> /dev/null | head -200'
        --bind '?:toggle-preview'
        --bind 'ctrl-a:select-all'
        --bind 'ctrl-y:execute-silent(echo {+} | pbcopy)'
        --bind 'ctrl-e:execute(echo {+} | xargs -o vim)'
    "

    # Use fd instead of find for FZF
    if command -v fd &>/dev/null; then
        export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
    fi
fi

# ============================================================================
# RIPGREP
# ============================================================================
if command -v rg &>/dev/null; then
    export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
fi

# ============================================================================
# DELTA (git diff)
# ============================================================================
if command -v delta &>/dev/null; then
    # Delta is configured in gitconfig
    alias gdiff="git diff | delta"
fi

# ============================================================================
# Additional helpful aliases
# ============================================================================
alias help="tldr"           # Use tldr instead of man for quick help
alias lg="lazygit"          # Launch lazygit
alias top="btop 2>/dev/null || htop 2>/dev/null || top"  # Better top
