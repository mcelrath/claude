#!/bin/bash
# PostToolUse hook for ExitPlanMode
# When user approves ExitPlanMode, update Mode: PLANNING → Mode: IMPLEMENTATION
source "$(dirname "$0")/lib/claude-env.sh"

LOGFILE="/tmp/claude-kb-state/plan-mode-approved.log"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

mkdir -p "/tmp/claude-kb-state"
echo "$(date '+%H:%M:%S') ExitPlanMode triggered, PPID=$PPID" >> "$LOGFILE"
printf '%s' "$INPUT" | python3 -c "import sys,json; json.dump(json.load(sys.stdin), sys.stdout, indent=2)" >> "$LOGFILE" 2>/dev/null
echo "" >> "$LOGFILE"

# ExitPlanMode has no slug/plan parameters — find the plan via current_plan pointer
# Try two methods: input session_id, then PPID mapping
STATE_DIR="/tmp/claude-kb-state"
PLAN_FILE=""

# Method 1: session_id from input JSON
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
if [[ -n "$SESSION_ID" ]]; then
    CURRENT_PLAN_FILE="$CLAUDE_DIR/sessions/$SESSION_ID/current_plan"
    [[ -f "$CURRENT_PLAN_FILE" ]] && PLAN_FILE=$(cat "$CURRENT_PLAN_FILE")
    echo "  method1 session_id=$SESSION_ID current_plan_file=$CURRENT_PLAN_FILE exists=$(test -f "$CURRENT_PLAN_FILE" && echo yes || echo no) plan=$PLAN_FILE" >> "$LOGFILE"
fi

# Method 2: PPID mapping
if [[ -z "$PLAN_FILE" ]]; then
    SESSION_FILE="$STATE_DIR/session-$PPID"
    echo "  method2 session_file=$SESSION_FILE exists=$(test -f "$SESSION_FILE" && echo yes || echo no)" >> "$LOGFILE"
    if [[ -f "$SESSION_FILE" ]]; then
        SESSION_ID=$(cat "$SESSION_FILE")
        CURRENT_PLAN_FILE="$CLAUDE_DIR/sessions/$SESSION_ID/current_plan"
        [[ -f "$CURRENT_PLAN_FILE" ]] && PLAN_FILE=$(cat "$CURRENT_PLAN_FILE")
        echo "  method2 session_id=$SESSION_ID current_plan=$CURRENT_PLAN_FILE exists=$(test -f "$CURRENT_PLAN_FILE" && echo yes || echo no) plan=$PLAN_FILE" >> "$LOGFILE"
    fi
fi

# List available session-$PID files for debugging
echo "  available session files:" >> "$LOGFILE"
ls -la "$STATE_DIR"/session-* >> "$LOGFILE" 2>/dev/null

if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
    echo "  FAILED: no plan file found" >> "$LOGFILE"
    exit 0
fi

echo "  SUCCESS: updating $PLAN_FILE" >> "$LOGFILE"

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
