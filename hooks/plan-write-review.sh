#!/bin/bash
# PostToolUse hook for Edit/Write
# When a plan file is written, remind Claude to run expert-review BEFORE presenting

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
    exit 0
fi

# Get session ID: try hook input first, then PPID mapping
STATE_DIR="/tmp/claude-kb-state"
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
    SESSION_FILE="$STATE_DIR/session-$PPID"
    [[ -f "$SESSION_FILE" ]] && SESSION_ID=$(cat "$SESSION_FILE")
fi
[[ -z "$SESSION_ID" ]] && exit 0

# Extract file path
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tool_input = data.get('tool_input', {})
print(tool_input.get('file_path', ''))
" 2>/dev/null)

# Check if this is a plan file (not an agent output file)
if [[ "$FILE_PATH" != *"/.claude/plans/"* ]]; then
    exit 0
fi

# Move agent output files to subdirectory immediately (keeps main dir clean)
AGENT_DIR="$HOME/.claude/plans/agent-output"
mkdir -p "$AGENT_DIR"
if [[ "$FILE_PATH" == *"-agent-"* ]]; then
    # Move this agent file to subdirectory
    mv "$FILE_PATH" "$AGENT_DIR/" 2>/dev/null
    exit 0
fi

# Write session-to-plan mapping for session isolation
if [[ -n "$SESSION_ID" ]]; then
    SESSION_DIR="$HOME/.claude/sessions/$SESSION_ID"
    mkdir -p "$SESSION_DIR"
    echo "$FILE_PATH" > "$SESSION_DIR/current_plan"
fi

# Check if project requires expert-review
PWD_PATH=$(pwd)
REQUIRES_REVIEW=false

if [[ "$PWD_PATH" == *"/Physics/"* ]] || [[ "$PWD_PATH" == *"/physics/"* ]]; then
    REQUIRES_REVIEW=true
fi

if [[ -f "CLAUDE.md" ]] && grep -q "Expert Review.*MANDATORY" CLAUDE.md 2>/dev/null; then
    REQUIRES_REVIEW=true
fi

if [[ "$REQUIRES_REVIEW" != "true" ]]; then
    exit 0
fi

# Skip review reminder if plan is already approved and in implementation mode
# This prevents re-review when a plan is migrated to a new session
if grep -q 'Mode: IMPLEMENTATION' "$FILE_PATH" 2>/dev/null; then
    exit 0
fi

PLAN_NAME=$(basename "$FILE_PATH")

cat << EOF
PLAN FILE WRITTEN: $PLAN_NAME

STOP! Before presenting this plan to the user, you MUST run expert-review:

SESSION_ID=\$(date +%Y%m%d-%H%M%S)-\$(head -c 4 /dev/urandom | xxd -p)
mkdir -p ~/.claude/sessions/\$SESSION_ID
cp "$FILE_PATH" ~/.claude/sessions/\$SESSION_ID/plan.md
cat > ~/.claude/sessions/\$SESSION_ID/context.yaml << 'YAML'
reviewer_persona: "Senior physicist specializing in Clifford algebras"
project_root: $PWD_PATH
YAML
Task(subagent_type="expert-review", model="opus", prompt="Review: session://\$SESSION_ID")

DO NOT show the plan to the user until expert-review returns APPROVED.
If REJECTED or INCOMPLETE, fix the issues first.
EOF
