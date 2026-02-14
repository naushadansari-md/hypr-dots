#!/usr/bin/env bash

# Ensure elephant is running
if ! pgrep -x "elephant" > /dev/null; then
    echo ":: Elephant is NOT running. Starting... ::" >&2
    elephant &
else
    echo ":: Elephant is running. ::" >&2
fi

# Read walker theme safely
theme_file="$HOME/.config/walker/walker-theme"

if [[ -f "$theme_file" ]]; then
    walker_theme=$(<"$theme_file")
else
    echo ":: Theme file not found. Using default. ::" >&2
    walker_theme="default"
fi

echo ":: Launching walker with theme: $walker_theme ::" >&2

exec walker -t "$walker_theme" "$@"
