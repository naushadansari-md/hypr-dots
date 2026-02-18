#!/usr/bin/env bash
set -euo pipefail

MODE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/battery_mode"
mkdir -p "$(dirname "$MODE_FILE")"

MODE="pct"
[[ -f "$MODE_FILE" ]] && MODE="$(cat "$MODE_FILE" 2>/dev/null || echo pct)"

if [[ "$MODE" == "pct" ]]; then
  echo "time" > "$MODE_FILE"
else
  echo "pct" > "$MODE_FILE"
fi

# Refresh the module instantly (signal 9)
pkill -RTMIN+9 waybar || true
