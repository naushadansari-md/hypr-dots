#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Paths
# -----------------------------
DOCK_DIR="$HOME/.config/nwg-dock-hyprland"
THEME_FILE="$DOCK_DIR/dock-theme"
DISABLED_FILE="$DOCK_DIR/dock-disabled"

# -----------------------------
# Dock config
# -----------------------------
DOCK_THEME="glass"   # default theme
ICON_SIZE="40"
WIDTH="5"
MB="10"
EXTRA_FLAGS=(-x)

# -----------------------------
# Import Wayland / DBus env
# -----------------------------
systemctl --user import-environment \
  WAYLAND_DISPLAY \
  XDG_RUNTIME_DIR \
  HYPRLAND_INSTANCE_SIGNATURE \
  DBUS_SESSION_BUS_ADDRESS \
  PATH 2>/dev/null || true

dbus-update-activation-environment --systemd \
  WAYLAND_DISPLAY \
  XDG_RUNTIME_DIR \
  HYPRLAND_INSTANCE_SIGNATURE \
  DBUS_SESSION_BUS_ADDRESS \
  PATH 2>/dev/null || true

# -----------------------------
# Resolve theme
# -----------------------------
if [[ -f "$THEME_FILE" ]]; then
  DOCK_THEME="$(<"$THEME_FILE")"
  DOCK_THEME="${DOCK_THEME//$'\r'/}"
  DOCK_THEME="${DOCK_THEME//$'\n'/}"
fi

STYLE_PATH="themes/${DOCK_THEME}/style.css"
if [[ ! -f "$DOCK_DIR/$STYLE_PATH" ]]; then
  STYLE_PATH="style.css"
fi

echo ":: Using Dock Theme: $DOCK_THEME"
echo ":: Style: $DOCK_DIR/$STYLE_PATH"

# -----------------------------
# Disabled?
# -----------------------------
if [[ -f "$DISABLED_FILE" ]]; then
  echo ":: Dock disabled"
  exit 0
fi

# -----------------------------
# Launcher (MUST be direct executable)
# -----------------------------
LAUNCHER_CMD="$HOME/.config/hypr/scripts/dock-launcher-exec.sh"

if [[ ! -x "$LAUNCHER_CMD" ]]; then
  echo ":: ERROR: Launcher not executable: $LAUNCHER_CMD"
  exit 1
fi

# -----------------------------
# Restart dock cleanly
# -----------------------------
pkill -f nwg-dock-hyprland 2>/dev/null || true
sleep 0.2

# -----------------------------
# Build args
# NOTE: NO -d autohide here
# dock-smart.sh controls visibility
# -----------------------------
ARGS=(
  -i "$ICON_SIZE"
  -w "$WIDTH"
  -mb "$MB"
  "${EXTRA_FLAGS[@]}"
  -s "$STYLE_PATH"
  -c "$LAUNCHER_CMD"
)

echo ":: Dock mode: smart (0 windows = visible)"

# -----------------------------
# Start dock
# -----------------------------
nwg-dock-hyprland "${ARGS[@]}" &
disown

echo ":: Dock started"
