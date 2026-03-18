#!/bin/bash
# PreToolUse hook for ExitPlanMode
# Blocks ExitPlanMode if expert-review has not approved the plan
# Supports both beads epic IDs and legacy file-based approval
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/beads-plan.sh"

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

SESSION_PLAN_LINK="$CLAUDE_DIR/sessions/$SESSION_ID/current_plan"
[[ ! -f "$SESSION_PLAN_LINK" ]] && exit 0
CURRENT_PLAN=$(cat "$SESSION_PLAN_LINK")
[[ -z "$CURRENT_PLAN" ]] && exit 0

# === BEADS PATH: current_plan contains a beads epic ID ===
if bd_is_beads_id "$CURRENT_PLAN"; then
    if bd_plan_is_approved "$CURRENT_PLAN"; then
        exit 0  # All analysis children closed — approved
    else
        STATUS=$(bd_plan_status "$(bd_strip_prefix "$CURRENT_PLAN")")
        echo "BLOCKED: analysis epic $(bd_strip_prefix "$CURRENT_PLAN") not resolved ($STATUS)" >&2
        echo "Run: bd children $(bd_strip_prefix "$CURRENT_PLAN")" >&2
        exit 2
    fi
fi

# === LEGACY FILE PATH: current_plan contains a file path ===
PLAN_FILE="$CURRENT_PLAN"
[[ ! -f "$PLAN_FILE" ]] && exit 0

# If plan is already in IMPLEMENTATION mode, review was completed in a prior session
if grep -q 'Mode: IMPLEMENTATION' "$PLAN_FILE" 2>/dev/null; then
    exit 0
fi

# If plan content itself records expert-review: APPROVED, allow ExitPlanMode
if grep -q 'expert-review: APPROVED' "$PLAN_FILE" 2>/dev/null; then
    PLAN_DIR=$(dirname "$PLAN_FILE")
    PLAN_BASE=$(basename "$PLAN_FILE" .md)
    touch "$PLAN_DIR/${PLAN_BASE}.approved" 2>/dev/null
    exit 0
fi

PLAN_DIR=$(dirname "$PLAN_FILE")
PLAN_BASE=$(basename "$PLAN_FILE" .md)
APPROVED_MARKER="$PLAN_DIR/${PLAN_BASE}.approved"
PENDING_MARKER="$PLAN_DIR/${PLAN_BASE}.pending"

# Check for approval marker (must be newer than plan.md)
if [[ -f "$APPROVED_MARKER" ]]; then
    PLAN_MTIME=$(python3 -c "import os;print(int(os.path.getmtime('$PLAN_FILE')))" 2>/dev/null || echo 0)
    MARKER_MTIME=$(python3 -c "import os;print(int(os.path.getmtime('$APPROVED_MARKER')))" 2>/dev/null || echo 0)
    if [[ "$MARKER_MTIME" -ge "$PLAN_MTIME" ]]; then
        exit 0
    else
        rm -f "$APPROVED_MARKER"
        rm -f "$PENDING_MARKER"
    fi
fi

# Auto-detect APPROVED from agent output
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
