#!/usr/bin/env bash
# ---------------------------------------------------------
# swww + matugen + waybar + dock reload
# ---------------------------------------------------------

set -Eeuo pipefail

# ----------------------------
# Wayland session env
# ----------------------------
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
    export WAYLAND_DISPLAY="wayland-0"
  else
    sock="$(ls -1 "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -n1 || true)"
    [[ -n "$sock" ]] && export WAYLAND_DISPLAY="$(basename "$sock")"
  fi
fi

# ----------------------------
# Variables
# ----------------------------
WALLPAPERS_DIR="$HOME/.config/hypr/wallpapers"
DOCK_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"

have() { command -v "$1" >/dev/null 2>&1; }
fail() { echo "FAIL: $*"; exit 1; }

# ----------------------------
# Pick wallpaper
# ----------------------------
pick_random() {
  find "$WALLPAPERS_DIR" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    | shuf -n 1
}

wallpaper="${1:-}"
[[ -z "$wallpaper" ]] && wallpaper="$(pick_random || true)"

[[ -n "${wallpaper:-}" ]] || fail "No wallpaper found"
[[ -f "$wallpaper" ]] || fail "Wallpaper not found: $wallpaper"

echo "Wallpaper: $wallpaper"

# ----------------------------
# Set wallpaper (instant change)
# ----------------------------
if have swww; then
  if ! swww query >/dev/null 2>&1; then
    pkill -x swww-daemon 2>/dev/null || true
    swww init >/dev/null 2>&1 || true
    sleep 0.25
  fi

  swww img "$wallpaper" >/dev/null 2>&1 || true
fi

# ----------------------------
# Generate theme (matugen)
# ----------------------------
have matugen && matugen image "$wallpaper" || true

# ----------------------------
# Reload Waybar
# ----------------------------
if have waybar; then
  pkill -SIGUSR2 waybar 2>/dev/null || true
  sleep 0.1
  pgrep -x waybar >/dev/null 2>&1 || waybar >/dev/null 2>&1 &
fi

# ----------------------------
# Restart Dock
# ----------------------------
dock_pat='(^|/)(nwg-dock-hyprland)(\s|$)'

if pgrep -f "$dock_pat" >/dev/null 2>&1; then
  pkill -f "$dock_pat" 2>/dev/null || true

  for _ in {1..20}; do
    pgrep -f "$dock_pat" >/dev/null 2>&1 || break
    sleep 0.05
  done

  [[ -x "$DOCK_SCRIPT" ]] && "$DOCK_SCRIPT" >/dev/null 2>&1 || true
fi

echo "DONE"