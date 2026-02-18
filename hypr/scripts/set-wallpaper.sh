#!/usr/bin/env bash
# ---------------------------------------------------------
# hyprpaper + matugen + waybar + mako + rofi wallpaper preview
# Compatible with your system (NO "hyprctl dispatch"; NO preload needed)
# ---------------------------------------------------------

set -u
set -o pipefail

# ----------------------------
# Lock (No Overlap)
# ----------------------------
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE" || exit 1

LOCKFILE="$CACHE/wallpaper-matugen.lock"
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
# Logging
# ----------------------------
LOG="$CACHE/wallpaper-matugen.log"
exec > >(tee -a "$LOG") 2>&1

echo "-----------------------------"
echo "Run : $(date)"
echo "User: $(id -un)"
echo "PWD : $(pwd)"

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
# hyprpaper (Set Wallpaper) - YOUR BUILD (no dispatch, no preload)
# ----------------------------
if have hyprctl && have hyprpaper; then
  # Ensure hyprpaper is running (recommended also: exec-once = hyprpaper in hyprland.conf)
  pgrep -x hyprpaper >/dev/null 2>&1 || (hyprpaper >/dev/null 2>&1 & disown || true)

  # Outputs may not be ready immediately after login
  sleep 0.5

  # Apply wallpaper to all monitors
  hyprctl hyprpaper wallpaper ",$wallpaper" >/dev/null 2>&1 || warn "hyprpaper wallpaper failed"

  # Optional cleanup
  hyprctl hyprpaper unload unused >/dev/null 2>&1 || true
else
  warn "Missing hyprctl or hyprpaper"
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
# Mako (Reload Notifications)
# ----------------------------
if have makoctl; then
  makoctl reload || true
fi

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
