#!/bin/bash
# UserPromptSubmit hook: detect "implement the following plan" and bind session to plan
# Supports both beads epics and legacy file-based plans
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/beads-plan.sh"
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

# === Try BEADS first: search open epics with plan:active label ===
BEADS_MATCH=""
PLAN_TITLE=$(echo "$USER_MSG" | grep -oP '^# .+' -m1)
[[ -z "$PLAN_TITLE" ]] && PLAN_TITLE=$(echo "$USER_MSG" | grep -oP '(?<=\n)# .+' -m1)

if [[ -n "$PLAN_TITLE" ]]; then
    CLEAN_TITLE=$(echo "$PLAN_TITLE" | sed 's/^# //')
    BEADS_MATCH=$(MATCH_TITLE="$CLEAN_TITLE" bd list --type epic --status open --json 2>/dev/null | python3 -c "
import sys, json, os
title = os.environ.get('MATCH_TITLE', '').strip()
try:
    issues = json.load(sys.stdin)
    for i in issues:
        if title.lower() in i.get('title','').lower():
            print(i['id'])
            break
except:
    pass
" 2>/dev/null)
fi

if [[ -n "$BEADS_MATCH" ]]; then
    echo "$(date +%H:%M:%S) Found beads epic: $BEADS_MATCH" >> "$LOG"
    bd_plan_bind_session "$SESSION_DIR" "$BEADS_MATCH"
    set_my_plan "beads:$BEADS_MATCH"

    EPIC_STATUS=$(bd show "$BEADS_MATCH" --json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,list): d=d[0]
    print(d.get('status',''))
except:
    print('')
" 2>/dev/null)

    if [[ "$EPIC_STATUS" == "closed" ]] || bd_plan_is_approved "$BEADS_MATCH"; then
        echo "PLAN ALREADY APPROVED (epic $BEADS_MATCH) — skip ExitPlanMode, begin implementation immediately."
    fi
    exit 0
fi

# === LEGACY FILE PATH ===
PLAN_PATH=""

DIRECT_PATH=$(echo "$USER_MSG" | grep -oP '~/.claude/plans/[^\s"]+\.md' | head -1)
if [[ -n "$DIRECT_PATH" ]]; then
    EXPANDED="${DIRECT_PATH/#\~/$HOME}"
    if [[ -f "$EXPANDED" ]]; then
        PLAN_PATH="$EXPANDED"
        echo "$(date +%H:%M:%S) Found by direct path: $PLAN_PATH" >> "$LOG"
    fi
fi

if [[ -z "$PLAN_PATH" && -n "$PLAN_TITLE" ]]; then
    BEST=""
    BEST_TIME=0
    for f in "$CLAUDE_DIR"/plans/*.md; do
        [[ -f "$f" ]] || continue
        HEAD=$(head -1 "$f")
        if [[ "$HEAD" == "$PLAN_TITLE" ]]; then
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
