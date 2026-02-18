#!/bin/bash
# PostToolUse hook for ExitPlanMode
# When user approves ExitPlanMode, update Mode: PLANNING → Mode: IMPLEMENTATION

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

# Extract session slug from tool input (used as plan filename)
SLUG=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('slug', ''))
except:
    pass
" 2>/dev/null)

[[ -z "$SLUG" ]] && exit 0

# Plan file is always ~/.claude/plans/{slug}.md
PLAN_FILE="$HOME/.claude/plans/${SLUG}.md"
[[ ! -f "$PLAN_FILE" ]] && exit 0

# Get session info for current_plan pointer
STATE_DIR="/tmp/claude-kb-state"
SESSION_FILE="$STATE_DIR/session-$PPID"
if [[ -f "$SESSION_FILE" ]]; then
    SESSION_ID=$(cat "$SESSION_FILE")
    SESSION_DIR="$HOME/.claude/sessions/$SESSION_ID"
    mkdir -p "$SESSION_DIR"
    echo "$PLAN_FILE" > "$SESSION_DIR/current_plan"

    # Set work context: this session is now implementing this plan
    source "$HOME/.claude/hooks/lib/work_context.sh"
    set_my_plan "$PLAN_FILE"
fi

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
