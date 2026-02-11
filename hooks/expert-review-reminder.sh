#!/bin/bash
# PreToolUse hook for ExitPlanMode
# Uses CLAUDE_SESSION_ID directly (no PPID mapping needed)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

# Check if review required
PWD_PATH=$(pwd)
REQUIRES_REVIEW=false
[[ "$PWD_PATH" == *"/Physics/"* ]] && REQUIRES_REVIEW=true
[[ -f "CLAUDE.md" ]] && grep -q "expert-review\|Expert Review.*MANDATORY" CLAUDE.md 2>/dev/null && REQUIRES_REVIEW=true
[[ "$REQUIRES_REVIEW" != "true" ]] && exit 0

# Read session ID from PPID mapping (set by history-isolation.sh)
STATE_DIR="/tmp/claude-kb-state"
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

SESSION_PLAN_LINK="$HOME/.claude/sessions/$SESSION_ID/current_plan"
[[ -f "$SESSION_PLAN_LINK" ]] && PLAN_FILE=$(cat "$SESSION_PLAN_LINK")
[[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]] && exit 0

# If plan is already in IMPLEMENTATION mode, review was completed in a prior session
# Allow ExitPlanMode without re-review (Claude shouldn't call it, but don't block if it does)
if grep -q 'Mode: IMPLEMENTATION' "$PLAN_FILE" 2>/dev/null; then
    exit 0
fi

PLAN_DIR=$(dirname "$PLAN_FILE")
PLAN_BASE=$(basename "$PLAN_FILE" .md)

# Plan-specific markers (not shared across plans)
APPROVED_MARKER="$PLAN_DIR/${PLAN_BASE}.approved"
PENDING_MARKER="$PLAN_DIR/${PLAN_BASE}.pending"

# Check for approval marker (must be newer than plan.md)
if [[ -f "$APPROVED_MARKER" ]]; then
    PLAN_MTIME=$(python3 -c "import os;print(int(os.path.getmtime('$PLAN_FILE')))" 2>/dev/null || echo 0)
    MARKER_MTIME=$(python3 -c "import os;print(int(os.path.getmtime('$APPROVED_MARKER')))" 2>/dev/null || echo 0)
    if [[ "$MARKER_MTIME" -ge "$PLAN_MTIME" ]]; then
        exit 0  # Marker is newer than plan - approval valid
    else
        rm -f "$APPROVED_MARKER"  # Stale marker - plan was modified
        rm -f "$PENDING_MARKER"
    fi
fi

# Auto-detect APPROVED from agent output (resolves sandbox catch-22)
# Agents can't create .approved (sandbox), but this hook runs outside sandbox
AGENT_OUTPUT=$(ls -t "$PLAN_DIR"/agent-output/*-agent-*.md "$PLAN_DIR"/*-agent-*.md 2>/dev/null | head -1)
if [[ -n "$AGENT_OUTPUT" ]]; then
    PLAN_MTIME=$(python3 -c "import os;print(int(os.path.getmtime('$PLAN_FILE')))" 2>/dev/null || echo 0)
    AGENT_MTIME=$(python3 -c "import os;print(int(os.path.getmtime('$AGENT_OUTPUT')))" 2>/dev/null || echo 0)
    if [[ "$AGENT_MTIME" -ge "$PLAN_MTIME" ]]; then
        if grep -qE '^## (Verdict|Status|Review Status):.*APPROVED' "$AGENT_OUTPUT" 2>/dev/null; then
            touch "$APPROVED_MARKER"
            exit 0
        fi
    fi
fi

# Check for pending marker
if [[ -f "$PENDING_MARKER" ]]; then
    echo "BLOCKED: expert-review pending. Run expert-review or: touch $APPROVED_MARKER" >&2
    exit 2
fi

# First attempt - create pending marker and block
touch "$PENDING_MARKER"
echo "BLOCKED: expert-review required. Run expert-review for: $PLAN_FILE" >&2
echo "After approval: touch $APPROVED_MARKER" >&2
exit 2
