#!/usr/bin/env bash
set -euo pipefail

DOCK_DIR="$HOME/.config/nwg-dock-hyprland"
THEME_FILE="$DOCK_DIR/dock-theme"
DISABLED_FILE="$DOCK_DIR/dock-disabled"

DOCK_THEME="glass"
ICON_SIZE="40"
WIDTH="5"
MB="10"
EXTRA_FLAGS=(-x)

# Disabled?
[[ -f "$DISABLED_FILE" ]] && exit 0

# Already running?
pgrep -f '^nwg-dock-hyprland' >/dev/null && exit 0

# Theme
if [[ -f "$THEME_FILE" ]]; then
  DOCK_THEME="$(<"$THEME_FILE")"
  DOCK_THEME="${DOCK_THEME//$'\r'/}"
  DOCK_THEME="${DOCK_THEME//$'\n'/}"
fi

STYLE_PATH="themes/${DOCK_THEME}/style.css"
[[ -f "$DOCK_DIR/$STYLE_PATH" ]] || STYLE_PATH="style.css"

LAUNCHER_CMD="$HOME/.config/hypr/scripts/dock-launcher-exec.sh"

cd "$DOCK_DIR"

nwg-dock-hyprland \
  -i "$ICON_SIZE" \
  -w "$WIDTH" \
  -mb "$MB" \
  "${EXTRA_FLAGS[@]}" \
  -s "$STYLE_PATH" \
  -c "$LAUNCHER_CMD" \
  >/dev/null 2>&1 &