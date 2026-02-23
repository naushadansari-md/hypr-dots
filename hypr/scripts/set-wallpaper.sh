#!/usr/bin/env bash
# ---------------------------------------------------------
# swww + matugen + waybar + rofi wallpaper preview
# + dock color sync + dock restart (reliable, Arch/Hyprland)
# ---------------------------------------------------------

set -Eeuo pipefail

# ----------------------------
# Wayland session env (IMPORTANT)
# ----------------------------
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Prefer wayland-0 (Hyprland typical). Fallback to first existing socket.
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
    export WAYLAND_DISPLAY="wayland-0"
  else
    sock="$(ls -1 "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -n1 || true)"
    [[ -n "$sock" ]] && export WAYLAND_DISPLAY="$(basename "$sock")"
  fi
fi

# ----------------------------
# Lock (No Overlap)
# ----------------------------
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE" || exit 1

LOCKFILE="$CACHE/swww-matugen.lock"
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
need find
need tee

# shuf + flock are expected on Arch; if missing, warn (don’t hard fail)
have shuf  || warn "shuf missing (coreutils). Random wallpaper may fail."
have flock || warn "flock missing (util-linux). Locking may fail."

# ----------------------------
# Paths / Variables
# ----------------------------
WALLPAPERS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpapers"

BLURRED="$CACHE/blurred_wallpaper.png"
RASI_FILE="$CACHE/current_wallpaper.rasi"
BLUR="20x10"

# Dock paths
DOCK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nwg-dock-hyprland"
DOCK_COLORS="$DOCK_DIR/colors.css"

# Dock restart script (your path)
DOCK_SCRIPT="$HOME/.config/hypr/scripts/start-dock.sh"

echo "CACHE       = $CACHE"
echo "WALLPAPERS  = $WALLPAPERS_DIR"
echo "RASI_FILE   = $RASI_FILE"
echo "BLURRED_IMG = $BLURRED"
echo "DOCK_DIR    = $DOCK_DIR"
echo "DOCK_COLORS = $DOCK_COLORS"
echo "DOCK_SCRIPT = $DOCK_SCRIPT"

# ----------------------------
# Rofi (Placeholder .rasi)
# ----------------------------
cat > "$RASI_FILE" <<'EOF'
/* ---- Auto-generated wallpaper ---- */
* { current-image: none; }
EOF
echo "OK: placeholder rasi created"

# ----------------------------
# Wallpaper Pick
# ----------------------------
pick_random_wallpaper() {
  [[ -d "$WALLPAPERS_DIR" ]] || return 1

  # Prefer GNU shuf -z (Arch). Fallback if -z not supported.
  if have shuf; then
    find "$WALLPAPERS_DIR" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
      -print0 | shuf -z -n 1 | tr -d '\0'
  else
    # fallback: first match
    find "$WALLPAPERS_DIR" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
      | head -n1
  fi
}

wallpaper="${1:-}"
if [[ -z "$wallpaper" ]]; then
  wallpaper="$(pick_random_wallpaper || true)"
fi

[[ -n "${wallpaper:-}" ]] || fail "No wallpaper found in: $WALLPAPERS_DIR"
[[ -f "$wallpaper" ]] || fail "Wallpaper not found: $wallpaper"
echo "Wallpaper: $wallpaper"

# ----------------------------
# swww (Set Wallpaper)
# ----------------------------
if have swww; then
  # Ensure daemon is running
  if ! swww query >/dev/null 2>&1; then
    pkill -x swww-daemon 2>/dev/null || true
    pkill -x swww 2>/dev/null || true
    swww init >/dev/null 2>&1 || warn "swww init failed"
    sleep 0.25
  fi

  # Try set wallpaper
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
# Find matugen colors.css (auto-detect)
# ----------------------------
MATUGEN_COLORS=""

# Common locations first
for p in \
  "$HOME/.config/matugen/colors.css" \
  "$HOME/.cache/matugen/colors.css" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/colors.css" \
  "${XDG_CACHE_HOME:-$HOME/.cache}/matugen/colors.css"
do
  if [[ -f "$p" ]]; then
    MATUGEN_COLORS="$p"
    break
  fi
done

# Fallback: search (limited depth for speed)
if [[ -z "$MATUGEN_COLORS" ]]; then
  MATUGEN_COLORS="$(
    find "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CACHE_HOME:-$HOME/.cache}" \
      -maxdepth 4 -type f -name "colors.css" -path "*matugen*" 2>/dev/null \
      | head -n1 || true
  )"
fi

echo "MATUGEN_COLORS=${MATUGEN_COLORS:-<not found>}"

# ----------------------------
# Sync colors to dock config (RELIABLE)
# ----------------------------
mkdir -p "$DOCK_DIR" || true

if [[ -n "$MATUGEN_COLORS" && -f "$MATUGEN_COLORS" ]]; then
  cp -f "$MATUGEN_COLORS" "$DOCK_COLORS" || warn "Failed to copy matugen colors to dock"
  echo "OK: synced dock colors -> $DOCK_COLORS"
else
  warn "Could not locate matugen colors.css; dock colors won't update"
fi

# ----------------------------
# Dock (Restart via start-dock.sh)
# ----------------------------
if [[ -x "$DOCK_SCRIPT" ]]; then
  # Kill any running instance of this script (path match)
  pkill -f "$DOCK_SCRIPT" 2>/dev/null || true
  sleep 0.1
  nohup "$DOCK_SCRIPT" >/dev/null 2>&1 &
  echo "OK: dock restarted using $DOCK_SCRIPT"
else
  warn "start-dock.sh missing or not executable: $DOCK_SCRIPT"
fi

# ----------------------------
# Waybar (Reload)
# ----------------------------
if have waybar; then
  # Preferred soft reload if supported
  pkill -SIGUSR2 waybar 2>/dev/null || true

  # If not running, start it
  if ! pgrep -x waybar >/dev/null 2>&1; then
    waybar >/dev/null 2>&1 &
    echo "OK: waybar started"
  else
    echo "OK: waybar reload signal sent"
  fi
else
  warn "waybar missing"
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
* { current-image: url("$FINAL_IMAGE", height); }
EOF

echo "OK: wrote final rasi: $RASI_FILE"
echo "DONE"
exit 0