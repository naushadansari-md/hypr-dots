#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Rofi Network + Power Menu (Nerd Font glyphs)
# - No "Refresh" or "Exit" entries
# - Esc / close rofi exits naturally
# ------------------------------------------------------------

# ---------------- CONFIG ----------------
ROFI="rofi -dmenu -i -markup-rows -p Launcher"
LOW_BATTERY_THRESHOLD=20

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/niri-launcher"
mkdir -p "$CACHE_DIR"

WIFI_CACHE="$CACHE_DIR/wifi-scan"
WIFI_CACHE_TTL=30

# ---------------- NERD FONT GLYPHS ----------------
# (These assume you run rofi with a Nerd Font, e.g. JetBrainsMono Nerd Font)
I_WIFI=""
I_BT=""
I_PLANE=""
I_BOLT=""
I_BAT=""
I_SLEEP=""
I_HEADPHONES=""
I_POWER=""
I_CHECK=""
I_X=""
I_SHUTDOWN="⏻"
I_REBOOT=""
I_LOGOUT="󰍃"
I_MENU=""

# ---------------- GENERIC HELPERS ----------------
is_number() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# ---------------- WIFI ----------------
wifi_state() { nmcli -t -f WIFI g | awk '{print $1}'; }
wifi_device() { nmcli -t -f DEVICE,TYPE d | awk -F: '$2=="wifi"{print $1; exit}'; }
wifi_connected_ssid() { nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1=="yes"{print $2; exit}'; }

wifi_cache_valid() {
  [ -f "$WIFI_CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$WIFI_CACHE") )) -lt "$WIFI_CACHE_TTL" ]
}

wifi_scan_async() {
  local dev
  dev="$(wifi_device)" || return
  (
    nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list ifname "$dev" 2>/dev/null \
      | sed '/::/d' > "${WIFI_CACHE}.tmp" \
      && mv "${WIFI_CACHE}.tmp" "$WIFI_CACHE"
  ) & disown
}

# Wi-Fi menu sorted by signal strength
wifi_menu() {
  local current ssid signal icon
  current="$(wifi_connected_ssid)"
  wifi_scan_async
  [ -f "$WIFI_CACHE" ] || return

  sort -t: -k2 -nr "$WIFI_CACHE" | while IFS=: read -r inuse signal ssid; do
    [[ -z "${ssid:-}" ]] && continue
    ssid="${ssid//\"/}"
    [[ "$ssid" == "$current" ]] && icon="$I_CHECK" || icon="$I_X"
    echo "$icon  $ssid ($signal%)"
  done
}

# ---------------- BLUETOOTH ----------------
bt_state() {
  bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && echo "on" || echo "off"
}

# Bluetooth menu sorted: connected first
bt_menu() {
  mapfile -t devices < <(bluetoothctl devices 2>/dev/null || true)

  local connected=() disconnected=()

  for dev in "${devices[@]}"; do
    local _ mac name status battery line icon label
    read -r _ mac name <<< "$dev"
    [ -z "${mac:-}" ] && continue

    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
      status="connected"
      icon="$I_CHECK"
    else
      status="disconnected"
      icon="$I_X"
    fi

    battery="$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Battery Percentage/ {print $2}' | head -n1)"
    [[ -n "${battery:-}" ]] && battery=" - ${battery}%" || battery=""

    label="$icon  $name$battery"
    line="$status|$mac|$label"

    if [ "$status" = "connected" ]; then
      connected+=("$line")
    else
      disconnected+=("$line")
    fi
  done

  local item
  for item in "${connected[@]}" "${disconnected[@]}"; do
    IFS='|' read -r _ mac label <<< "$item"
    echo "$label|$mac"
  done
}

notify_low_battery() {
  bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
    [ -z "${mac:-}" ] && continue

    local connected battery flag
    connected="$(bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && echo "yes" || echo "no")"
    [ "$connected" != "yes" ] && continue

    battery="$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Battery Percentage/ {print $2}' | head -n1)"
    [ -z "${battery:-}" ] && continue
    is_number "$battery" || continue

    flag="$CACHE_DIR/bt-low-$mac"
    if [ "$battery" -le "$LOW_BATTERY_THRESHOLD" ]; then
      [ -f "$flag" ] && continue
      notify-send -u critical -a "Niri Launcher" "🔋 Bluetooth low battery" "$name: ${battery}%"
      touch "$flag"
    else
      rm -f "$flag"
    fi
  done
}

# ---------------- POWER PROFILE ----------------
power_profile_menu() {
  local current profile icon mark
  if command -v powerprofilesctl >/dev/null 2>&1; then
    current="$(powerprofilesctl get 2>/dev/null || echo unknown)"
  else
    current="unknown"
  fi

  for profile in performance balanced power-saver; do
    case "$profile" in
      performance) icon="$I_BOLT" ;;
      balanced)    icon="$I_BAT" ;;
      power-saver) icon="$I_SLEEP" ;;
    esac
    [ "$profile" = "$current" ] && mark="$I_CHECK" || mark="  "
    echo "$mark  $icon  $profile"
  done
}

