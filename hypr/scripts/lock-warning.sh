#!/bin/sh

notify-send \
  --urgency=critical \
  --icon=preferences-desktop-screensaver \
  --expire-time=5000 \
  "Screen will lock soon" \
  "Move mouse or press a key to stay unlocked"
