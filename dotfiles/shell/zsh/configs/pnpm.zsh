command -v pnpm >/dev/null 2>&1 || return 0

# Where `pnpm add -g` puts global packages (the folder `pnpm setup` picks on
# macOS). pnpm 12 puts their commands in $PNPM_HOME/bin.
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
