#!/bin/sh
set -eu

# prevent multiple watcher instances
SCRIPT="$HOME/.config/hypr/scripts/hypridle-power.sh"
if pgrep -f "$SCRIPT" | grep -vq "$$"; then
  exit 0
fi

WARN="$HOME/.config/hypr/scripts/lock-warning.sh"

AC_WARN=595; AC_LOCK=600; AC_OFF=900
BAT_WARN=295; BAT_LOCK=300; BAT_OFF=420

TEMPLATE="$HOME/.config/hypr/hypridle.conf"
ACTIVE="$HOME/.cache/hypridle.conf"

get_ac_online() {
  for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    if [ "$(cat "$d/type")" = "Mains" ] && [ -r "$d/online" ]; then
      cat "$d/online"
      return 0
    fi
  done
  echo 0
}

write_conf() {
  mode="$1"
  if [ "$mode" = "AC" ]; then
    WARN_T="$AC_WARN"; LOCK_T="$AC_LOCK"; OFF_T="$AC_OFF"
  else
    WARN_T="$BAT_WARN"; LOCK_T="$BAT_LOCK"; OFF_T="$BAT_OFF"
  fi

  mkdir -p "$(dirname "$ACTIVE")"

  # escape for sed
  WARN_ESC=$(printf '%s' "$WARN" | sed 's/[\/&]/\\&/g')

  sed \
    -e "s/__WARN_T__/$WARN_T/g" \
    -e "s/__LOCK_T__/$LOCK_T/g" \
    -e "s/__OFF_T__/$OFF_T/g" \
    -e "s/__WARN_CMD__/$WARN_ESC/g" \
    "$TEMPLATE" > "$ACTIVE"
}

start_hypridle() {
  mode="$1"
  write_conf "$mode"
  echo "Starting hypridle mode=$mode using $ACTIVE" >&2
  hypridle -c "$ACTIVE"
}

cleanup() {
  [ -n "${pid:-}" ] || exit 0
  kill -TERM "-$pgid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

run_loop() {
  last=""
  pid=""
  pgid=""

  trap cleanup INT TERM EXIT

  while :; do
    online="$(get_ac_online)"
    mode="BAT"; [ "$online" = "1" ] && mode="AC"

    if [ "$mode" != "$last" ]; then
      last="$mode"

      # stop previous hypridle
      if [ -n "${pid:-}" ]; then
        kill -TERM "-$pgid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi

      # start new hypridle
      start_hypridle "$mode" >/dev/null 2>&1 &
      pid=$!
      pgid="$pid"
    fi

    sleep 2

    # re-check quickly
    online2="$(get_ac_online)"
    mode2="BAT"; [ "$online2" = "1" ] && mode2="AC"
    [ "$mode2" = "$last" ] || last=""
  done
}

run_loop
