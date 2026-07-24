#!/bin/bash

# Ensure kitty-themes is cloned locally so we have all the .conf files
THEME_DIR="$HOME/.config/kitty/kitty-themes"

if [ ! -d "$THEME_DIR" ]; then
  echo "Cloning kitty-themes repository for the first time..."
  mkdir -p "$HOME/.config/kitty"
  git clone --depth 1 https://github.com/kovidgoyal/kitty-themes.git "$THEME_DIR"
fi

# Get all the available .conf theme files
# Nullglob prevents the array from having "*.conf" if empty
shopt -s nullglob
THEMES=("$THEME_DIR/themes/"*.conf)
shopt -u nullglob

THEME_COUNT=${#THEMES[@]}

if [ $THEME_COUNT -eq 0 ]; then
  echo "Error: No themes found in $THEME_DIR/themes. Try deleting the directory and running again."
  exit 1
fi

# Pick a random theme
RANDOM_INDEX=$((RANDOM % THEME_COUNT))
SELECTED_THEME_FILE="${THEMES[$RANDOM_INDEX]}"
THEME_NAME=$(basename "$SELECTED_THEME_FILE" .conf)

echo "Setting theme to: $THEME_NAME (for ALL windows)"

# Use kitty remote control to change the colors in ALL windows.
# The --all (-a) flag forces it to apply across every terminal pane/tab/window.
# The --configured (-c) flag makes new windows use this theme too.
# This requires `allow_remote_control yes` in your kitty.conf
kitty @ set-colors -a -c "$SELECTED_THEME_FILE"