# ---------------- AIRPLANE MODE ----------------
toggle_airplane_mode() {
  local wifi bt
  wifi="$(wifi_state)"
  bt="$(bt_state)"

  if [ "$wifi" = "enabled" ] || [ "$bt" = "on" ]; then
    nmcli radio all off
    bluetoothctl power off >/dev/null 2>&1 || true
    notify-send -a "Niri Launcher" "✈ Airplane Mode" "Wireless interfaces disabled"
  else
    nmcli radio all on
    bluetoothctl power on >/dev/null 2>&1 || true
    notify-send -a "Niri Launcher" "✈ Airplane Mode" "Wireless interfaces enabled"
  fi
}

# ---------------- MENUS ----------------
main_menu() {
  local wifi_status bt_status power_profile airplane_status

  wifi_status="$(wifi_state)"
  [[ "$wifi_status" == "enabled" ]] && wifi_status="enabled" || wifi_status="disabled"

  bt_status="$(bt_state)"
  [[ "$bt_status" == "on" ]] && bt_status="on" || bt_status="off"

  if command -v powerprofilesctl >/dev/null 2>&1; then
    power_profile="$(powerprofilesctl get 2>/dev/null || echo unknown)"
  else
    power_profile="unknown"
  fi

  [[ "$wifi_status" == "disabled" && "$bt_status" == "off" ]] && airplane_status="off" || airplane_status="on"

  echo "$I_WIFI  Wi-Fi: $wifi_status"
  echo "$I_BT  Bluetooth: $bt_status"
  echo "$I_PLANE  Airplane Mode: $airplane_status"
  echo "$I_BOLT  Power Profile: $power_profile"
  echo "----"
  echo "$I_WIFI  Wi-Fi Networks"
  echo "$I_HEADPHONES  Bluetooth Devices"
  echo "$I_POWER  Power Options"
}

power_menu() {
  echo "$I_SHUTDOWN  Shutdown"
  echo "$I_REBOOT  Reboot"
  echo "$I_LOGOUT  Logout"
}

# ---------------- MAIN LOOP ----------------
while true; do
  notify_low_battery

  choice="$(main_menu | $ROFI)"
  [ -z "${choice:-}" ] && exit

  case "$choice" in
    "$I_WIFI  Wi-Fi:"*)
      if [ "$(wifi_state)" = "enabled" ]; then
        nmcli radio wifi off
      else
        nmcli radio wifi on
      fi
      ;;

    "$I_BT  Bluetooth:"*)
      if [ "$(bt_state)" = "on" ]; then
        bluetoothctl power off >/dev/null 2>&1 || true
      else
        bluetoothctl power on >/dev/null 2>&1 || true
      fi
      ;;

    "$I_PLANE  Airplane Mode:"*)
      toggle_airplane_mode
      ;;

    "$I_BOLT  Power Profile:"*)
      sel="$(power_profile_menu | $ROFI -p "Power Profile")"
      [ -z "${sel:-}" ] && continue
      # last field is profile name
      prof="${sel##* }"
      if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl set "$prof"
        notify-send -a "Niri Launcher" "Power Profile" "Switched to $prof"
      fi
      ;;

    "$I_WIFI  Wi-Fi Networks")
      [ "$(wifi_state)" != "enabled" ] && nmcli radio wifi on && sleep 1
      sel="$(wifi_menu | rofi -dmenu -i -p "Wi-Fi")"
      [ -z "${sel:-}" ] && continue

      # Extract SSID: remove leading icon + two spaces, then strip trailing " (NN%)"
      ssid="${sel#*  }"
      ssid="${ssid% (*}"

      if ! nmcli device wifi connect "$ssid"; then
        pass="$($ROFI -password -p "Password")"
        [ -n "${pass:-}" ] && nmcli device wifi connect "$ssid" password "$pass"
      fi
      ;;

    "$I_HEADPHONES  Bluetooth Devices")
      [ "$(bt_state)" != "on" ] && bluetoothctl power on >/dev/null 2>&1 || true

      sel="$(bt_menu | rofi -dmenu -i -p "Bluetooth")"
      [ -z "${sel:-}" ] && continue

      IFS='|' read -r _ mac <<< "$sel"
      [ -z "${mac:-}" ] && continue

      if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
      else
        bluetoothctl connect "$mac" >/dev/null 2>&1 || true
      fi
      ;;

    "$I_POWER  Power Options")
      sel="$(power_menu | $ROFI -p "Power")"
      case "$sel" in
        "$I_SHUTDOWN  Shutdown") systemctl poweroff ;;
        "$I_REBOOT  Reboot")     systemctl reboot ;;
        "$I_LOGOUT  Logout")     niri msg exit ;;
      esac
      ;;
  esac
done
