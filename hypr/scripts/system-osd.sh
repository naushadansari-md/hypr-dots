#!/bin/bash
set -euo pipefail

volume_step=5
brightness_step=2
max_volume=100
notification_timeout=1000  # ms

# Where we store replace IDs so next notif updates the previous one
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
vol_id_file="$runtime_dir/volume_notify_id"
bri_id_file="$runtime_dir/brightness_notify_id"

need() { command -v "$1" >/dev/null 2>&1; }

for cmd in pulsemixer brightnessctl notify-send awk; do
  if ! need "$cmd"; then
    echo "Missing dependency: $cmd" >&2
    exit 1
  fi
done

clamp_0_100() {
  local v="${1:-0}"
  if   [ "$v" -lt 0 ];   then echo 0
  elif [ "$v" -gt 100 ]; then echo 100
  else echo "$v"
  fi
}

# ------------ swaync-friendly notify (replace instead of spam) ------------

notify_replace() {
  # usage: notify_replace <id_file> <appname> <category> <icon> <value(0-100)> <summary> <body>
  local id_file="$1"; shift
  local appname="$1"; shift
  local category="$1"; shift
  local icon="$1"; shift
  local value="$1"; shift
  local summary="$1"; shift
  local body="$1"; shift

  value="$(clamp_0_100 "$value")"

  local old_id="0"
  if [ -s "$id_file" ]; then
    old_id="$(cat "$id_file" 2>/dev/null || echo 0)"
  fi

  # -p prints new notification id; -r replaces old one if supported
  # -h int:value:<n> is used by many daemons (incl. swaync) for a progress bar/slider style.
  local new_id
  new_id="$(
    notify-send \
      -a "$appname" \
      -c "$category" \
      -i "$icon" \
      -t "$notification_timeout" \
      -h int:value:"$value" \
      -r "$old_id" \
      -p \
      "$summary" \
      "$body" \
    || true
  )"

  # If for any reason we didn't get an ID, don't overwrite the old one.
  if [[ "$new_id" =~ ^[0-9]+$ ]]; then
    printf '%s' "$new_id" > "$id_file"
  fi
}

# ------------------ AUDIO ------------------

get_volume() {
  pulsemixer --get-volume | awk '
    NF==1 {print int($1)}
    NF>=2 {print int(($1+$2)/2)}
  '
}

get_mute() {
  case "$(pulsemixer --get-mute)" in
    1|true|yes|on) echo 1 ;;
    *)             echo 0 ;;
  esac
}

get_volume_icon_glyph() {
  local volume mute
  volume="$(get_volume)"
  mute="$(get_mute)"

  if [ "$mute" -eq 1 ] || [ "$volume" -eq 0 ]; then
    echo "󰕿"
  elif [ "$volume" -lt 50 ]; then
    echo "󰖀"
  else
    echo "󰕾"
  fi
}

get_volume_icon_name() {
  # icon name for notify-send (theme icon)
  local volume mute
  volume="$(get_volume)"
  mute="$(get_mute)"

  if [ "$mute" -eq 1 ] || [ "$volume" -eq 0 ]; then
    echo "audio-volume-muted"
  elif [ "$volume" -lt 50 ]; then
    echo "audio-volume-low"
  else
    echo "audio-volume-high"
  fi
}

show_volume_notif() {
  local volume glyph icon
  volume="$(get_volume)"
  glyph="$(get_volume_icon_glyph)"
  icon="$(get_volume_icon_name)"

  notify_replace \
    "$vol_id_file" \
    "Volume" \
    "device" \
    "$icon" \
    "$volume" \
    "Volume" \
    "$glyph    $volume%"
}

# ------------------ BRIGHTNESS ------------------

get_brightness_percent() {
  local b max
  b="$(brightnessctl get)"
  max="$(brightnessctl max || echo 0)"
  if [ "$max" -le 0 ]; then
    echo 0
  else
    echo $(( b * 100 / max ))
  fi
}

show_brightness_notif() {
  local p
  p="$(get_brightness_percent)"

  notify_replace \
    "$bri_id_file" \
    "Brightness" \
    "device" \
    "display-brightness" \
    "$p" \
    "Brightness" \
    "󰃠    ${p}%"
}

# ------------------ ACTIONS ------------------

case "${1:-}" in
  volume_up)
    pulsemixer --unmute
    pulsemixer --change-volume +"$volume_step" --max-volume "$max_volume"
    show_volume_notif
    ;;

  volume_down)
    pulsemixer --unmute
    pulsemixer --change-volume -"${volume_step}" --max-volume "$max_volume"
    show_volume_notif
    ;;

  volume_mute)
    pulsemixer --toggle-mute
    show_volume_notif
    ;;

  brightness_up)
    brightnessctl set +"${brightness_step}%"
    show_brightness_notif
    ;;

  brightness_down)
    brightnessctl set "${brightness_step}%-"
    show_brightness_notif
    ;;

  *)
    notify-send -a "controls" -t 2000 "Error" \
      "Invalid argument.
Use: volume_up | volume_down | volume_mute | brightness_up | brightness_down"
    exit 1
    ;;
esac