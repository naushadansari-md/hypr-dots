#!/usr/bin/env bash

# minimal, NO set -e
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# import env (safe even if it fails)
systemctl --user import-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true

# run rofi
exec rofi -show drun
