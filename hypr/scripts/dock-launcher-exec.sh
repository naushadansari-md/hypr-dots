#!/usr/bin/env bash

# minimal, NO set -e
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"

# import env (safe even if it fails)
systemctl --user import-environment \
  WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS PATH \
  2>/dev/null || true

dbus-update-activation-environment --systemd \
  WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS PATH \
  2>/dev/null || true

# helps some desktop files / portals
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"

# run rofi
exec rofi -show drun