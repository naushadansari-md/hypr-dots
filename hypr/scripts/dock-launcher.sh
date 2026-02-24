#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Logging
# =========================
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nwg-dock-hyprland"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/launcher.log"

{
  echo "---- $(date '+%F %T') ----"
  echo "dock-launcher.sh started"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<empty>}"
  echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<empty>}"
} >> "$LOG_FILE"

# =========================
# Ensure PATH (important for Hyprland/Waybar launches)
# =========================
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
echo "PATH=$PATH" >> "$LOG_FILE"

# =========================
# Find nwg-drawer
# =========================
DRAWER_BIN="$(command -v nwg-drawer || true)"
if [[ -z "${DRAWER_BIN:-}" ]]; then
  echo "ERROR: nwg-drawer not found in PATH" >> "$LOG_FILE"
  exit 2
fi

# =========================
# Kill old instance so margins update
# =========================
pkill -x nwg-drawer 2>/dev/null && exit 0

# =========================
# Mac-style preset with space under Waybar
# Tune these values as you like
# =========================
ARGS=(
  -ovl
  -a bottom
  -c 7
  -is 72
  -spacing 18
  -mt 240
  -mb 120
  -ml 300
  -mr 300
)

echo "Launching: $DRAWER_BIN ${ARGS[*]}" >> "$LOG_FILE"

exec "$DRAWER_BIN" "${ARGS[@]}"