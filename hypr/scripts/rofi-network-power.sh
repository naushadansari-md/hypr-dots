#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Rofi Network + Bluetooth + Power Menu (FAST)
# Arch Linux | Hyprland | BlueZ + PipeWire
# ------------------------------------------------------------

ROFI_BASE=(rofi -dmenu -i -markup-rows)
ROFI_PROMPT="System"
LOW_BATTERY_THRESHOLD=20

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/rofi-net-power"
mkdir -p "$CACHE_DIR"

# Wi-Fi caches
WIFI_CACHE="$CACHE_DIR/wifi-scan"
WIFI_CACHE_TTL=12
WIFI_SSID_CACHE="$CACHE_DIR/wifi-ssid.cache"
WIFI_SSID_TTL=3

# Bluetooth caches
BT_DISCOVERY_SECONDS=8
BT_CACHE="$CACHE_DIR/bt-devices.cache"
BT_CACHE_TTL=6

BT_SUMMARY_CACHE="$CACHE_DIR/bt-summary.cache"
BT_SUMMARY_TTL=3

BT_STATE_CACHE="$CACHE_DIR/bt-state.cache"
BT_STATE_TTL=3

# Low battery background loop
BT_LOW_CHECK_STAMP="$CACHE_DIR/bt-low-check.stamp"
BT_LOW_CHECK_TTL=120
BT_LOW_BG_INTERVAL=30
BT_LOW_BG_PID="$CACHE_DIR/bt-low-bg.pid"

# Icons
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
I_TRASH=""
I_SEARCH=""

SEP="────────────"

have() { command -v "$1" >/dev/null 2>&1; }
is_number() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
now_s() { date +%s; }
mtime_s() { stat -c %Y "$1" 2>/dev/null || echo 0; }

rofi_menu() { # stdin -> selection
  "${ROFI_BASE[@]}" -p "${1:-$ROFI_PROMPT}"
}
rofi_menu_pw() { # prompts for password
  "${ROFI_BASE[@]}" -password -p "${1:-Password}"
}

notify() {
  local title="${1:-}" body="${2:-}" urg="${3:-normal}"
  have notify-send || return 0
  notify-send -u "$urg" -a "Hypr Launcher" "$title" "$body" >/dev/null 2>&1 || true
}

