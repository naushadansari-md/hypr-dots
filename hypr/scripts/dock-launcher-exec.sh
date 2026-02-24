#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Logging
# =========================
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nwg-dock-hyprland"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/launcher.log"

# =========================
# Ensure PATH (important for Hyprland/Waybar launches)
# =========================
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Default command if none provided
if [[ $# -lt 1 ]]; then
  set -- "nwg-drawer"
fi

CMD="$1"
shift || true

{
  echo "---- $(date '+%F %T') ----"
  echo "dock-launcher-exec.sh running: $CMD $*"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<empty>}"
  echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<empty>}"
  echo "PATH=$PATH"
} >> "$LOG_FILE"

# Run detached and log stdout/stderr
if command -v setsid >/dev/null 2>&1; then
  # -f = fork, so this script can exit immediately
  setsid -f "$CMD" "$@" >> "$LOG_FILE" 2>&1 || true
else
  nohup "$CMD" "$@" >> "$LOG_FILE" 2>&1 & disown || true
fi

exit 0