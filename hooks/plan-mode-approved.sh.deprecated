#!/bin/bash
# PostToolUse hook for ExitPlanMode
# When user approves ExitPlanMode, close beads epic or update Mode in plan file
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/beads-plan.sh"

LOGFILE="/tmp/claude-kb-state/plan-mode-approved.log"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

mkdir -p "/tmp/claude-kb-state"
echo "$(date '+%H:%M:%S') ExitPlanMode triggered, PPID=$PPID" >> "$LOGFILE"

# Find plan via current_plan pointer
STATE_DIR="/tmp/claude-kb-state"
PLAN_VALUE=""

SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
if [[ -n "$SESSION_ID" ]]; then
    CURRENT_PLAN_FILE="$CLAUDE_DIR/sessions/$SESSION_ID/current_plan"
    [[ -f "$CURRENT_PLAN_FILE" ]] && PLAN_VALUE=$(cat "$CURRENT_PLAN_FILE")
    echo "  method1 session_id=$SESSION_ID plan=$PLAN_VALUE" >> "$LOGFILE"
fi

if [[ -z "$PLAN_VALUE" ]]; then
    SESSION_FILE="$STATE_DIR/session-$PPID"
    if [[ -f "$SESSION_FILE" ]]; then
        SESSION_ID=$(cat "$SESSION_FILE")
        CURRENT_PLAN_FILE="$CLAUDE_DIR/sessions/$SESSION_ID/current_plan"
        [[ -f "$CURRENT_PLAN_FILE" ]] && PLAN_VALUE=$(cat "$CURRENT_PLAN_FILE")
        echo "  method2 session_id=$SESSION_ID plan=$PLAN_VALUE" >> "$LOGFILE"
    fi
fi

[[ -z "$PLAN_VALUE" ]] && echo "  FAILED: no plan found" >> "$LOGFILE" && exit 0

# === BEADS PATH ===
if bd_is_beads_id "$PLAN_VALUE"; then
    EPIC_ID=$(bd_strip_prefix "$PLAN_VALUE")
    echo "  BEADS: closing epic $EPIC_ID" >> "$LOGFILE"

    # Archive final plan text as comment (from legacy file if available)
    SESSION_DIR="$CLAUDE_DIR/sessions/$SESSION_ID"
    LEGACY_PLAN=""
    [[ -f "$SESSION_DIR/current_plan.legacy" ]] && LEGACY_PLAN=$(cat "$SESSION_DIR/current_plan.legacy")
    if [[ -n "$LEGACY_PLAN" && -f "$LEGACY_PLAN" ]]; then
        bd comments add "$EPIC_ID" -f "$LEGACY_PLAN" 2>/dev/null
    fi

    bd_plan_close "$EPIC_ID"
    echo "  SUCCESS: epic $EPIC_ID closed" >> "$LOGFILE"

    # Still set work context for resume compatibility (Phase 4 removes this)
    source "$CLAUDE_DIR/hooks/lib/work_context.sh"
    set_my_plan "beads:$EPIC_ID"
    exit 0
fi

# === LEGACY FILE PATH ===
PLAN_FILE="$PLAN_VALUE"
[[ ! -f "$PLAN_FILE" ]] && echo "  FAILED: plan file not found: $PLAN_FILE" >> "$LOGFILE" && exit 0

echo "  SUCCESS: updating $PLAN_FILE" >> "$LOGFILE"

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

if grep -q 'Mode: PLANNING' "$PLAN_FILE" 2>/dev/null; then
    sedi 's/Mode: PLANNING/Mode: IMPLEMENTATION/' "$PLAN_FILE"
fi
if grep -q 'User: PENDING' "$PLAN_FILE" 2>/dev/null; then
    sedi 's/User: PENDING/User: APPROVED/' "$PLAN_FILE"
fi

exit 0
