#!/bin/bash
set -euo pipefail

volume_step=5
brightness_step=2
max_volume=100
notification_timeout=1000

# ------------------ AUDIO ------------------

get_volume() {
    # Average L/R channels for accuracy
    pulsemixer --get-volume | awk '{print int(($1+$2)/2)}'
}

get_mute() {
    pulsemixer --get-mute
}

get_volume_icon() {
    local volume mute
    volume=$(get_volume)
    mute=$(get_mute)

    if [ "$mute" -eq 1 ] || [ "$volume" -eq 0 ]; then
        echo "󰕿"   # Muted
    elif [ "$volume" -lt 50 ]; then
        echo "󰖀"   # Low
    else
        echo "󰕾"   # High
    fi
}

show_volume_notif() {
    local volume icon
    volume=$(get_volume)
    icon=$(get_volume_icon)

    notify-send \
        -t "$notification_timeout" \
        -h string:x-dunst-stack-tag:volume_notif \
        -h int:value:"$volume" \
        "$icon    $volume%"
}

# ------------------ BRIGHTNESS ------------------

get_brightness_raw() {
    brightnessctl get
}

get_brightness_icon() {
    echo "󰃠"
}

show_brightness_notif() {
    local brightness max_brightness percentage icon

    brightness=$(get_brightness_raw)
    max_brightness=$(brightnessctl max)
    percentage=$(( brightness * 100 / max_brightness ))
    icon=$(get_brightness_icon)

    notify-send \
        -t "$notification_timeout" \
        -h string:x-dunst-stack-tag:brightness_notif \
        -h int:value:"$percentage" \
        "$icon    $percentage%"
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
        notify-send "Error" \
            "Invalid argument.
Use: volume_up | volume_down | volume_mute | brightness_up | brightness_down"
        exit 1
        ;;
esac
