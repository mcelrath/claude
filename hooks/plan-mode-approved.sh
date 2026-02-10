#!/bin/bash
# PostToolUse hook for ExitPlanMode
# When user approves ExitPlanMode, update Mode: PLANNING → Mode: IMPLEMENTATION
# This prevents double-approval after context compact/resume

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

# Find session and plan file
STATE_DIR="/tmp/claude-kb-state"
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

SESSION_DIR="$HOME/.claude/sessions/$SESSION_ID"
[[ ! -f "$SESSION_DIR/current_plan" ]] && exit 0
PLAN_FILE=$(cat "$SESSION_DIR/current_plan")
[[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]] && exit 0

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
