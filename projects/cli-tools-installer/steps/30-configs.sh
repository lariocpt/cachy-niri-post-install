#!/usr/bin/env bash
# Step 30 — configs. Runs as the user. Installs color-ghostty + the interactive
# shell hook, seeds a ghostty config, and lays down the yazi base sections
# ([mgr] + [preview]) WITHOUT touching [opener]/[open] (owned by yazi-opener-config).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

ASSETS="$ROOT/assets"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$CONFIG_HOME/cli-tools-installer"

[ "$(id -u)" -eq 0 ] && warn "running as root: configs will be written to root's HOME, not yours"

# --- 0. Oh My Zsh (zsh framework) ----------------------------------------------
# Cloned (not via the upstream installer, which would rewrite ~/.zshrc and chsh).
# Activated through a guarded block, skipped if ~/.zshrc already uses oh-my-zsh.
OMZ_DIR="$HOME/.oh-my-zsh"
if [ -d "$OMZ_DIR" ]; then
    msg "Oh My Zsh already installed ($OMZ_DIR) — skipping clone"
elif [ "$DRY_RUN" = 1 ]; then
    dryrun_note "would clone Oh My Zsh -> $OMZ_DIR (and activate it in ~/.zshrc)"
elif have git; then
    msg "installing Oh My Zsh ..."
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR" \
        && msg "installed Oh My Zsh -> $OMZ_DIR" \
        || warn "Oh My Zsh clone failed (network/git?) — continuing"
else
    warn "git not found — skipping Oh My Zsh (run the packages step first, or install git)"
fi

# Activate in ~/.zshrc only if the user has/uses zsh, and not if it already loads OMZ.
if { [ -d "$OMZ_DIR" ] || [ "$DRY_RUN" = 1 ]; } && { [ -f "$HOME/.zshrc" ] || [ "${SHELL##*/}" = zsh ]; }; then
    if [ -f "$HOME/.zshrc" ] && grep -q 'oh-my-zsh' "$HOME/.zshrc" 2>/dev/null; then
        msg ".zshrc already references oh-my-zsh — not adding an activation block"
    else
        OMZ_BLOCK=$'export ZSH="$HOME/.oh-my-zsh"\nZSH_THEME="robbyrussell"\nplugins=(git sudo)\n[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'
        backup_rc_once "$HOME/.zshrc"
        append_sentinel_block "$HOME/.zshrc" "oh-my-zsh" "$OMZ_BLOCK"
    fi
elif [ -d "$OMZ_DIR" ]; then
    msg "Oh My Zsh installed but not activated (no ~/.zshrc and shell isn't zsh)"
fi

# --- 1. color-ghostty script ---------------------------------------------------
msg "installing color-ghostty ..."
if [ "$DRY_RUN" = 1 ]; then
    dryrun_note "would install color-ghostty -> $LOCAL_BIN/color-ghostty"
else
    install -d "$LOCAL_BIN"
    install -m0755 "$ASSETS/bin/color-ghostty" "$LOCAL_BIN/color-ghostty"
    msg "installed color-ghostty -> $LOCAL_BIN/color-ghostty"
fi

# --- 2. seed ghostty config (only if absent) -----------------------------------
GHOSTTY_CFG="$CONFIG_HOME/ghostty/config"
if [ -e "$GHOSTTY_CFG" ]; then
    msg "ghostty config exists — leaving it (color-ghostty updates only its theme line)"
elif [ "$DRY_RUN" = 1 ]; then
    dryrun_note "would seed $GHOSTTY_CFG"
else
    install -d "$(dirname "$GHOSTTY_CFG")"
    install -m0644 "$ASSETS/ghostty/config.seed" "$GHOSTTY_CFG"
    msg "seeded $GHOSTTY_CFG"
fi

# --- 3. shell hook snippets + guarded rc wiring --------------------------------
if [ "$DRY_RUN" = 1 ]; then
    dryrun_note "would install hook snippets into $HOOK_DIR and wire ~/.zshrc / ~/.bashrc"
else
    install -d "$HOOK_DIR"
    install -m0644 "$ASSETS/shell/color-ghostty.zsh"  "$HOOK_DIR/color-ghostty.zsh"
    install -m0644 "$ASSETS/shell/color-ghostty.bash" "$HOOK_DIR/color-ghostty.bash"
    install -m0644 "$ASSETS/shell/yazi-broot.zsh"     "$HOOK_DIR/yazi-broot.zsh"
    install -m0644 "$ASSETS/shell/yazi-broot.bash"    "$HOOK_DIR/yazi-broot.bash"
fi

# PATH guard written verbatim (single-quoted -> expanded at shell-init, not now).
PATH_GUARD='case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'

wire_rc() {  # <rcfile> <snippet-basename>
    local rc="$1" snip="$2"
    backup_rc_once "$rc"   # one pristine snapshot before any of our blocks
    append_sentinel_block "$rc" "local-bin PATH" "$PATH_GUARD"
    append_sentinel_block "$rc" "color-ghostty hook" \
        "[ -f \"$HOOK_DIR/$snip\" ] && . \"$HOOK_DIR/$snip\""
    
    local ysnip="yazi-broot.${snip##*.}"
    append_sentinel_block "$rc" "yazi-broot hook" \
        "[ -f \"$HOOK_DIR/$ysnip\" ] && . \"$HOOK_DIR/$ysnip\""
}

wired=0
if [ -f "$HOME/.zshrc" ];  then wire_rc "$HOME/.zshrc"  color-ghostty.zsh;  wired=1; fi
if [ -f "$HOME/.bashrc" ]; then wire_rc "$HOME/.bashrc" color-ghostty.bash; wired=1; fi
if [ "$wired" = 0 ]; then
    case "${SHELL:-}" in
        *zsh) wire_rc "$HOME/.zshrc"  color-ghostty.zsh ;;
        *)    wire_rc "$HOME/.bashrc" color-ghostty.bash ;;
    esac
fi

# --- 4. yazi base config ([mgr] + [preview]); never touch [opener]/[open] ------
install_yazi_base() {
    local cfg="$1" base="$2"
    if [ ! -e "$cfg" ]; then
        if [ "$DRY_RUN" = 1 ]; then dryrun_note "would create $cfg from base ([mgr]+[preview])"; return 0; fi
        install -d "$(dirname "$cfg")"
        install -m0644 "$base" "$cfg"
        msg "wrote yazi base config -> $cfg"
        return 0
    fi
    if grep -qE '^\[(mgr|preview)\]' "$cfg" 2>/dev/null; then
        msg "yazi.toml already has [mgr]/[preview] — leaving untouched"
        return 0
    fi
    # File exists but lacks our sections (e.g. yazi-opener-config wrote [opener]/[open]
    # first): prepend [mgr]+[preview] above everything so those sections stay intact.
    if [ "$DRY_RUN" = 1 ]; then dryrun_note "would prepend [mgr]+[preview] to existing $cfg"; return 0; fi
    backup_path "$cfg"
    local tmp; tmp="$(mktemp)"
    { cat "$base"; printf '\n'; cat "$cfg"; } > "$tmp"
    install -m0644 "$tmp" "$cfg"
    rm -f "$tmp"
    msg "prepended [mgr]+[preview] to $cfg (existing sections preserved)"
}
install_yazi_base "$CONFIG_HOME/yazi/yazi.toml" "$ASSETS/yazi/yazi.base.toml"

msg "configs step complete."
