# Auto-recolor: pick a random ghostty theme on each new interactive ghostty shell.
# $GHOSTTY_RESOURCES_DIR is exported by ghostty into the shells it spawns, so this is
# a no-op in any other terminal. Sourced from ~/.zshrc by cli-tools-installer.
if [[ -n "$GHOSTTY_RESOURCES_DIR" && -o interactive ]] && command -v color-ghostty >/dev/null 2>&1; then
    color-ghostty >/dev/null 2>&1
fi
