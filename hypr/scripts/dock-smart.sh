#!/usr/bin/env bash
set -euo pipefail

DOCK_BIN="nwg-dock-hyprland"
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"
LOG="$HOME/.cache/nwg-dock-hyprland/dock-smart.log"

mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

have() { command -v "$1" >/dev/null 2>&1; }
have hyprctl || { echo "Missing: hyprctl"; exit 1; }
have jq     || { echo "Missing: jq (sudo pacman -S jq)"; exit 1; }
have flock  || { echo "Missing: flock (sudo pacman -S util-linux)"; exit 1; }

# -------- Dock helpers (safe) --------
is_running() { pgrep -x "$DOCK_BIN" >/dev/null 2>&1; }

kill_dock() {
  pkill -x "$DOCK_BIN" 2>/dev/null || true
  # fallback in case it was launched in an odd way
  pgrep -x "$DOCK_BIN" >/dev/null 2>&1 && pkill -f "$DOCK_BIN" 2>/dev/null || true
}

start_dock() {
  if [[ -x "$START_SCRIPT" ]]; then
    "$START_SCRIPT" >/dev/null 2>&1 || true
  else
    log "ERROR: start script not executable: $START_SCRIPT"
  fi
}

# -------- Lock (avoid duplicates) --------
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/dock-smart.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log "=== dock-smart started ==="
log "START_SCRIPT=$START_SCRIPT"

last=""

while true; do
  # active workspace id
  wsid="$(hyprctl activeworkspace -j | jq -r '.id')"

  # count windows in active workspace
  win_count="$(
    hyprctl clients -j \
      | jq --argjson wsid "$wsid" '[ .[] | select(.workspace.id == $wsid) ] | length'
  )"

  if [[ "$win_count" -eq 0 ]]; then
    state="show"
  else
    state="hide"
  fi

  if [[ "$state" != "$last" ]]; then
    log "state change: $last -> $state (wsid=$wsid win_count=$win_count dock_running=$(is_running && echo yes || echo no))"

    if [[ "$state" == "show" ]]; then
      if ! is_running; then
        log "starting dock"
        start_dock
      fi
    else
      if is_running; then
        log "killing dock"
        kill_dock
      fi
    fi

    last="$state"
  fi

  sleep 0.5
done