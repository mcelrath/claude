#!/bin/bash
# Utility to set work context for current session
# Usage: set-work-context.sh <work_type> <primary_task> [my_plan]
#
# Work types:
#   implementation - Implementing a specific plan
#   meta          - Fixing systems, debugging workflows (not implementing plans)
#   debugging     - Debugging other sessions or investigating issues
#   research      - Research, exploration, no specific deliverable
source "$(dirname "$0")/lib/claude-env.sh"

WORK_TYPE="${1:-research}"
PRIMARY_TASK="${2:-Unspecified task}"
MY_PLAN="${3:-}"

source "$CLAUDE_DIR/hooks/lib/work_context.sh"

if init_work_context "$WORK_TYPE" "$PRIMARY_TASK" "$MY_PLAN"; then
    echo "Work context set:"
    echo "  Type: $WORK_TYPE"
    echo "  Task: $PRIMARY_TASK"
    [[ -n "$MY_PLAN" ]] && echo "  Plan: $MY_PLAN"
    exit 0
else
    echo "Failed to set work context (no active session?)" >&2
    exit 1
fi
