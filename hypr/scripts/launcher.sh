#!/usr/bin/env bash
# Auto launcher: prefers nwg-drawer, then rofi, then wofi.

if command -v nwg-drawer >/dev/null 2>&1; then
  exec nwg-drawer
elif command -v rofi >/dev/null 2>&1; then
  exec rofi -show drun
elif command -v wofi >/dev/null 2>&1; then
  exec wofi --show drun
else
  notify-send "Launcher missing" "Install nwg-drawer or rofi or wofi"
  exit 1
fi
