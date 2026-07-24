#!/usr/bin/env bash
# Step 25 — Install and wire up the local opn (cli-rust-menu) project
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

msg "Installing and wiring up opn (cli-rust-menu)..."

OPN_DIR="$HOME/Projects/cli-rust-menu"

if [ -d "$OPN_DIR" ]; then
    if have cargo; then
        msg "Installing opn binary from $OPN_DIR..."
        (cd "$OPN_DIR" && cargo install --path .)
        
        msg "Hooking opn into yazi and broot..."
        if [ -x "$OPN_DIR/scripts/hook-navigators.sh" ]; then
            "$OPN_DIR/scripts/hook-navigators.sh"
        else
            bash "$OPN_DIR/scripts/hook-navigators.sh"
        fi
        
        msg "opn has been installed and hooked into the file managers."
    else
        warn "cargo is not available; cannot install opn."
    fi
else
    warn "Could not find $OPN_DIR. Please clone cli-rust-menu into ~/Projects to install opn."
fi
