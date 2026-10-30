# Let gpg's pinentry prompt on this terminal (needed for commit signing).
if [[ -t 0 ]]; then
    export GPG_TTY=$(tty)
fi
