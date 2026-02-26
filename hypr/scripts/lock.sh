#!/usr/bin/env bash
set -Eeuo pipefail

BLUR="$HOME/.cache/blurred_wallpaper.png"
WALL_DIR="$HOME/.config/hypr/wallpapers"
RES="1920x1080"

have() { command -v "$1" >/dev/null 2>&1; }

# If blur missing or empty → create it
if [[ ! -s "$BLUR" ]]; then
    mkdir -p "$(dirname "$BLUR")"

    CURRENT=""

    # Try to get current wallpaper from swww
    if have swww; then
        CURRENT="$(swww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1 || true)"
    fi

    # If that failed → pick random wallpaper
    if [[ -z "$CURRENT" || ! -f "$CURRENT" ]]; then
        CURRENT="$(find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" \) | shuf -n1 || true)"
    fi

    # If ImageMagick exists → generate blur
    if [[ -n "$CURRENT" && -f "$CURRENT" && $(command -v magick) ]]; then
        magick "$CURRENT" \
            -resize "${RES}^" \
            -gravity center \
            -extent "$RES" \
            -blur 0x20 \
            "$BLUR" || cp -f "$CURRENT" "$BLUR"
    else
        # Last fallback → copy wallpaper directly
        [[ -n "$CURRENT" && -f "$CURRENT" ]] && cp -f "$CURRENT" "$BLUR"
    fi
fi

exec hyprlock