# ---------------- WIFI ----------------
wifi_state() { nmcli -t -f WIFI g 2>/dev/null | awk '{print $1}'; }
wifi_device() { nmcli -t -f DEVICE,TYPE d 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'; }
wifi_connected_ssid_raw() { nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'; }

wifi_connected_ssid_cached() {
  local t_now t_mtime age
  t_now="$(now_s)"; t_mtime="$(mtime_s "$WIFI_SSID_CACHE")"; age=$((t_now - t_mtime))
  if [ -f "$WIFI_SSID_CACHE" ] && [ "$age" -le "$WIFI_SSID_TTL" ]; then
    cat "$WIFI_SSID_CACHE"; return 0
  fi
  local ssid
  ssid="$(wifi_connected_ssid_raw 2>/dev/null || true)"
  printf '%s' "${ssid:-}" > "${WIFI_SSID_CACHE}.tmp" 2>/dev/null || true
  mv "${WIFI_SSID_CACHE}.tmp" "$WIFI_SSID_CACHE" 2>/dev/null || true
  printf '%s' "${ssid:-}"
}

wifi_scan_async() {
  local dev
  dev="$(wifi_device 2>/dev/null || true)"
  [ -z "${dev:-}" ] && return 0
  (
    nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list ifname "$dev" 2>/dev/null \
      | sed '/::/d' > "${WIFI_CACHE}.tmp" \
      && mv "${WIFI_CACHE}.tmp" "$WIFI_CACHE"
  ) & disown
}

wifi_scan_if_needed() {
  local t_now t_mtime age
  t_now="$(now_s)"; t_mtime="$(mtime_s "$WIFI_CACHE")"; age=$((t_now - t_mtime))
  if [ ! -f "$WIFI_CACHE" ] || [ "$age" -gt "$WIFI_CACHE_TTL" ]; then
    wifi_scan_async
  fi
}

wifi_menu() {
  local current ssid signal icon
  current="$(wifi_connected_ssid_cached 2>/dev/null || true)"
  [ -f "$WIFI_CACHE" ] || return 0
  sort -t: -k2 -nr "$WIFI_CACHE" | while IFS=: read -r _inuse signal ssid; do
    [[ -z "${ssid:-}" ]] && continue
    ssid="${ssid//\"/}"
    [[ "$ssid" == "$current" ]] && icon="$I_CHECK" || icon="$I_X"
    echo "$icon  $ssid ($signal%)"
  done
}

wifi_parse_selection_to_ssid() {
  # Input like: "  MyWiFi (72%)" -> "MyWiFi"
  local sel="${1:-}"
  sel="${sel#*  }"       # remove icon + two spaces
  sel="${sel% (*}"       # remove " (xx%)"
  printf '%s' "$sel"
}

# ---------------- BLUETOOTH (DBus + btmgmt) ----------------
bt_hci_name() { ls -1 /sys/class/bluetooth 2>/dev/null | awk '/^hci[0-9]+$/ {print; exit}'; }
bt_hci_path() { local hci; hci="$(bt_hci_name 2>/dev/null || true)"; [ -n "${hci:-}" ] && echo "/org/bluez/${hci}"; }

bt_ensure_ready() {
  if have systemctl && ! systemctl is-active --quiet bluetooth.service 2>/dev/null; then
    sudo -n systemctl start bluetooth.service >/dev/null 2>&1 \
      || systemctl start bluetooth.service >/dev/null 2>&1 || true
  fi
  if have rfkill; then
    rfkill unblock bluetooth >/dev/null 2>&1 \
      || sudo -n rfkill unblock bluetooth >/dev/null 2>&1 || true
  fi
}

bt_busctl_get_bool() { busctl get-property org.bluez "$1" "$2" "$3" 2>/dev/null | awk '{print $2}'; }
bt_busctl_get_str()  { busctl get-property org.bluez "$1" "$2" "$3" 2>/dev/null | awk -F'"' '{print $2}'; }
bt_busctl_get_byte() { busctl get-property org.bluez "$1" "$2" "$3" 2>/dev/null | awk '{print $2}'; }

bt_state_real() {
  have busctl || { echo "off"; return; }
  local path powered
  path="$(bt_hci_path 2>/dev/null || true)"
  [ -z "${path:-}" ] && { echo "off"; return; }
  powered="$(bt_busctl_get_bool "$path" org.bluez.Adapter1 Powered || true)"
  [ "$powered" = "true" ] && echo "on" || echo "off"
}

bt_state_cache_set() { printf '%s' "$1" > "$BT_STATE_CACHE" 2>/dev/null || true; }

bt_state_cached() {
  local t_now t_mtime age
  t_now="$(now_s)"; t_mtime="$(mtime_s "$BT_STATE_CACHE")"; age=$((t_now - t_mtime))
  if [ -f "$BT_STATE_CACHE" ] && [ "$age" -le "$BT_STATE_TTL" ]; then
    cat "$BT_STATE_CACHE"; return 0
  fi
  [ -f "$BT_STATE_CACHE" ] && cat "$BT_STATE_CACHE" || echo "off"
}

bt_summary_set() { printf '%s' "$1" > "$BT_SUMMARY_CACHE" 2>/dev/null || true; }

bt_power_on() {
  bt_ensure_ready || true
  have busctl || { bt_state_cache_set "on"; bt_summary_set "on"; return 1; }
  local path; path="$(bt_hci_path 2>/dev/null || true)"
  [ -z "${path:-}" ] && { bt_state_cache_set "on"; bt_summary_set "on"; return 1; }
  busctl set-property org.bluez "$path" org.bluez.Adapter1 Powered b true >/dev/null 2>&1 || true
  busctl set-property org.bluez "$path" org.bluez.Adapter1 Pairable b true >/dev/null 2>&1 || true
  bt_state_cache_set "on"
  bt_summary_set "on"
  rm -f "$BT_CACHE" >/dev/null 2>&1 || true
}

bt_power_off() {
  have busctl || { bt_state_cache_set "off"; bt_summary_set "off"; return 0; }
  local path; path="$(bt_hci_path 2>/dev/null || true)"
  [ -z "${path:-}" ] && { bt_state_cache_set "off"; bt_summary_set "off"; return 0; }
  busctl set-property org.bluez "$path" org.bluez.Adapter1 Powered b false >/dev/null 2>&1 || true
  bt_state_cache_set "off"
  bt_summary_set "off"
  rm -f "$BT_CACHE" >/dev/null 2>&1 || true
}

bt_mac_from_path() { echo "${1##*/dev_}" | tr '_' ':'; }
bt_dev_path_from_mac() { local base; base="$(bt_hci_path)" || return 1; echo "$base/dev_${1//:/_}"; }

bt_devices_busctl_paths() {
  have busctl || return 1
  local base; base="$(bt_hci_path)" || return 1
  busctl tree org.bluez 2>/dev/null | awk -v base="$base" '$2 ~ "^"base"/dev_[^/]+$" {print $2}'
}

bt_cache_refresh_if_needed() {
  have busctl || return 0
  local t_now t_mtime age
  t_now="$(now_s)"; t_mtime="$(mtime_s "$BT_CACHE")"; age=$((t_now - t_mtime))
  if [ -f "$BT_CACHE" ] && [ "$age" -le "$BT_CACHE_TTL" ]; then return 0; fi

  : > "${BT_CACHE}.tmp" || true
  while read -r p; do
    [ -z "${p:-}" ] && continue
    local mac name conn batt
    mac="$(bt_mac_from_path "$p")"
    name="$(bt_busctl_get_str "$p" org.bluez.Device1 Name || true)"; [ -z "${name:-}" ] && name="$mac"
    conn="$(bt_busctl_get_bool "$p" org.bluez.Device1 Connected || echo false)"
    batt="$(bt_busctl_get_byte "$p" org.bluez.Battery1 Percentage || true)"; is_number "$batt" || batt=""
    echo "$mac|$name|$conn|$batt" >> "${BT_CACHE}.tmp"
  done < <(bt_devices_busctl_paths 2>/dev/null || true)
  mv "${BT_CACHE}.tmp" "$BT_CACHE" 2>/dev/null || true
}

bt_cache_iter() { bt_cache_refresh_if_needed; [ -f "$BT_CACHE" ] && cat "$BT_CACHE" || true; }

bt_connected_summary_build_from_cachefile() {
  [ -f "$BT_CACHE" ] || { echo "on"; return 0; }

  local count=0 first_name="" first_batt=""
  while IFS='|' read -r _mac name conn batt; do
    [ "$conn" = "true" ] || continue
    if [ "$count" -eq 0 ]; then first_name="$name"; first_batt="$batt"; fi
    count=$((count+1))
  done < "$BT_CACHE"

  if [ "$count" -eq 0 ]; then
    echo "on"
  elif [ "$count" -eq 1 ]; then
    [ -n "${first_batt:-}" ] && echo "$first_name (${first_batt}%)" || echo "$first_name"
  else
    echo "$first_name (+$((count-1)))"
  fi
}

bt_summary_cached() {
  local t_now t_mtime age
  t_now="$(now_s)"; t_mtime="$(mtime_s "$BT_SUMMARY_CACHE")"; age=$((t_now - t_mtime))
  if [ -f "$BT_SUMMARY_CACHE" ] && [ "$age" -le "$BT_SUMMARY_TTL" ]; then
    cat "$BT_SUMMARY_CACHE"; return 0
  fi

  local st; st="$(bt_state_cached)"
  [ "$st" = "on" ] && echo "on" || echo "off"
}

bt_summary_update_now() {
  local st out
  st="$(bt_state_real 2>/dev/null || echo off)"
  bt_state_cache_set "$st"
  if [ "$st" != "on" ]; then
    bt_summary_set "off"; return 0
  fi
  out="$(bt_connected_summary_build_from_cachefile)"
  bt_summary_set "$out"
}

bt_menu_busctl() {
  local connected=() disconnected=()
  while IFS='|' read -r mac name conn batt; do
    [ -z "${mac:-}" ] && continue
    local icon battery
    [ "$conn" = "true" ] && icon="$I_CHECK" || icon="$I_X"
    [ -n "${batt:-}" ] && battery=" - ${batt}%" || battery=""
    if [ "$conn" = "true" ]; then
      connected+=("$icon  $name$battery|$mac")
    else
      disconnected+=("$icon  $name$battery|$mac")
    fi
  done < <(bt_cache_iter)
  printf '%s\n' "${connected[@]}" "${disconnected[@]}"
}

bt_scan_btmgmt() {
  have btmgmt || return 0
  local hci idx; hci="$(bt_hci_name 2>/dev/null || true)"; [ -z "${hci:-}" ] && return 0
  idx="${hci#hci}"
  timeout "$BT_DISCOVERY_SECONDS" btmgmt --index "$idx" find >/dev/null 2>&1 \
    || timeout "$BT_DISCOVERY_SECONDS" sudo -n btmgmt --index "$idx" find >/dev/null 2>&1 \
    || true
  rm -f "$BT_CACHE" >/dev/null 2>&1 || true
}

bt_pair_trust_connect_busctl() {
  have busctl || return 1
  local p; p="$(bt_dev_path_from_mac "$1")" || return 1
  busctl call org.bluez "$p" org.bluez.Device1 Pair >/dev/null 2>&1 || true
  busctl set-property org.bluez "$p" org.bluez.Device1 Trusted b true >/dev/null 2>&1 || true
  busctl call org.bluez "$p" org.bluez.Device1 Connect >/dev/null 2>&1 || true
  rm -f "$BT_CACHE" >/dev/null 2>&1 || true
}

bt_disconnect_busctl() {
  have busctl || return 1
  local p; p="$(bt_dev_path_from_mac "$1")" || return 1
  busctl call org.bluez "$p" org.bluez.Device1 Disconnect >/dev/null 2>&1 || true
  rm -f "$BT_CACHE" >/dev/null 2>&1 || true
}

bt_remove_device_busctl() {
  have busctl || return 1
  local mac="$1" adapter devpath name
  adapter="$(bt_hci_path 2>/dev/null || true)"; [ -z "${adapter:-}" ] && return 1
  devpath="$(bt_dev_path_from_mac "$mac" 2>/dev/null || true)"; [ -z "${devpath:-}" ] && return 1
  name="$(bt_busctl_get_str "$devpath" org.bluez.Device1 Name || true)"; [ -z "${name:-}" ] && name="$mac"
  bt_disconnect_busctl "$mac" >/dev/null 2>&1 || true
  busctl call org.bluez "$adapter" org.bluez.Adapter1 RemoveDevice o "$devpath" >/dev/null 2>&1 || true
  rm -f "$BT_CACHE" >/dev/null 2>&1 || true
  notify "Bluetooth" "Removed: $name"
}

set_bt_sink_default_best_effort() {
  have wpctl || return 0
  local id
  id="$(wpctl status 2>/dev/null | awk '/bluez_output/ {print $1}' | tr -d '.' | head -n1)"
  [ -n "${id:-}" ] && wpctl set-default "$id" >/dev/null 2>&1 || true
}

notify_low_battery_throttled() {
  [ "$(bt_state_cached 2>/dev/null || echo off)" = "on" ] || return 0

  local t_now t_prev age
  t_now="$(now_s)"; t_prev="$(mtime_s "$BT_LOW_CHECK_STAMP")"; age=$((t_now - t_prev))
  [ "$age" -lt "$BT_LOW_CHECK_TTL" ] && return 0
  : > "$BT_LOW_CHECK_STAMP" || true

  bt_cache_refresh_if_needed

  while IFS='|' read -r mac name conn batt; do
    [ "$conn" = "true" ] || continue
    is_number "$batt" || continue
    local flag="$CACHE_DIR/bt-low-$mac"
    if [ "$batt" -le "$LOW_BATTERY_THRESHOLD" ]; then
      [ -f "$flag" ] && continue
      notify "🔋 Bluetooth low battery" "$name: ${batt}%" "critical"
      touch "$flag"
    else
      rm -f "$flag" >/dev/null 2>&1 || true
    fi
  done < <(bt_cache_iter)
}

start_low_battery_bg() {
  if [ -f "$BT_LOW_BG_PID" ] && kill -0 "$(cat "$BT_LOW_BG_PID" 2>/dev/null)" 2>/dev/null; then
    return 0
  fi
  # clean stale pid
  rm -f "$BT_LOW_BG_PID" 2>/dev/null || true

  (
    while true; do
      notify_low_battery_throttled || true
      sleep "$BT_LOW_BG_INTERVAL"
    done
  ) & disown

  echo $! > "$BT_LOW_BG_PID" 2>/dev/null || true
}

# ---------------- POWER PROFILE ----------------
power_profile_menu() {
  local current profile icon mark
  if have powerprofilesctl; then current="$(powerprofilesctl get 2>/dev/null || echo unknown)"; else current="unknown"; fi
  for profile in performance balanced power-saver; do
    case "$profile" in
      performance) icon="$I_BOLT" ;;
      balanced) icon="$I_BAT" ;;
      power-saver) icon="$I_SLEEP" ;;
    esac
    [ "$profile" = "$current" ] && mark="$I_CHECK" || mark="  "
    echo "$mark  $icon  $profile"
  done
}

