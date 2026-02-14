#!/usr/bin/env bash
set -euo pipefail

DOCK_MATCH='nwg-dock-hyprland'
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"
LOG="$HOME/.cache/nwg-dock-hyprland/dock-smart.log"

mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

need() { command -v "$1" >/dev/null 2>&1; }
need hyprctl || { echo "Missing: hyprctl"; exit 1; }
need jq || { echo "Missing: jq (sudo pacman -S jq)"; exit 1; }

is_running() { pgrep -af "$DOCK_MATCH" >/dev/null 2>&1; }
kill_dock() { pkill -f "$DOCK_MATCH" 2>/dev/null || true; }
start_dock() { bash -lc "$START_SCRIPT" >/dev/null 2>&1 || true; }

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/dock-smart.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log "=== dock-smart started ==="
log "START_SCRIPT=$START_SCRIPT"

last=""

while true; do
  ws_json="$(hyprctl activeworkspace -j)"
  wsid="$(jq -r '.id' <<<"$ws_json")"
  wsname="$(jq -r '.name' <<<"$ws_json")"

  win_count="$(
    hyprctl clients -j | jq --argjson wsid "$wsid" --arg wsname "$wsname" '
      [ .[]
        | select(
            (.workspace.id? == $wsid)
            or (.workspace? == $wsid)
            or (.workspace.name? == $wsname)
            or (.workspace? == $wsname)
        )
      ] | length
    '
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

  sleep 0.4
done
