# Completion System Initialization
# This runs in the 'post' stage after all configs are loaded
# fpath should already be configured by pre/completions.zsh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Initialize completion system with caching
# https://blog.callstack.io/supercharge-your-terminal-with-zsh-8b369d689770
autoload -Uz compinit

# Rebuild completion cache once per day
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit -i
else
  compinit -C -i
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Completion UI Configuration

# Menu-like autocompletion selection
zmodload -i zsh/complist

# Automatically list choices on ambiguous completion
setopt auto_list
# Automatically use menu completion
setopt auto_menu
# Move cursor to end if word had one match
setopt always_to_end

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Completion Behavior Styles

# Select completions with arrow keys
zstyle ':completion:*' menu select

# Group results by category
zstyle ':completion:*' group-name ''

# Enable approximate matches for completion
zstyle ':completion:::::' completer _expand _complete _ignored _approximate

# Case and hyphen insensitive matching
zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|=*' 'l:|=* r:|=*'

# Use caching for slow commands (apt, dpkg, etc)
zstyle ':completion::complete:*' use-cache 1
# Keep the cache outside the repo (it lists installed packages)
_zsh_cache_dir="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}"
[[ -d $_zsh_cache_dir ]] || mkdir -p "$_zsh_cache_dir"
zstyle ':completion::complete:*' cache-path "$_zsh_cache_dir"
unset _zsh_cache_dir

# Colorize completions using default `ls` colors
zstyle ':completion:*' list-colors ''

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Git Completions

# Load git completion functions (don't execute, just load)
autoload -Uz _git

# Define custom completion for git aliases
compdef __git_branch_names branch br
