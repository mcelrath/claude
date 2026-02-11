#!/bin/bash
# PostToolUse hook for mcp__knowledge-base__kb_search and Task
# Sets flag that kb_search was called in this session
# Also sets flag when delegating to kb-research agent

STATE_DIR="/tmp/claude-kb-state"
mkdir -p "$STATE_DIR"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Read session ID from PPID mapping (set by history-isolation.sh)
SESSION_FILE="$STATE_DIR/session-$PPID"
if [[ ! -f "$SESSION_FILE" ]]; then
    echo "WARNING: Session file $SESSION_FILE not found (PPID=$PPID)" >&2
    exit 0
fi
SESSION_ID=$(cat "$SESSION_FILE")

# Direct kb_search call
if [[ "$TOOL_NAME" == "mcp__knowledge-base__kb_search" ]]; then
    touch "$STATE_DIR/${SESSION_ID}-searched"
fi

# Task delegation to kb-research agent (agent will call kb_search in its session)
if [[ "$TOOL_NAME" == "Task" ]]; then
    SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(tool_input.get('subagent_type', ''))
except:
    pass
" 2>/dev/null)

    if [[ "$SUBAGENT_TYPE" == "kb-research" ]]; then
        touch "$STATE_DIR/${SESSION_ID}-searched"
    fi
fi

exit 0
