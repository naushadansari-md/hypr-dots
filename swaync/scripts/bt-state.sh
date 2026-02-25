#!/usr/bin/env bash
set -euo pipefail

RFKILL="$(command -v rfkill || true)"

if [[ -z "${RFKILL}" ]]; then
  echo false
  exit 0
fi

BTID="$("$RFKILL" list | awk -F: '/Bluetooth/ {print $1; exit}')"

if [[ -z "${BTID:-}" ]]; then
  echo false
  exit 0
fi

if "$RFKILL" list "$BTID" | grep -q "Soft blocked: no"; then
  echo true
else
  echo false
fi