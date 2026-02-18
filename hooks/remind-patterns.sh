#!/bin/bash
# user-prompt-submit hook
# Injects reminder about common failure patterns
# Also detects plan mode and reminds about expert-review
source "$(dirname "$0")/lib/claude-env.sh"

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
# NO FALLBACK: If current_plan doesn't exist, this session has no plan
SESSION_PLAN=""
if [[ -n "$CLAUDE_SESSION_ID" && -f "$CLAUDE_DIR/sessions/$CLAUDE_SESSION_ID/current_plan" ]]; then
    SESSION_PLAN=$(cat "$CLAUDE_DIR/sessions/$CLAUDE_SESSION_ID/current_plan")
    # Verify the file still exists
    if [[ ! -f "$SESSION_PLAN" ]]; then
        SESSION_PLAN=""
    fi
fi

if [[ -n "$SESSION_PLAN" && -f "$SESSION_PLAN" ]]; then
    RECENT_PLAN="$SESSION_PLAN"
fi

if [[ -n "$RECENT_PLAN" ]]; then
    PLAN_NAME=$(basename "$RECENT_PLAN")
    echo "PLAN: $PLAN_NAME | expert-review→ExitPlanMode"
fi

if [[ -n "$RECENT_PLAN" ]]; then
    PLAN_DIR=$(dirname "$RECENT_PLAN")
    if [[ -f "$PLAN_DIR/expert-review-pending" ]]; then
        echo "PENDING: expert-review"
    fi
fi
