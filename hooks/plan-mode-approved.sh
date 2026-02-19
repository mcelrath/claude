#!/bin/bash
# PostToolUse hook for ExitPlanMode
# When user approves ExitPlanMode, update Mode: PLANNING → Mode: IMPLEMENTATION
source "$(dirname "$0")/lib/claude-env.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

# ExitPlanMode has no slug/plan parameters — find the plan via current_plan pointer
# Match plan-write-review.sh session ID lookup: input field first, then PPID fallback
STATE_DIR="/tmp/claude-kb-state"
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
    SESSION_FILE="$STATE_DIR/session-$PPID"
    [[ -f "$SESSION_FILE" ]] && SESSION_ID=$(cat "$SESSION_FILE")
fi
[[ -z "$SESSION_ID" ]] && exit 0

SESSION_DIR="$CLAUDE_DIR/sessions/$SESSION_ID"
CURRENT_PLAN_FILE="$SESSION_DIR/current_plan"
[[ ! -f "$CURRENT_PLAN_FILE" ]] && exit 0

PLAN_FILE=$(cat "$CURRENT_PLAN_FILE")
[[ ! -f "$PLAN_FILE" ]] && exit 0

# Set work context: this session is now implementing this plan
source "$CLAUDE_DIR/hooks/lib/work_context.sh"
set_my_plan "$PLAN_FILE"

# Cross-platform sed -i
sedi() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Update Mode: PLANNING → Mode: IMPLEMENTATION in the plan file
if grep -q 'Mode: PLANNING' "$PLAN_FILE" 2>/dev/null; then
    sedi 's/Mode: PLANNING/Mode: IMPLEMENTATION/' "$PLAN_FILE"
fi

# Update User: PENDING → User: APPROVED
if grep -q 'User: PENDING' "$PLAN_FILE" 2>/dev/null; then
    sedi 's/User: PENDING/User: APPROVED/' "$PLAN_FILE"
fi

exit 0
