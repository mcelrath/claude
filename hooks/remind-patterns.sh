#!/bin/bash
# user-prompt-submit hook
# Injects reminder about common failure patterns
# Also detects plan mode and reminds about expert-review
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/beads-plan.sh"

# Compressed reminders (token-efficient)
echo "RULES: rg-before-new-code | no-mocks | options→AskUserQuestion | verify-not-guess | check-pwd"

# Check if this project requires expert-review
REQUIRES_REVIEW=false
PWD_PATH=$(pwd)

if [[ "$PWD_PATH" == *"/Physics/"* ]] || [[ "$PWD_PATH" == *"/physics/"* ]]; then
    REQUIRES_REVIEW=true
fi

if [[ -f "CLAUDE.md" ]] && grep -q "Expert Review.*MANDATORY" CLAUDE.md 2>/dev/null; then
    REQUIRES_REVIEW=true
fi

if [[ "$REQUIRES_REVIEW" != "true" ]]; then
    exit 0
fi

# Check for THIS session's plan (session isolation)
SESSION_PLAN=""
if [[ -n "$CLAUDE_SESSION_ID" && -f "$CLAUDE_DIR/sessions/$CLAUDE_SESSION_ID/current_plan" ]]; then
    SESSION_PLAN=$(cat "$CLAUDE_DIR/sessions/$CLAUDE_SESSION_ID/current_plan")
fi

[[ -z "$SESSION_PLAN" ]] && exit 0

# === BEADS PATH ===
if bd_is_beads_id "$SESSION_PLAN"; then
    EPIC_ID=$(bd_strip_prefix "$SESSION_PLAN")
    STATUS=$(bd_plan_status "$EPIC_ID")
    EPIC_STATUS=$(bd show "$EPIC_ID" --json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,list): d=d[0]
    print(d.get('status',''))
except:
    print('')
" 2>/dev/null)
    if [[ "$EPIC_STATUS" == "closed" ]]; then
        echo "PLAN: epic $EPIC_ID | APPROVED — implementing (do NOT call ExitPlanMode)"
    else
        echo "PLAN: epic $EPIC_ID | $STATUS — expert-review→ExitPlanMode"
    fi
    exit 0
fi

# === LEGACY FILE PATH ===
if [[ -f "$SESSION_PLAN" ]]; then
    PLAN_NAME=$(basename "$SESSION_PLAN")
    if grep -q 'Mode: IMPLEMENTATION' "$SESSION_PLAN" 2>/dev/null; then
        echo "PLAN: $PLAN_NAME | APPROVED — implementing (do NOT call ExitPlanMode)"
    else
        echo "PLAN: $PLAN_NAME | expert-review→ExitPlanMode"
    fi

    PLAN_DIR=$(dirname "$SESSION_PLAN")
    if [[ -f "$PLAN_DIR/expert-review-pending" ]]; then
        echo "PENDING: expert-review"
    fi
fi
