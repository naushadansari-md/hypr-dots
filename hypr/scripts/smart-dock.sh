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
POLL_SEC="${POLL_SEC:-0.20}"              # cursor poll interval
STATE_REFRESH_MS="${STATE_REFRESH_MS:-600}"  # refresh window/fullscreen state
MON_REFRESH_MS="${MON_REFRESH_MS:-1000}"     # refresh monitor geometry
# ----------------------------------------

# Process name is >15 chars, so DO NOT use -x
is_running() { pgrep -f '^nwg-dock-hyprland(\s|$)' >/dev/null 2>&1; }
kill_dock()  { pkill -f '^nwg-dock-hyprland(\s|$)' 2>/dev/null || true; }

# Direct start (no login shell needed)
start_dock() { "$START_SCRIPT" >/dev/null 2>&1 || true; }

# Cheap wall-clock ms (guarded against time going backwards)
now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local s="${EPOCHREALTIME/./}"
    echo "${s:0:${#s}-3}"
  else
    date +%s%3N
  fi
}

# reveal state
zone_enter_ms=0
reveal_until_ms=0
hide_deadline_ms=0
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
  (( t < last_t )) && t=$last_t
  last_t=$t

  # ---------------- Monitor Refresh ----------------
  if (( t >= next_mon_refresh_ms || mon_w <= 0 || mon_h <= 0 )); then
    monitors_json="$(hyprctl monitors -j 2>/dev/null || echo '[]')"

    read -r mon_x mon_y mon_w mon_h <<<"$(
      jq -r 'first(.[] | select(.focused==true) | "\(.x) \(.y) \(.width) \(.height)") // "0 0 0 0"' \
        <<<"$monitors_json" 2>/dev/null
    )"

    mon_x="${mon_x:-0}"; mon_y="${mon_y:-0}"
    mon_w="${mon_w:-0}"; mon_h="${mon_h:-0}"

    if (( mon_w > 0 && mon_h > 0 )); then
      mon_right=$((mon_x + mon_w - 1))
      mon_bottom=$((mon_y + mon_h - 1))
      zone_top=$((mon_bottom - BOTTOM_ZONE_PX))
    else
      mon_right=0; mon_bottom=0; zone_top=0
    fi

    next_mon_refresh_ms=$((t + MON_REFRESH_MS))
  fi

  # ---------------- Cursor ----------------
  cursor_raw="$(hyprctl cursorpos 2>/dev/null || echo "0,0")"
  cursor_raw="${cursor_raw// /}"
  IFS=, read -r cx cy <<<"$cursor_raw"
  cx="${cx:-0}"; cy="${cy:-0}"

  zone_hit=0
  if (( mon_w > 0 && mon_h > 0 )); then
    if (( cx >= mon_x && cx <= mon_right && cy >= zone_top && cy <= mon_bottom )); then
      zone_hit=1
    fi
  fi

  # ---------------- Reveal Logic ----------------
  if (( zone_hit == 1 )); then
    (( zone_enter_ms == 0 )) && zone_enter_ms=$t
    (( t - zone_enter_ms >= SHOW_DELAY_MS )) && reveal_until_ms=$((t + REVEAL_HOLD_MS))
  else
    zone_enter_ms=0
  fi

  revealed=0
  (( reveal_until_ms > t )) && revealed=1

  # ---------------- Window State Refresh ----------------
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

  # ---------------- Final Rules ----------------
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

  # ---------------- Apply ----------------
  if [[ "$desired" == "show" ]]; then
    hide_deadline_ms=0
    ! is_running && start_dock
  else
    (( hide_deadline_ms == 0 )) && hide_deadline_ms=$((t + HIDE_DELAY_MS))
    if (( t >= hide_deadline_ms )); then
      hide_deadline_ms=0
      is_running && kill_dock
    fi
  fi

  sleep "$POLL_SEC"
done