# ensure dotfiles bin directory is loaded first
PATH="$HOME/.bin:/usr/local/bin:$PATH"

# Source ASDF if installed via Homebrew
if command -v brew &> /dev/null; then
    ASDF_SCRIPT="$(brew --prefix asdf 2>/dev/null)/libexec/asdf.sh"
    if [ -f "$ASDF_SCRIPT" ]; then
        . "$ASDF_SCRIPT"
    fi
fi

# Fallback: Add ASDF shims to PATH
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
export -U PATH