# ---------------- AIRPLANE MODE ----------------
airplane_state() {
  local wifi bt
  wifi="$(wifi_state 2>/dev/null || echo disabled)"
  bt="$(bt_state_cached 2>/dev/null || echo off)"
  if [ "$wifi" != "enabled" ] && [ "$bt" != "on" ]; then echo "on"; else echo "off"; fi
}

toggle_airplane_mode() {
  if [ "$(airplane_state)" = "off" ]; then
    nmcli radio all off >/dev/null 2>&1 || true
    bt_power_off || true
    notify "✈ Airplane Mode" "Enabled"
  else
    nmcli radio all on >/dev/null 2>&1 || true
    bt_power_on || true
    notify "✈ Airplane Mode" "Disabled"
  fi
}

# ---------------- MENUS ----------------
main_menu() {
  local wifi_status bt_status power_profile airplane_status ssid

  wifi_status="$(wifi_state 2>/dev/null || echo disabled)"
  ssid="$(wifi_connected_ssid_cached 2>/dev/null || true)"
  if [ "$wifi_status" = "enabled" ] && [ -n "${ssid:-}" ]; then
    wifi_status="enabled ($ssid)"
  elif [ "$wifi_status" = "enabled" ]; then
    wifi_status="enabled"
  else
    wifi_status="disabled"
  fi

  bt_status="$(bt_summary_cached)"
  airplane_status="$(airplane_state)"
  if have powerprofilesctl; then power_profile="$(powerprofilesctl get 2>/dev/null || echo unknown)"; else power_profile="unknown"; fi

  echo "$I_WIFI  Wi-Fi: $wifi_status"
  echo "$I_BT  Bluetooth: $bt_status"
  echo "$I_PLANE  Airplane Mode: $airplane_status"
  echo "$I_BOLT  Power Profile: $power_profile"
  echo "$SEP"
  echo "$I_WIFI  Wi-Fi Networks"
  echo "$I_HEADPHONES  Bluetooth Devices"
  echo "$I_POWER  Power Options"
}

