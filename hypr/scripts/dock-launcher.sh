#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="$HOME/.cache/nwg-dock-hyprland"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/launcher.log"

# log everything from dock click
exec >>"$LOG" 2>&1
echo "---- $(date '+%F %T') dock launcher click ----"

# import env when launched from dock
systemctl --user import-environment \
  WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE PATH DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true

dbus-update-activation-environment --systemd \
  WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE PATH DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true

export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Your rofi launcher script (recommended)
ROFI_SCRIPT="$HOME/.config/hypr/scripts/rofi-launcher.sh"

if [[ -x "$ROFI_SCRIPT" ]]; then
  echo "Running: $ROFI_SCRIPT"
  "$ROFI_SCRIPT"
else
  echo "rofi-launcher.sh missing/not executable -> running rofi drun"
  command -v rofi >/dev/null 2>&1 || { echo "ERROR: rofi not found"; exit 2; }
  rofi -show drun
fi
