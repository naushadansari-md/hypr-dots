#!/usr/bin/env bash
set -euo pipefail

notification_timeout=1000

# Steps
b_step="5%"
v_step="5%"
v_limit="150"   # set 100 for hard cap

# Bar style
bar_width=17
bar_full="━"
bar_empty="─"

# Animation
anim_frames=8
anim_delay="0.02"

state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state_brightness="$state_dir/osdctl_brightness.prev"
state_volume="$state_dir/osdctl_volume.prev"

# -------------------------
# Notify helper
# -------------------------
notify_line() {
  notify-send \
    -e -t "$notification_timeout" \
    -h "string:x-canonical-private-synchronous:$1" \
    -h "int:value:$2" \
    -u low \
    "$3"
}

# -------------------------
# Bar generator
# -------------------------
make_bar() {
  local pct="$1"
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100

  local filled=$(( (pct * bar_width + 50) / 100 ))
  local bar=""
  local i

  for ((i=0; i<filled; i++)); do bar+="$bar_full"; done
  for ((i=filled; i<bar_width; i++)); do bar+="$bar_empty"; done

  echo "$bar"
}

render_osd() {
  # identical styling for brightness & volume
  # $1 icon, $2 pct, $3 suffix
  local icon="$1"
  local pct="$2"
  local suffix="$3"
  local bar
  bar="$(make_bar "$pct")"
  printf "%s  %s  %s" "$icon" "$bar" "$suffix"
}

read_prev() {
  [[ -f "$1" ]] && cat "$1" 2>/dev/null || echo "$2"
}

write_prev() {
  printf "%s" "$2" >"$1" 2>/dev/null || true
}

animate_notify() {
  # $1 sync_key, $2 state_file, $3 icon, $4 target_pct, $5 suffix
  local sync_key="$1"
  local state_file="$2"
  local icon="$3"
  local target="$4"
  local suffix="$5"

  local prev frame i
  prev="$(read_prev "$state_file" "$target")"

  [[ "$prev" =~ ^-?[0-9]+$ ]] || prev="$target"
  [[ "$target" =~ ^-?[0-9]+$ ]] || target="$prev"

  if (( prev == target )); then
    notify_line "$sync_key" "$target" "$(render_osd "$icon" "$target" "$suffix")"
    write_prev "$state_file" "$target"
    return
  fi

  for ((i=1; i<=anim_frames; i++)); do
    frame=$(( prev + ( (target - prev) * i ) / anim_frames ))
    notify_line "$sync_key" "$frame" "$(render_osd "$icon" "$frame" "$suffix")"
    sleep "$anim_delay"
  done

  write_prev "$state_file" "$target"
}

# =========================
# Brightness
# =========================
get_brightness() {
  brightnessctl -m | cut -d, -f4 | tr -d '%'
}

brightness_icon() {
  local cur="$1"
  if   (( cur <= 20 )); then echo "󰃞"
  elif (( cur <= 40 )); then echo "󰃟"
  elif (( cur <= 60 )); then echo "󰃠"
  elif (( cur <= 80 )); then echo "󰃡"
  else                     echo "󰃢"
  fi
}

brightness_notify() {
  local cur icon
  cur="$(get_brightness)"
  icon="$(brightness_icon "$cur")"
  animate_notify "brightness_notif" "$state_brightness" "$icon" "$cur" "${cur}%"
}

brightness_change() {
  brightnessctl set "$1" >/dev/null
  brightness_notify
}

# =====================
# Volume (PulseAudio)
# =====================
get_sink() { pactl get-default-sink; }

get_volume() {
  local sink out nums sum=0 count=0 n
  sink="$(get_sink)"
  out="$(pactl get-sink-volume "$sink")"
  mapfile -t nums < <(grep -oP '\b\d+(?=%)' <<<"$out")

  for n in "${nums[@]}"; do
    sum=$((sum + n))
    count=$((count + 1))
  done

  (( count == 0 )) && { echo 0; return; }
  echo $(( (sum + count/2) / count ))
}

is_muted() {
  local sink
  sink="$(get_sink)"
  pactl get-sink-mute "$sink" | grep -q "yes"
}

volume_icon() {
  local vol="$1" muted="$2"
  if (( muted == 1 || vol == 0 )); then
    echo "󰖁"
  elif (( vol <= 30 )); then
    echo "󰕿"
  elif (( vol <= 70 )); then
    echo "󰖀"
  else
    echo "󰕾"
  fi
}

volume_notify() {
  local vol muted icon target suffix
  vol="$(get_volume)"
  muted=0; is_muted && muted=1

  if (( muted == 1 )); then
    target=0
    suffix="Muted"
  else
    target="$vol"
    suffix="${vol}%"
  fi

  icon="$(volume_icon "$vol" "$muted")"
  animate_notify "volume_notif" "$state_volume" "$icon" "$target" "$suffix"
}

volume_cap() {
  local sink vol
  sink="$(get_sink)"
  vol="$(get_volume)"
  if (( vol > v_limit )); then
    pactl set-sink-volume "$sink" "${v_limit}%"
  fi
}

volume_inc() {
  local sink
  sink="$(get_sink)"
  pactl set-sink-mute "$sink" 0
  pactl set-sink-volume "$sink" "+$v_step"
  volume_cap
  volume_notify
}

volume_dec() {
  local sink
  sink="$(get_sink)"
  pactl set-sink-volume "$sink" "-$v_step"
  volume_notify
}

volume_toggle_mute() {
  local sink
  sink="$(get_sink)"
  pactl set-sink-mute "$sink" toggle
  volume_notify
}

# -------------------------
# Main
# -------------------------
device="${1:-brightness}"
action="${2:---get}"

case "$device" in
  brightness|backlight)
    case "$action" in
      --get)  get_brightness ;;
      --inc)  brightness_change "+$b_step" ;;
      --dec)  brightness_change "${b_step}-" ;;
      *)      get_brightness ;;
    esac
    ;;
  volume|audio)
    case "$action" in
      --get)  get_volume ;;
      --inc)  volume_inc ;;
      --dec)  volume_dec ;;
      --mute) volume_toggle_mute ;;
      *)      get_volume ;;
    esac
    ;;
  *)
    echo "Usage:"
    echo "  $0 brightness --get|--inc|--dec"
    echo "  $0 volume --get|--inc|--dec|--mute"
    exit 2
    ;;
esac