power_menu() {
  echo "$I_SHUTDOWN  Shutdown"
  echo "$I_REBOOT  Reboot"
  echo "$I_LOGOUT  Logout"
}

bt_action_menu() {
  local is_conn="${1:-false}"
  echo "$I_SEARCH  Scan for devices"
  if [ "$is_conn" = "true" ]; then echo "$I_X  Disconnect"; else echo "$I_CHECK  Connect"; fi
  echo "$I_TRASH  Remove device"
}

# ---------------- START BG TASK ----------------
start_low_battery_bg

# ---------------- MAIN LOOP ----------------
while true; do
  choice="$(main_menu | rofi_menu "$ROFI_PROMPT")"
  [ -z "${choice:-}" ] && exit 0

  case "$choice" in
    "$I_WIFI  Wi-Fi:"*)
      if [ "$(wifi_state 2>/dev/null || echo disabled)" = "enabled" ]; then
        nmcli radio wifi off >/dev/null 2>&1 || true
      else
        nmcli radio wifi on >/dev/null 2>&1 || true
      fi
      rm -f "$WIFI_SSID_CACHE" >/dev/null 2>&1 || true
      ;;

    "$I_BT  Bluetooth:"*)
      if [ "$(bt_state_cached 2>/dev/null || echo off)" = "on" ]; then
        bt_power_off || true
      else
        bt_power_on || true
      fi
      # ensure main menu immediately reflects change
      bt_summary_set "$(bt_state_cached)"
      ;;

    "$I_PLANE  Airplane Mode:"*)
      toggle_airplane_mode
      rm -f "$WIFI_SSID_CACHE" >/dev/null 2>&1 || true
      ;;

    "$I_BOLT  Power Profile:"*)
      sel="$(power_profile_menu | rofi_menu "Power Profile")"
      [ -z "${sel:-}" ] && continue
      prof="${sel##* }"
      have powerprofilesctl && powerprofilesctl set "$prof" >/dev/null 2>&1 || true
      ;;

    "$I_WIFI  Wi-Fi Networks")
      [ "$(wifi_state 2>/dev/null || echo disabled)" != "enabled" ] && nmcli radio wifi on >/dev/null 2>&1 || true

      wifi_scan_if_needed
      sel="$(wifi_menu | rofi_menu "Wi-Fi")"
      [ -z "${sel:-}" ] && continue

      ssid="$(wifi_parse_selection_to_ssid "$sel")"
      if ! nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
        pass="$(rofi_menu_pw "Password")"
        [ -n "${pass:-}" ] && nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1 || true
      fi
      rm -f "$WIFI_SSID_CACHE" >/dev/null 2>&1 || true
      ;;

    "$I_HEADPHONES  Bluetooth Devices")
      bt_power_on || true

      bt_cache_refresh_if_needed
      bt_summary_update_now

      sel="$(bt_menu_busctl | rofi_menu "Bluetooth")"
      [ -z "${sel:-}" ] && continue

      IFS='|' read -r _label mac <<< "$sel"
      [ -z "${mac:-}" ] && continue

      is_conn="false"
      while IFS='|' read -r c_mac _name c_conn _batt; do
        [ "$c_mac" = "$mac" ] || continue
        [ "$c_conn" = "true" ] && is_conn="true" || is_conn="false"
        break
      done < <(bt_cache_iter)

      action="$(bt_action_menu "$is_conn" | rofi_menu "BT Action")"
      [ -z "${action:-}" ] && continue

      case "$action" in
        "$I_SEARCH  Scan for devices")
          bt_scan_btmgmt
          bt_cache_refresh_if_needed
          bt_summary_update_now
          ;;
        "$I_CHECK  Connect")
          bt_pair_trust_connect_busctl "$mac" >/dev/null 2>&1 || true
          set_bt_sink_default_best_effort
          bt_cache_refresh_if_needed
          bt_summary_update_now
          ;;
        "$I_X  Disconnect")
          bt_disconnect_busctl "$mac" >/dev/null 2>&1 || true
          bt_cache_refresh_if_needed
          bt_summary_update_now
          ;;
        "$I_TRASH  Remove device")
          bt_remove_device_busctl "$mac" || true
          bt_cache_refresh_if_needed
          bt_summary_update_now
          ;;
      esac
      ;;

    "$I_POWER  Power Options")
      sel="$(power_menu | rofi_menu "Power")"
      case "$sel" in
        "$I_SHUTDOWN  Shutdown") systemctl poweroff ;;
        "$I_REBOOT  Reboot") systemctl reboot ;;
        "$I_LOGOUT  Logout") hyprctl dispatch exit ;;
      esac
      ;;
  esac
done
