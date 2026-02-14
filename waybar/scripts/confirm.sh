#!/usr/bin/env bash

set -euo pipefail

question="${1:-Are you sure?}"
command="${2:-}"

# Kill existing fuzzel instance silently
pkill -x fuzzel 2>/dev/null || true

confirmation=$(printf "Yes\nNo" | \
    fuzzel --dmenu \
           --placeholder "$question" \
           --lines 2)

if [[ "$confirmation" == "Yes" && -n "$command" ]]; then
    eval "$command"
fi
