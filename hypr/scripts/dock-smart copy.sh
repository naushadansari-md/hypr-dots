#!/usr/bin/env bash
set -uo pipefail

DOCK_MATCH='nwg-dock-hyprland'
DOCK_CLASS='nwg-dock-hyprland'
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"

# ---------- Tuning (macOS feel) ----------
SHOW_DELAY_MS="${SHOW_DELAY_MS:-180}"     # cursor must stay in bottom zone before showing
REVEAL_HOLD_MS="${REVEAL_HOLD_MS:-450}"   # keep visible after leaving zone
HIDE_DELAY_MS="${HIDE_DELAY_MS:-250}"     # delay before hiding

BOTTOM_ZONE_PX="${BOTTOM_ZONE_PX:-32}"

# Responsiveness vs CPU
POLL_SEC="${POLL_SEC:-0.20}"             # cursor poll interval (0.15=snappier, 0.25=lower wakeups)
STATE_REFRESH_MS="${STATE_REFRESH_MS:-600}" # refresh window/fullscreen state every 0.6s
MON_REFRESH_MS="${MON_REFRESH_MS:-1000}"   # refresh monitor geometry every 1.0s
# ----------------------------------------

# Prefer exact-name matching if available (faster/safer), fallback to your original match
if pgrep -x "nwg-dock-hyprland" >/dev/null 2>&1; then
  is_running() { pgrep -x "nwg-dock-hyprland" >/dev/null 2>&1; }
  kill_dock()  { pkill -x "nwg-dock-hyprland" 2>/dev/null || true; }
else
  is_running() { pgrep -af "$DOCK_MATCH" >/dev/null 2>&1; }
  kill_dock()  { pkill -f "$DOCK_MATCH" 2>/dev/null || true; }
fi

# Keep your original behavior (login shell), in case start script relies on env
start_dock() { bash -lc "$START_SCRIPT" >/dev/null 2>&1 || true; }

# Cheap wall-clock ms (guarded against time going backwards)
now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local s="${EPOCHREALTIME/./}"
    echo "${s:0:${#s}-3}"   # ms
  else
    date +%s%3N
  fi
}

# reveal state
zone_enter_ms=0
reveal_until_ms=0
hide_deadline_ms=0

# monotonic guard
last_t=0

# cached monitor geometry
mon_x=0 mon_y=0 mon_w=0 mon_h=0
mon_right=0 mon_bottom=0 zone_top=0
next_mon_refresh_ms=0

# cached window/fullscreen state
ws_hasfullscreen=false
total_count=0
tiled_count=0
next_state_refresh_ms=0

while true; do
  t="$(now_ms)"
  # Guard against system time adjustments going backwards (NTP)
  if (( t < last_t )); then t=$last_t; fi
  last_t=$t

  # Refresh focused monitor geometry only occasionally (single monitor)
  if (( t >= next_mon_refresh_ms || mon_w <= 0 || mon_h <= 0 )); then
    monitors_json="$(hyprctl monitors -j 2>/dev/null || echo '[]')"

    read -r mon_x mon_y mon_w mon_h <<<"$(
      jq -r 'first(.[] | select(.focused==true) | "\(.x) \(.y) \(.width) \(.height)") // "0 0 0 0"' \
        <<<"$monitors_json" 2>/dev/null
    )"

    mon_x="${mon_x:-0}"; mon_y="${mon_y:-0}"; mon_w="${mon_w:-0}"; mon_h="${mon_h:-0}"

    if (( mon_w > 0 && mon_h > 0 )); then
      mon_right=$((mon_x + mon_w - 1))
      mon_bottom=$((mon_y + mon_h - 1))
      zone_top=$((mon_bottom - BOTTOM_ZONE_PX))
    else
      mon_right=0; mon_bottom=0; zone_top=0
    fi

    next_mon_refresh_ms=$((t + MON_REFRESH_MS))
  fi

  # Cursor position (polled; required for reveal feature)
  cursor_raw="$(hyprctl cursorpos 2>/dev/null || echo "0,0")"
  cursor_raw="${cursor_raw// /}"
  IFS=, read -r cx cy <<<"$cursor_raw"
  cx="${cx:-0}"; cy="${cy:-0}"

  # Bottom zone hit (safe)
  zone_hit=0
  if (( mon_w > 0 && mon_h > 0 )); then
    if (( cx >= mon_x && cx <= mon_right && cy >= zone_top && cy <= mon_bottom )); then
      zone_hit=1
    fi
  fi

  # ---- macOS-like reveal timing ----
  if (( zone_hit == 1 )); then
    if (( zone_enter_ms == 0 )); then
      zone_enter_ms=$t
    fi
    if (( t - zone_enter_ms >= SHOW_DELAY_MS )); then
      reveal_until_ms=$((t + REVEAL_HOLD_MS))
    fi
  else
    zone_enter_ms=0
  fi

  revealed=0
  if (( reveal_until_ms > t )); then
    revealed=1
  fi
  # ---------------------------------

  # Refresh heavy state only every STATE_REFRESH_MS,
  # and skip it while revealed (dock is forced visible anyway)
  if (( revealed == 0 && t >= next_state_refresh_ms )); then
    wsid="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null || echo 0)"
    clients_json="$(hyprctl clients -j 2>/dev/null || echo '[]')"
    workspaces_json="$(hyprctl workspaces -j 2>/dev/null || echo '[]')"

    ws_hasfullscreen="$(
      jq --argjson wsid "$wsid" -r '(.[] | select(.id == $wsid) | .hasfullscreen) // false' \
        <<<"$workspaces_json" 2>/dev/null || echo false
    )"

    read -r total_count tiled_count <<<"$(
      jq --argjson wsid "$wsid" --arg dock "$DOCK_CLASS" -r '
        def isdock:
          ((.class // "") == $dock) or ((.initialClass // "") == $dock);

        [ .[]
          | select(.workspace.id == $wsid)
          | select(isdock | not)
        ] as $w
        | ($w | length) as $total
        | ($w | map(select((.floating // false) == false)) | length) as $tiled
        | "\($total) \($tiled)"
      ' <<<"$clients_json" 2>/dev/null || echo "0 0"
    )"
    total_count="${total_count:-0}"
    tiled_count="${tiled_count:-0}"

    next_state_refresh_ms=$((t + STATE_REFRESH_MS))
  fi

  # FINAL RULES (your working reference behavior)
  if (( revealed == 1 )); then
    desired="show"
  elif [[ "$ws_hasfullscreen" == "true" ]]; then
    desired="hide"
  elif (( total_count == 0 )); then
    desired="show"
  elif (( total_count > 0 && tiled_count == 0 )); then
    desired="show"
  else
    desired="hide"
  fi

  # Apply with HIDE_DELAY_MS
  if [[ "$desired" == "show" ]]; then
    hide_deadline_ms=0
    if ! is_running; then
      start_dock
    fi
  else
    if (( hide_deadline_ms == 0 )); then
      hide_deadline_ms=$((t + HIDE_DELAY_MS))
    fi
    if (( t >= hide_deadline_ms )); then
      hide_deadline_ms=0
      if is_running; then
        kill_dock
      fi
    fi
  fi

  sleep "$POLL_SEC"
done