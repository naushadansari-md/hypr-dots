#!/usr/bin/env bash
set -euo pipefail

DOCK_MATCH='nwg-dock-hyprland'
START_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"

# ---------- Tuning (macOS feel) ----------
SHOW_DELAY_MS="${SHOW_DELAY_MS:-180}"
REVEAL_HOLD_MS="${REVEAL_HOLD_MS:-1600}"
HIDE_DELAY_MS="${HIDE_DELAY_MS:-700}"
BOTTOM_ZONE_PX="${BOTTOM_ZONE_PX:-32}"

POLL_SEC="${POLL_SEC:-0.25}"            # cursor poll only
WS_REFRESH_MS="${WS_REFRESH_MS:-1200}"  # workspace state safety refresh
MON_REFRESH_MS="${MON_REFRESH_MS:-5000}"
# ----------------------------------------

is_running() { pgrep -f "^${DOCK_MATCH}(\s|$)" >/dev/null 2>&1; }

# nwg-dock-hyprland signals
dock_show() { pkill -RTMIN+2 -f "^${DOCK_MATCH}(\s|$)" 2>/dev/null || true; }
dock_hide() { pkill -RTMIN+3 -f "^${DOCK_MATCH}(\s|$)" 2>/dev/null || true; }

start_resident() { "$START_SCRIPT" >/dev/null 2>&1 || true; }

now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local s="${EPOCHREALTIME/./}"
    echo "${s:0:${#s}-3}"
  else
    date +%s%3N
  fi
}

# ---------- Hyprland event socket ----------
HYPR_SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPR_SIG}/.socket2.sock"

have_events=0
if [[ -n "$HYPR_SIG" && -S "$SOCK" ]] && command -v socat >/dev/null 2>&1; then
  have_events=1
fi

if (( have_events == 1 )); then
  coproc HYPR_EVENTS { socat -u "UNIX-CONNECT:$SOCK" - 2>/dev/null; }
fi

# ---------- State ----------
zone_enter_ms=0
reveal_until_ms=0
hide_deadline_ms=0
last_t=0

mon_x=0 mon_y=0 mon_w=0 mon_h=0
mon_right=0 mon_bottom=0 zone_top=0
next_mon_refresh_ms=0
mon_dirty=1

ws_hasfullscreen=false
ws_windows=0
next_ws_refresh_ms=0
ws_dirty=1

dock_visible=0

# ---------- Functions ----------
refresh_monitors() {
  local monitors_json
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
}

refresh_workspace_state() {
  local wsid workspaces_json

  wsid="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null || echo 0)"
  workspaces_json="$(hyprctl workspaces -j 2>/dev/null || echo '[]')"

  # Reliable fullscreen detection
  ws_hasfullscreen="$(
    hyprctl activewindow -j 2>/dev/null \
      | jq -r '((.fullscreen // false) == true) or ((.fullscreenMode // 0) != 0)' \
      2>/dev/null || echo false
  )"

  # Workspace window count (cheap)
  ws_windows="$(
    jq --argjson wsid "$wsid" -r '(.[] | select(.id == $wsid) | (.windows // 0)) // 0' \
      <<<"$workspaces_json" 2>/dev/null || echo 0
  )"
  ws_windows="${ws_windows:-0}"
}

mark_dirty_from_event() {
  local ev="$1"
  case "$ev" in
    workspace*|activewindow*|activewindowv2*|openwindow*|closewindow*|movewindow*|fullscreen* )
      ws_dirty=1
      ;;
    focusedmon*|monitoradded*|monitorremoved*|monitor* )
      mon_dirty=1
      ws_dirty=1
      ;;
  esac
}

# ---------- Startup ----------
if ! is_running; then
  start_resident
fi

t="$(now_ms)"
next_mon_refresh_ms=$t
next_ws_refresh_ms=$t

# ---------- Main Loop ----------
while true; do
  t="$(now_ms)"
  (( t < last_t )) && t=$last_t
  last_t=$t

  # Event-driven idle
  if (( have_events == 1 )); then
    if IFS= read -r -t "$POLL_SEC" -u "${HYPR_EVENTS[0]}" evline; then
      mark_dirty_from_event "$evline"
      continue
    fi
  else
    sleep "$POLL_SEC"
  fi

  # Ensure dock still running
  if ! is_running; then
    start_resident
    dock_visible=0
  fi

  # Monitor refresh
  if (( mon_dirty == 1 || t >= next_mon_refresh_ms || mon_w <= 0 || mon_h <= 0 )); then
    refresh_monitors
    mon_dirty=0
    next_mon_refresh_ms=$((t + MON_REFRESH_MS))
  fi

  # Cursor poll
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

  # Reveal timing
  if (( zone_hit == 1 )); then
    (( zone_enter_ms == 0 )) && zone_enter_ms=$t
    (( t - zone_enter_ms >= SHOW_DELAY_MS )) && reveal_until_ms=$((t + REVEAL_HOLD_MS))
  else
    zone_enter_ms=0
  fi

  revealed=0
  (( reveal_until_ms > t )) && revealed=1

  # Workspace refresh
  if (( ws_dirty == 1 || t >= next_ws_refresh_ms )); then
    refresh_workspace_state
    ws_dirty=0
    next_ws_refresh_ms=$((t + WS_REFRESH_MS))
  fi

  # ---------- Rules ----------
  if (( revealed == 1 )); then
    desired="show"
  elif [[ "$ws_hasfullscreen" == "true" ]]; then
    desired="hide"
  elif (( ws_windows == 0 )); then
    desired="show"
  else
    desired="hide"
  fi

  # ---------- Apply ----------
  if [[ "$desired" == "show" ]]; then
    hide_deadline_ms=0
    if (( dock_visible == 0 )); then
      dock_show
      dock_visible=1
    fi
  else
    (( hide_deadline_ms == 0 )) && hide_deadline_ms=$((t + HIDE_DELAY_MS))
    if (( t >= hide_deadline_ms )); then
      hide_deadline_ms=0
      if (( dock_visible == 1 )); then
        dock_hide
        dock_visible=0
      fi
    fi
  fi
done        