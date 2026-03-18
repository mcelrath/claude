#!/bin/bash
# Shared library for beads ID utilities
# Source this from hooks that need to detect beads IDs

# Pattern match: beads ID format is {prefix}-{hex}
bd_is_beads_id() {
    local value="${1#beads:}"
    [[ -n "$value" && "$value" =~ ^[a-z]+-[a-z0-9]+$ ]]
}

# Strip "beads:" prefix
bd_strip_prefix() {
    echo "${1#beads:}"
}

# Get plan epic status as string
bd_plan_status() {
    local epic_id="${1#beads:}"
    local status
    status=$(bd show "$epic_id" --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if isinstance(d, list): d = d[0]
    print(d.get('status', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)
    echo "$status"
}
