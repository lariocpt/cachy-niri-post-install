#!/usr/bin/env bash
# Step 26 — Install and wire up niri-spaces
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

msg "Installing niri-spaces..."

SPACES_DIR="$HOME/Projects/niri-spaces"

if [ -d "$SPACES_DIR" ] && [ -x "$SPACES_DIR/install.sh" ]; then
    msg "Found niri-spaces. Running its install.sh script..."
    "$SPACES_DIR/install.sh"
    msg "niri-spaces has been installed."
else
    warn "Could not find $SPACES_DIR/install.sh. Please ensure niri-spaces is cloned to ~/Projects."
fi
