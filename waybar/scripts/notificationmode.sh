#!/usr/bin/env bash
set -euo pipefail

MODE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/notification_mode"
mkdir -p "$(dirname "$MODE_FILE")"

ACTION="${1:-status}"

# Icons passed from Waybar config
ICON_NORMAL="${2:-}"
ICON_DND="${3:-}"

# Get current mode from mako
get_mode() {
    makoctl mode 2>/dev/null | awk '{print $1}' || echo "default"
}

set_mode() {
    local new_mode="$1"
    makoctl mode -s "$new_mode" >/dev/null 2>&1 || true
    echo "$new_mode" > "$MODE_FILE"
}

case "$ACTION" in
    toggle)
        CURRENT="$(get_mode)"
        if [[ "$CURRENT" == "do-not-disturb" ]]; then
            set_mode "default"
        else
            set_mode "do-not-disturb"
        fi
        ;;
    icon|status)
        ;;
esac

MODE="$(get_mode)"

# Build output
if [[ "$MODE" == "do-not-disturb" ]]; then
    TEXT="$ICON_DND"
    CLASS="dnd"
    TOOLTIP="Notifications: Do Not Disturb"
else
    TEXT="$ICON_NORMAL"
    CLASS="normal"
    TOOLTIP="Notifications: Enabled"
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
    "$TEXT" "$TOOLTIP" "$CLASS"