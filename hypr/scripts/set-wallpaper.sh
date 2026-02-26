#!/usr/bin/env bash
# ---------------------------------------------------------
# swww + matugen + waybar + dock reload + blur generator
# (hyprlock-safe: always ensures blurred_wallpaper.png exists)
# ---------------------------------------------------------

set -Eeuo pipefail

# ----------------------------
# Wayland session env
# ----------------------------
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
    export WAYLAND_DISPLAY="wayland-0"
  else
    sock="$(ls -1 "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -n1 || true)"
    [[ -n "$sock" ]] && export WAYLAND_DISPLAY="$(basename "$sock")"
  fi
fi

# ----------------------------
# Variables
# ----------------------------
WALLPAPERS_DIR="${WALLPAPERS_DIR:-$HOME/.config/hypr/wallpapers}"
DOCK_SCRIPT="${DOCK_SCRIPT:-$HOME/.config/hypr/scripts/start-dock.sh}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache}"
BLUR_OUTPUT="${BLUR_OUTPUT:-$CACHE_DIR/blurred_wallpaper.png}"
BLUR_STAMP="${BLUR_STAMP:-$CACHE_DIR/blurred_wallpaper.stamp}"
RES="${RES:-1920x1080}"  # 1080p

SWWW_TRANSITION="${SWWW_TRANSITION:-none}"
SWWW_DURATION="${SWWW_DURATION:-0}"

have() { command -v "$1" >/dev/null 2>&1; }
log()  { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ----------------------------
# Pick wallpaper (safe with spaces/newlines)
# ----------------------------
pick_random() {
  local dir="${1:-$WALLPAPERS_DIR}"
  [[ -d "$dir" ]] || return 1

  # Prefer shuf -z (null-safe). Fallback to plain shuf if -z unsupported.
  if shuf -z -n 1 </dev/null >/dev/null 2>&1; then
    find "$dir" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
      -print0 | shuf -z -n 1 | tr -d '\0'
  else
    find "$dir" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
      | shuf -n 1
  fi
}

wallpaper="${1:-}"

if [[ -n "$wallpaper" && -d "$wallpaper" ]]; then
  wallpaper="$(pick_random "$wallpaper" || true)"
fi

[[ -z "$wallpaper" ]] && wallpaper="$(pick_random "$WALLPAPERS_DIR" || true)"

[[ -n "${wallpaper:-}" ]] || fail "No wallpaper found (dir: $WALLPAPERS_DIR)"
[[ -f "$wallpaper" ]] || fail "Wallpaper not found: $wallpaper"

log "Wallpaper: $wallpaper"

mkdir -p "$CACHE_DIR"
mkdir -p "$(dirname "$BLUR_OUTPUT")"

# ----------------------------
# Generate blurred wallpaper - only if needed
# ----------------------------
need_blur=0
if [[ ! -f "$BLUR_OUTPUT" || ! -f "$BLUR_STAMP" ]]; then
  need_blur=1
else
  last="$(cat "$BLUR_STAMP" 2>/dev/null || true)"
  [[ "$last" != "$wallpaper" ]] && need_blur=1
  [[ "$wallpaper" -nt "$BLUR_OUTPUT" ]] && need_blur=1
fi

im_cmd=""
have magick  && im_cmd="magick"
have convert && [[ -z "$im_cmd" ]] && im_cmd="convert"

make_fallback() {
  cp -f -- "$wallpaper" "$BLUR_OUTPUT" 2>/dev/null || ln -sf -- "$wallpaper" "$BLUR_OUTPUT"
  printf '%s' "$wallpaper" > "$BLUR_STAMP"
}

if [[ "$need_blur" -eq 1 ]]; then
  if [[ -n "$im_cmd" ]]; then
    log "Generating blur: $BLUR_OUTPUT"
    if "$im_cmd" "$wallpaper" \
        -resize "${RES}^" \
        -gravity center \
        -extent "$RES" \
        -blur 0x20 \
        "$BLUR_OUTPUT" && [[ -s "$BLUR_OUTPUT" ]]; then
      printf '%s' "$wallpaper" > "$BLUR_STAMP"
    else
      log "Note: blur generation failed. Creating non-blurred fallback for hyprlock."
      make_fallback
    fi
  else
    log "Note: ImageMagick not found. Creating non-blurred fallback for hyprlock."
    make_fallback
  fi
else
  log "Blur up-to-date: $BLUR_OUTPUT"
fi

# ----------------------------
# Set wallpaper (instant change)
# ----------------------------
if have swww; then
  if ! swww query >/dev/null 2>&1; then
    pkill -x swww-daemon 2>/dev/null || true
    swww init >/dev/null 2>&1 || true
    sleep 0.25
  fi

  if [[ "$SWWW_DURATION" == "0" || "$SWWW_TRANSITION" == "none" ]]; then
    swww img "$wallpaper" >/dev/null 2>&1 || log "Note: swww img failed"
  else
    swww img "$wallpaper" \
      --transition-type "$SWWW_TRANSITION" \
      --transition-duration "$SWWW_DURATION" \
      >/dev/null 2>&1 || log "Note: swww img failed"
  fi
else
  log "Note: swww not found. Skipping wallpaper set."
fi

# ----------------------------
# Generate theme (matugen)
# ----------------------------
if have matugen; then
  matugen image "$wallpaper" || log "Note: matugen failed (continuing)."
fi

# ----------------------------
# Reload Waybar
# ----------------------------
if have waybar; then
  if pgrep -x waybar >/dev/null 2>&1; then
    pkill -SIGUSR2 waybar 2>/dev/null || true
  else
    waybar >/dev/null 2>&1 &
  fi
fi

# ----------------------------
# Restart Dock (nwg-dock-hyprland)
# ----------------------------
dock_pat='(^|/)(nwg-dock-hyprland)(\s|$)'

dock_was_running=0
if pgrep -f "$dock_pat" >/dev/null 2>&1; then
  dock_was_running=1
  pkill -f "$dock_pat" 2>/dev/null || true
  for _ in {1..20}; do
    pgrep -f "$dock_pat" >/dev/null 2>&1 || break
    sleep 0.05
  done
fi

if [[ "$dock_was_running" -eq 1 && -x "$DOCK_SCRIPT" ]]; then
  "$DOCK_SCRIPT" >/dev/null 2>&1 || true
fi

log "DONE"