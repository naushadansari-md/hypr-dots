#!/usr/bin/env bash
set -euo pipefail

DOCK_MATCH='nwg-dock-hyprland'
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"
LOG="$HOME/.cache/nwg-dock-hyprland/dock-smart.log"

# Bottom zone height in pixels (must be >= dock height so you can click icons)
BOTTOM_ZONE_PX="${BOTTOM_ZONE_PX:-32}"

# Poll interval
POLL="${POLL:-0.50}"

# Hide delay to prevent flicker
HIDE_DELAY="${HIDE_DELAY:-0.20}"

mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

need() { command -v "$1" >/dev/null 2>&1; }
need hyprctl || { echo "Missing: hyprctl"; exit 1; }
need jq || { echo "Missing: jq"; exit 1; }
need flock || { echo "Missing: flock"; exit 1; }

is_running() { pgrep -af "$DOCK_MATCH" >/dev/null 2>&1; }
kill_dock() { pkill -f "$DOCK_MATCH" 2>/dev/null || true; }
start_dock() { bash -lc "$START_SCRIPT" >>"$LOG" 2>&1 || true; }

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/dock-smart.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log "=== dock-smart started (bottom-zone + hide delay) ==="
log "START_SCRIPT=$START_SCRIPT BOTTOM_ZONE_PX=$BOTTOM_ZONE_PX POLL=$POLL HIDE_DELAY=$HIDE_DELAY"

last=""
pending_hide=0

# Single monitor geometry (focused)
mon_json="$(hyprctl monitors -j)"
read -r mon_name mon_x mon_y mon_w mon_h <<<"$(
  jq -r '.[] | select(.focused==true) | "\(.name) \(.x) \(.y) \(.width) \(.height)"' <<<"$mon_json" | head -n1
)"

while true; do
  ws_json="$(hyprctl activeworkspace -j)"
  wsid="$(jq -r '.id' <<<"$ws_json")"
  wsname="$(jq -r '.name' <<<"$ws_json")"

  clients_json="$(hyprctl clients -j)"

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

  # Cursor pos
  cursor_raw="$(hyprctl cursorpos 2>/dev/null || echo "0,0")"
  cursor_raw="${cursor_raw// /}"
  IFS=, read -r cx cy <<<"$cursor_raw"
  cx="${cx:-0}"
  cy="${cy:-0}"

  # Bottom zone hit (NOT just 25px edge)
  mon_right=$((mon_x + mon_w - 1))
  mon_bottom=$((mon_y + mon_h - 1))
  zone_hit=0
  if (( cx >= mon_x && cx <= mon_right && cy >= mon_bottom - BOTTOM_ZONE_PX )); then
    zone_hit=1
  fi

  # Desired state: empty OR any floating OR cursor in bottom zone
  if [[ "$win_count" -eq 0 || "$float_any" == "true" || "$zone_hit" -eq 1 ]]; then
    desired="show"
  else
    desired="hide"
  fi

  if [[ "$desired" == "show" ]]; then
    pending_hide=0
    if [[ "$last" != "show" ]]; then
      log "state change: $last -> show (win_count=$win_count float_any=$float_any zone_hit=$zone_hit)"
      last="show"
    fi
    if ! is_running; then
      start_dock
    fi
  else
    # hide with delay (prevents flicker)
    if [[ "$last" != "hide" ]]; then
      if (( pending_hide == 0 )); then
        pending_hide=1
        sleep "$HIDE_DELAY"
        continue
      fi
      log "state change: $last -> hide (win_count=$win_count float_any=$float_any zone_hit=$zone_hit)"
      last="hide"
      pending_hide=0
      if is_running; then
        kill_dock
      fi
    fi
  fi

  sleep "$POLL"
done