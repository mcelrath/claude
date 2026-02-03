#!/bin/bash
# PreToolUse hook for Edit/Write
# BLOCKS unless kb_search was called this session

STATE_DIR="/tmp/claude-kb-state"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Read session ID from PPID mapping (set by history-isolation.sh)
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

case "$TOOL_NAME" in
    Edit|Write)
        SEARCHED_FILE="$STATE_DIR/${SESSION_ID}-searched"
        if [[ ! -f "$SEARCHED_FILE" ]]; then
            echo "BLOCKED: No kb_search called yet this session." >&2
            echo "" >&2
            echo "Run kb_search('<what you are implementing>') first." >&2
            echo "This is mandatory. Every time. No exceptions." >&2
            exit 2
        fi
        ;;
esac

exit 0
