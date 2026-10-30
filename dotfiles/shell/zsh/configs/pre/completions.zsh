# Completion System Configuration
# This file configures the fpath BEFORE compinit is called
# Pre-stage ensures completion directories are registered early

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Custom completions directory
fpath=(~/.zsh/completion $fpath)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Homebrew completions (if Homebrew is installed)
if command -v brew &> /dev/null; then
    # Homebrew's zsh function directory
    fpath=($(brew --prefix)/share/zsh/functions $fpath)

    # Homebrew's zsh site-functions (for casks and formulas)
    fpath=($(brew --prefix)/share/zsh/site-functions $fpath)
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# ASDF completions (if ASDF is available)
if [ -n "${ASDF_DIR:-}" ]; then
    fpath=(${ASDF_DIR}/completions $fpath)
elif [ -d "${ASDF_DATA_DIR:-$HOME/.asdf}/completions" ]; then
    fpath=(${ASDF_DATA_DIR:-$HOME/.asdf}/completions $fpath)
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Docker completions (if Docker Desktop is installed)
if [ -d "$HOME/.docker/completions" ]; then
    fpath=($HOME/.docker/completions $fpath)
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Export fpath for visibility
export FPATH
