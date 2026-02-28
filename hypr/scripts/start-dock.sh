#!/usr/bin/env bash
set -euo pipefail

DOCK_DIR="$HOME/.config/nwg-dock-hyprland"
THEME_FILE="$DOCK_DIR/dock-theme"
DISABLED_FILE="$DOCK_DIR/dock-disabled"

DOCK_THEME="glass"
ICON_SIZE="40"
WIDTH="5"
MB="10"
EXTRA_FLAGS=()

# Disabled?
[[ -f "$DISABLED_FILE" ]] && exit 0

# Already running? (fine — just exit)
pgrep -f '^nwg-dock-hyprland(\s|$)' >/dev/null && exit 0

# Theme
if [[ -f "$THEME_FILE" ]]; then
  DOCK_THEME="$(<"$THEME_FILE")"
  DOCK_THEME="${DOCK_THEME//$'\r'/}"
  DOCK_THEME="${DOCK_THEME//$'\n'/}"
fi

STYLE_PATH="themes/${DOCK_THEME}/style.css"
[[ -f "$DOCK_DIR/$STYLE_PATH" ]] || STYLE_PATH="style.css"

LAUNCHER_CMD="$HOME/.config/hypr/scripts/dock-launcher-exec.sh nwg-drawer -ovl -c 7"

cd "$DOCK_DIR"

# IMPORTANT: -r (resident) so we can show/hide via signals
nwg-dock-hyprland \
  -r \
  -i "$ICON_SIZE" \
  -w "$WIDTH" \
  -mb "$MB" \
  "${EXTRA_FLAGS[@]}" \
  -s "$STYLE_PATH" \
  -c "$LAUNCHER_CMD" \
  >/dev/null 2>&1 &

# Start hidden (controller will show it on hover/rules)
sleep 0.15
pkill -RTMIN+3 -f '^nwg-dock-hyprland(\s|$)' 2>/dev/null || true