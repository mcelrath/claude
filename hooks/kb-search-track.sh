#!/bin/bash
# PostToolUse hook for mcp__knowledge-base__kb_search
# Sets flag that kb_search was called in this session

STATE_DIR="/tmp/claude-kb-state"
mkdir -p "$STATE_DIR"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Read session ID from PPID mapping (set by history-isolation.sh)
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

if [[ "$TOOL_NAME" == "mcp__knowledge-base__kb_search" ]]; then
    touch "$STATE_DIR/${SESSION_ID}-searched"
fi

exit 0
