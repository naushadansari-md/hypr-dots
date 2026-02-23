#!/usr/bin/env bash
set -euo pipefail

DOCK_MATCH='nwg-dock-hyprland'
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"
LOG="$HOME/.cache/nwg-dock-hyprland/dock-smart.log"

# Show dock when cursor is within this many pixels of bottom edge
EDGE_PX="${EDGE_PX:-25}"

# Poll interval (0.30–0.40 is smooth and lighter CPU)
POLL="${POLL:-0.30}"

mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

need() { command -v "$1" >/dev/null 2>&1; }
need hyprctl || { echo "Missing: hyprctl"; exit 1; }
need jq || { echo "Missing: jq (sudo pacman -S jq)"; exit 1; }
need flock || { echo "Missing: flock (util-linux)"; exit 1; }

is_running() { pgrep -af "$DOCK_MATCH" >/dev/null 2>&1; }
kill_dock() { pkill -f "$DOCK_MATCH" 2>/dev/null || true; }

# Log output of start script to help debugging (remove >>"$LOG" if you want silent)
start_dock() { bash -lc "$START_SCRIPT" >>"$LOG" 2>&1 || true; }

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/dock-smart.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log "=== dock-smart started (single monitor optimized) ==="
log "START_SCRIPT=$START_SCRIPT EDGE_PX=$EDGE_PX POLL=$POLL"

last=""

# Cache monitor geometry (single monitor). Refresh every N loops in case of resolution change.
refresh_every=40
i=0
mon_x=0 mon_y=0 mon_w=0 mon_h=0
mon_name=""

refresh_monitor() {
  local mon_json mon_info
  mon_json="$(hyprctl monitors -j)"
  # pick the focused monitor (single monitor laptop -> always correct)
  mon_info="$(jq -r '.[] | select(.focused==true) | "\(.name) \(.x) \(.y) \(.width) \(.height)"' <<<"$mon_json" | head -n1)"
  if [[ -n "$mon_info" ]]; then
    read -r mon_name mon_x mon_y mon_w mon_h <<<"$mon_info"
  fi
}

refresh_monitor

while true; do
  # refresh monitor geometry occasionally (handles resolution/scale changes)
  i=$((i+1))
  if (( i % refresh_every == 0 )); then
    refresh_monitor
  fi

  # Active workspace info
  ws_json="$(hyprctl activeworkspace -j)"
  wsid="$(jq -r '.id' <<<"$ws_json")"
  wsname="$(jq -r '.name' <<<"$ws_json")"

  # Get clients once
  clients_json="$(hyprctl clients -j)"

  # Count windows on active workspace
  win_count="$(
    jq --argjson wsid "$wsid" --arg wsname "$wsname" '
      [ .[]
        | select(
            (.workspace.id? == $wsid)
            or (.workspace? == $wsid)
            or (.workspace.name? == $wsname)
            or (.workspace? == $wsname)
        )
      ] | length
    ' <<<"$clients_json"
  )"

  # Any floating window on active workspace?
  float_any="$(
    jq -r --argjson wsid "$wsid" --arg wsname "$wsname" '
      any(.[]; (
          (.workspace.id? == $wsid)
          or (.workspace? == $wsid)
          or (.workspace.name? == $wsname)
          or (.workspace? == $wsname)
        )
        and ((.floating // false) == true)
      )
    ' <<<"$clients_json"
  )"

  # Cursor position: "x, y"
  cursor_raw="$(hyprctl cursorpos 2>/dev/null || echo "0,0")"
  cursor_raw="${cursor_raw// /}"
  IFS=, read -r cx cy <<<"$cursor_raw"
  cx="${cx:-0}"
  cy="${cy:-0}"

  # Bottom edge hit (single monitor -> simple)
  edge_hit=0
  mon_right=$((mon_x + mon_w - 1))
  mon_bottom=$((mon_y + mon_h - 1))
  if (( cx >= mon_x && cx <= mon_right && cy >= mon_bottom - EDGE_PX )); then
    edge_hit=1
  fi

  # State: show if workspace empty OR any floating OR cursor at bottom edge
  if [[ "$win_count" -eq 0 || "$float_any" == "true" || "$edge_hit" -eq 1 ]]; then
    state="show"
  else
    state="hide"
  fi

  # Log state change
  if [[ "$state" != "$last" ]]; then
    log "state change: $last -> $state (wsid=$wsid win_count=$win_count float_any=$float_any edge_hit=$edge_hit cursor=$cx,$cy mon=$mon_name bottom=$mon_bottom dock_running=$(is_running && echo yes || echo no))"
    last="$state"
  fi

  # Enforce state (restarts dock if it crashed)
  if [[ "$state" == "show" ]]; then
    if ! is_running; then
      log "enforce: starting dock"
      start_dock
    fi
  else
    if is_running; then
      log "enforce: killing dock"
      kill_dock
    fi
  fi

  sleep "$POLL"
done