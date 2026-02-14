#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   hyprlock.sh [WALLPAPER_PATH] [BLURRED_PATH]
# If BLURRED_PATH exists, hyprlock will use it as background.
# Otherwise it falls back to screenshot background.

WAL_COLORS="$HOME/.cache/wal/colors.sh"
OUT="$HOME/.config/hypr/hyprlock.conf"

WALLPAPER="${1:-}"
BLURRED="${2:-$HOME/.cache/blurred_wallpaper.png}"

if [[ ! -f "$WAL_COLORS" ]]; then
  echo "ERROR: pywal colors not found: $WAL_COLORS"
  exit 1
fi

source "$WAL_COLORS"
mkdir -p "$(dirname "$OUT")"

# "#RRGGBB" -> "r,g,b"
hex2rgb() {
  local hex="${1#\#}"
  [[ "$hex" =~ ^[0-9A-Fa-f]{6}$ ]] || hex="000000"
  local r="${hex:0:2}" g="${hex:2:2}" b="${hex:4:2}"
  printf '%d,%d,%d' "$((16#$r))" "$((16#$g))" "$((16#$b))"
}

BG="$(hex2rgb "${background:-#000000}")"
FG="$(hex2rgb "${foreground:-#ffffff}")"
C1="$(hex2rgb "${color1:-#ff5555}")"
C2="$(hex2rgb "${color2:-#50fa7b}")"
C4="$(hex2rgb "${color4:-#6272a4}")"

# choose background path
BG_PATH="screenshot"
if [[ -n "$BLURRED" && -f "$BLURRED" ]]; then
  BG_PATH="$BLURRED"
fi

cat > "$OUT" <<EOF
general {
  disable_loading_bar = true
  grace = 2
  hide_cursor = true
}

background {
  monitor =
  path = $BG_PATH
  blur_passes = 3
  blur_size = 8
  color = rgba($BG,0.55)
}

label {
  monitor =
  text = cmd[update:1000] date +"%A, %B %d"
  color = rgba($FG,0.90)
  font_size = 22
  font_family = JetBrains Mono
  position = 0, 300
  halign = center
  valign = center

  shadow_passes = 2
  shadow_size = 4
  shadow_color = rgba($BG,0.90)
}

label {
  monitor =
  text = cmd[update:1000] date +"%-I:%M"
  color = rgba($FG,1.0)
  font_size = 95
  font_family = JetBrains Mono ExtraBold
  position = 0, 200
  halign = center
  valign = center

  shadow_passes = 2
  shadow_size = 4
  shadow_color = rgba($BG,0.90)
}

input-field {
  monitor =
  size = 340, 60
  rounding = 16
  outline_thickness = 2

  outer_color = rgba($C4,0.90)
  inner_color = rgba($BG,0.55)

  font_color = rgba($FG,1.0)
  placeholder_text = Enter Password
  hide_input = false

  dots_center = true
  dots_size = 0.25
  dots_spacing = 0.30

  fail_color = rgba($C1,0.98)
  check_color = rgba($C2,0.98)

  position = 0, -40
  halign = center
  valign = center
}
EOF

echo "Wrote: $OUT"
