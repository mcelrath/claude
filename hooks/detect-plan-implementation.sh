#!/bin/bash
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/work_context.sh"

INPUT=$(cat)
USER_MSG=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null)

if ! echo "$USER_MSG" | grep -qi "implement the following plan"; then
    exit 0
fi

LOG="/tmp/claude-kb-state/detect-plan.log"
echo "$(date +%H:%M:%S) Detected plan implementation request" >> "$LOG"

SESSION_DIR=$(get_session_dir)
if [[ -z "$SESSION_DIR" ]]; then
    echo "$(date +%H:%M:%S) No session dir" >> "$LOG"
    exit 0
fi
mkdir -p "$SESSION_DIR"

PLAN_PATH=""

DIRECT_PATH=$(echo "$USER_MSG" | grep -oP '~/.claude/plans/[^\s"]+\.md' | head -1)
if [[ -n "$DIRECT_PATH" ]]; then
    EXPANDED="${DIRECT_PATH/#\~/$HOME}"
    if [[ -f "$EXPANDED" ]]; then
        PLAN_PATH="$EXPANDED"
        echo "$(date +%H:%M:%S) Found by direct path: $PLAN_PATH" >> "$LOG"
    fi
fi

if [[ -z "$PLAN_PATH" ]]; then
    TITLE=$(echo "$USER_MSG" | grep -oP '^# .+' -m1)
    if [[ -z "$TITLE" ]]; then
        TITLE=$(echo "$USER_MSG" | grep -oP '(?<=\n)# .+' -m1)
    fi
    if [[ -n "$TITLE" ]]; then
        BEST=""
        BEST_TIME=0
        for f in "$CLAUDE_DIR"/plans/*.md; do
            [[ -f "$f" ]] || continue
            HEAD=$(head -1 "$f")
            if [[ "$HEAD" == "$TITLE" ]]; then
                MTIME=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)
                if [[ "$MTIME" -gt "$BEST_TIME" ]]; then
                    BEST="$f"
                    BEST_TIME="$MTIME"
                fi
            fi
        done
        if [[ -n "$BEST" ]]; then
            PLAN_PATH="$BEST"
            echo "$(date +%H:%M:%S) Found by title match: $PLAN_PATH" >> "$LOG"
        fi
    fi
fi

if [[ -z "$PLAN_PATH" ]]; then
    echo "$(date +%H:%M:%S) No plan file found" >> "$LOG"
    exit 0
fi

echo "$PLAN_PATH" > "$SESSION_DIR/current_plan"
set_my_plan "$PLAN_PATH"
echo "$(date +%H:%M:%S) Set current_plan=$PLAN_PATH" >> "$LOG"

if grep -q 'expert-review: APPROVED' "$PLAN_PATH" 2>/dev/null; then
    if grep -q 'Mode: PLANNING' "$PLAN_PATH" 2>/dev/null; then
        sed -i 's/Mode: PLANNING/Mode: IMPLEMENTATION/' "$PLAN_PATH"
        sed -i 's/User: PENDING/User: APPROVED/' "$PLAN_PATH"
        echo "$(date +%H:%M:%S) Auto-updated Mode→IMPLEMENTATION (expert-review already APPROVED)" >> "$LOG"
    fi
    echo "PLAN ALREADY APPROVED — skip ExitPlanMode, begin implementation immediately."
fi
