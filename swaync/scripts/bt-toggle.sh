#!/usr/bin/env bash
set -euo pipefail

RFKILL="$(command -v rfkill || true)"
BTCTL="$(command -v bluetoothctl || true)"

log() {
  [[ "${SWAYNC_BT_LOG:-0}" == "1" ]] || return 0
  local LOG="${XDG_RUNTIME_DIR:-/tmp}/swaync-bt.log"
  echo "$(date -Is) $*" >> "$LOG"
}

if [[ -z "${RFKILL}" ]]; then
  echo "rfkill not found" >&2
  exit 1
fi

# Find rfkill id for Bluetooth (matches: "0: hci0: Bluetooth")
BTID="$("$RFKILL" list | awk -F: '/Bluetooth/ {print $1; exit}')"
if [[ -z "${BTID:-}" ]]; then
  echo "No Bluetooth rfkill device found" >&2
  exit 1
fi

# If SwayNC passes desired state, use it. Otherwise (manual run), toggle based on current state.
DESIRED="${SWAYNC_TOGGLE_STATE:-}"
if [[ "$DESIRED" != "true" && "$DESIRED" != "false" ]]; then
  if "$RFKILL" list "$BTID" | grep -q "Soft blocked: no"; then
    DESIRED="false"
  else
    DESIRED="true"
  fi
fi

BEFORE="$("$RFKILL" list "$BTID")"

is_unblocked() { grep -q "Soft blocked: no" <<<"$1"; }

log "toggle desired=$DESIRED bt_id=$BTID before=$(tr '\n' ' ' <<<"$BEFORE")"

if [[ "$DESIRED" == "true" ]]; then
  if is_unblocked "$BEFORE"; then
    log "no-op: already unblocked"
  else
    "$RFKILL" unblock "$BTID"
  fi
  # Optional: also power on (ignore failures)
  if [[ -n "${BTCTL}" ]]; then
    "$BTCTL" power on >/dev/null 2>&1 || true
  fi
else
  if ! is_unblocked "$BEFORE"; then
    log "no-op: already blocked"
  else
    # Optional: power off first (ignore failures)
    if [[ -n "${BTCTL}" ]]; then
      "$BTCTL" power off >/dev/null 2>&1 || true
    fi
    "$RFKILL" block "$BTID"
  fi
fi

AFTER="$("$RFKILL" list "$BTID")"
log "after=$(tr '\n' ' ' <<<"$AFTER")"