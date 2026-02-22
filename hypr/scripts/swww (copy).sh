#!/usr/bin/env bash
# ---------------------------------------------------------
# swww + matugen + waybar + swaync + rofi wallpaper preview
# ---------------------------------------------------------

set -u
set -o pipefail

# ----------------------------
# Wayland session env (IMPORTANT)
# ----------------------------
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# If WAYLAND_DISPLAY is missing (common when triggered from swaync/waybar/systemd),
# auto-pick one from $XDG_RUNTIME_DIR (wayland-0 / wayland-1)
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  if ls "$XDG_RUNTIME_DIR"/wayland-* >/dev/null 2>&1; then
    WAYLAND_DISPLAY="$(basename "$(ls -1 "$XDG_RUNTIME_DIR"/wayland-* | head -n1)")"
    export WAYLAND_DISPLAY
  fi
fi

# ----------------------------
# Lock (No Overlap)
# ----------------------------
LOCKFILE="${XDG_CACHE_HOME:-$HOME/.cache}/swww-matugen.lock"
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

# ----------------------------
# Helpers
# ----------------------------
have() { command -v "$1" >/dev/null 2>&1; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
need() { have "$1" || fail "Missing dependency: $1"; }

# ----------------------------
# Logging / Cache
# ----------------------------
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE" || exit 1

LOG="$CACHE/swww-matugen.log"
exec > >(tee -a "$LOG") 2>&1

echo "-----------------------------"
echo "Run : $(date)"
echo "User: $(id -un)"
echo "PWD : $(pwd)"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<empty>}"

# ----------------------------
# Requirements (Core tools)
# ----------------------------
need flock
need find
need shuf
need tee

# ----------------------------
# Paths / Variables
# ----------------------------
WALLPAPERS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpapers"

BLURRED="$CACHE/blurred_wallpaper.png"
RASI_FILE="$CACHE/current_wallpaper.rasi"

# Blur strength (ImageMagick). Set "0x0" to disable blur.
BLUR="20x10"

echo "CACHE       = $CACHE"
echo "WALLPAPERS  = $WALLPAPERS_DIR"
echo "RASI_FILE   = $RASI_FILE"
echo "BLURRED_IMG = $BLURRED"

# ----------------------------
# SECTION: Rofi (Placeholder .rasi)
# ----------------------------
cat > "$RASI_FILE" <<EOF
/* ---- Auto-generated wallpaper ---- */
* {
    current-image: none;
}
EOF
echo "OK: placeholder rasi created"

# ----------------------------
# Wallpaper Pick
# ----------------------------
pick_random_wallpaper() {
  [[ -d "$WALLPAPERS_DIR" ]] || return 1
  find "$WALLPAPERS_DIR" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0 | shuf -z -n 1 | tr -d '\0'
}

wallpaper="${1:-}"
if [[ -z "$wallpaper" ]]; then
  wallpaper="$(pick_random_wallpaper || true)"
fi

[[ -n "${wallpaper:-}" ]] || fail "No wallpaper found in: $WALLPAPERS_DIR"
[[ -f "$wallpaper" ]] || fail "Wallpaper not found: $wallpaper"
echo "Wallpaper: $wallpaper"

# ----------------------------
# swww (Set Wallpaper) - robust
# ----------------------------
if have swww; then
  # Start daemon if needed
  if ! swww query >/dev/null 2>&1; then
    pkill -x swww-daemon 2>/dev/null || true
    pkill -x swww 2>/dev/null || true
    swww init >/dev/null 2>&1 || warn "swww init failed"
    sleep 0.25
  fi

  # Set wallpaper; retry once if needed
  if ! swww img "$wallpaper" >/dev/null 2>&1; then
    warn "swww img failed, retrying after daemon restart..."
    pkill -x swww-daemon 2>/dev/null || true
    pkill -x swww 2>/dev/null || true
    swww init >/dev/null 2>&1 || warn "swww init failed"
    sleep 0.25
    swww img "$wallpaper" >/dev/null 2>&1 || warn "swww img failed again"
  fi
else
  warn "swww missing"
fi

# ----------------------------
# matugen (Generate Theme)
# ----------------------------
if have matugen; then
  matugen image "$wallpaper" || warn "matugen failed"
else
  warn "matugen missing"
fi

# ----------------------------
# Waybar (Reload)
# ----------------------------
if have waybar; then
  if have pkill; then
    pkill -SIGUSR2 waybar 2>/dev/null || true
  else
    warn "pkill missing, cannot signal waybar"
  fi
  pgrep -x waybar >/dev/null 2>&1 || waybar >/dev/null 2>&1 &
fi

# ----------------------------
# SwayNC (Ensure running; do NOT restart here)
# ----------------------------
pgrep -x swaync >/dev/null 2>&1 || swaync >/dev/null 2>&1 &

# ----------------------------
# Wallpaper Blur (Rofi Preview Image)
# ----------------------------
tmp_blur="$CACHE/.blur_tmp.png"
rm -f "$BLURRED" "$tmp_blur" 2>/dev/null || true

if have magick; then
  magick "$wallpaper" -resize 75% "$tmp_blur" || warn "magick resize failed"
  if [[ "$BLUR" != "0x0" && -f "$tmp_blur" ]]; then
    magick "$tmp_blur" -blur "$BLUR" "$BLURRED" || warn "magick blur failed"
  else
    mv -f "$tmp_blur" "$BLURRED" || true
  fi
else
  cp -f "$wallpaper" "$BLURRED" || warn "fallback copy failed"
fi

# ----------------------------
# Rofi (.rasi)
# ----------------------------
FINAL_IMAGE="$BLURRED"
if [[ ! -f "$FINAL_IMAGE" ]]; then
  warn "blurred image missing, using original wallpaper"
  FINAL_IMAGE="$wallpaper"
fi

cat > "$RASI_FILE" <<EOF
/* ---- Auto-generated wallpaper ---- */
* {
    current-image: url("$FINAL_IMAGE", height);
}
EOF
echo "OK: wrote final rasi: $RASI_FILE"

echo "DONE"
exit 0