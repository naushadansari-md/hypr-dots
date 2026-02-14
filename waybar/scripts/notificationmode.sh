#!/usr/bin/env bash

action="$1"
icon1="$2"
icon2="$3"

# Get current modes
mode="$(makoctl mode 2>/dev/null)"

if [[ "$mode" == *"do-not-disturb"* ]]; then
    paused="true"
else
    paused="false"
fi

if [ "$paused" = "false" ]; then
    # Notifications ON
    if [ "$action" = "toggle" ]; then
        makoctl mode -s do-not-disturb > /dev/null 2>&1
    fi

    if [ "$action" = "icon" ]; then
        echo "{ \"text\": \"$icon1\", \"class\": \"default\" }"
    fi
else
    # Notifications OFF (DND)
    if [ "$action" = "toggle" ]; then
        makoctl mode -s default > /dev/null 2>&1
    fi

    if [ "$action" = "icon" ]; then
        echo "{ \"text\": \"$icon2\", \"class\": \"dnd\" }"
    fi
fi
