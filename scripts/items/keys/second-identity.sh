#!/usr/bin/env bash
#
# maclift item: second git identity for one folder (~/.gitconfig.alt).
#   second-identity.sh --check   exit 0 when .gitconfig.alt matches user.conf (hand-added settings aside)
#   second-identity.sh           write ~/.gitconfig.alt from user.conf
# The folder, name and email are asked by maclift itself and kept in user.conf.
# Works only inside $MACLIFT_HOME and user.conf.

set -eo pipefail

MACLIFT_DIR="${MACLIFT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=lib/core.sh
source "$MACLIFT_DIR/lib/core.sh"
# shellcheck source=lib/conf.sh
source "$MACLIFT_DIR/lib/conf.sh"
# shellcheck source=lib/ui.sh
source "$MACLIFT_DIR/lib/ui.sh"
# shellcheck source=lib/dotfiles.sh
source "$MACLIFT_DIR/lib/dotfiles.sh"
# shellcheck source=lib/identity.sh
source "$MACLIFT_DIR/lib/identity.sh"
maclift_init_paths

if [ "${1:-}" = "--check" ]; then
  identity_alt_current
  exit $?
fi

identity_render_alt 0
