#!/usr/bin/env bash
set -uo pipefail

DOCK_MATCH='nwg-dock-hyprland'
DOCK_CLASS='nwg-dock-hyprland'
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"

# ---------- Tuning (macOS feel) ----------
SHOW_DELAY_MS="${SHOW_DELAY_MS:-180}"     # cursor must stay in bottom zone before showing
REVEAL_HOLD_MS="${REVEAL_HOLD_MS:-450}"   # keep visible after leaving zone
HIDE_DELAY_MS="${HIDE_DELAY_MS:-250}"     # delay before hiding

BOTTOM_ZONE_PX="${BOTTOM_ZONE_PX:-20}"
POLL_SEC="${POLL_SEC:-0.10}"
# ----------------------------------------

is_running() { pgrep -af "$DOCK_MATCH" >/dev/null 2>&1; }
kill_dock()  { pkill -f "$DOCK_MATCH" 2>/dev/null || true; }
start_dock() { bash -lc "$START_SCRIPT" >/dev/null 2>&1 || true; }

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
}

# macOS reveal state
zone_enter_ms=0
reveal_until_ms=0
hide_deadline_ms=0

while true; do
  t="$(now_ms)"

  wsid="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null || echo 0)"
  clients_json="$(hyprctl clients -j 2>/dev/null || echo '[]')"
  workspaces_json="$(hyprctl workspaces -j 2>/dev/null || echo '[]')"
  monitors_json="$(hyprctl monitors -j 2>/dev/null || echo '[]')"

  # Workspace fullscreen (from workspaces -j)
  ws_hasfullscreen="$(
    jq --argjson wsid "$wsid" -r '(.[] | select(.id == $wsid) | .hasfullscreen) // false' \
      <<<"$workspaces_json" 2>/dev/null || echo false
  )"

  # Total windows excluding dock
  total_count="$(
    jq --argjson wsid "$wsid" --arg dock "$DOCK_CLASS" '
      [ .[]
        | select(.workspace.id == $wsid)
        | select((.class // "") != $dock)
        | select((.initialClass // "") != $dock)
      ] | length
    ' <<<"$clients_json" 2>/dev/null || echo 0
  )"

  # Tiled windows count (floating=false) excluding dock
  tiled_count="$(
    jq --argjson wsid "$wsid" --arg dock "$DOCK_CLASS" '
      [ .[]
        | select(.workspace.id == $wsid)
        | select((.class // "") != $dock)
        | select((.initialClass // "") != $dock)
        | select((.floating // false) == false)
      ] | length
    ' <<<"$clients_json" 2>/dev/null || echo 0
  )"

  # Focused monitor geometry (safe)
  read -r mon_x mon_y mon_w mon_h <<<"$(
    jq -r '.[] | select(.focused==true) | "\(.x) \(.y) \(.width) \(.height)"' \
      <<<"$monitors_json" 2>/dev/null | head -n1
  )"
  mon_x="${mon_x:-0}"; mon_y="${mon_y:-0}"; mon_w="${mon_w:-0}"; mon_h="${mon_h:-0}"

  # Cursor position (safe)
  cursor_raw="$(hyprctl cursorpos 2>/dev/null || echo "0,0")"
  cursor_raw="${cursor_raw// /}"
  IFS=, read -r cx cy <<<"$cursor_raw"
  cx="${cx:-0}"; cy="${cy:-0}"

  # Bottom zone hit (safe)
  zone_hit=0
  if (( mon_w > 0 && mon_h > 0 )); then
    mon_right=$((mon_x + mon_w - 1))
    mon_bottom=$((mon_y + mon_h - 1))
    zone_top=$((mon_bottom - BOTTOM_ZONE_PX))
    if (( cx >= mon_x && cx <= mon_right && cy >= zone_top )); then
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

  # FINAL RULES:
  # - revealed (bottom zone) => show always
  # - fullscreen => hide (unless revealed)
  # - empty => show
  # - only floating (total>0 and tiled==0) => show
  # - else => hide
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