#!/bin/bash
# PostToolUse hook tracking kb search activity (Bash CLI or kb-research Task).
# Sets a per-session flag the gate hook reads. The MCP kb_search tool was
# removed 2026-05-19; canonical entrypoint is `~/.local/bin/kb search` via Bash.

STATE_DIR="/tmp/claude-kb-state"
mkdir -p "$STATE_DIR"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Read session ID from PPID mapping (set by history-isolation.sh)
SESSION_FILE="$STATE_DIR/session-$PPID"
if [[ ! -f "$SESSION_FILE" ]]; then
    echo "WARNING: Session file $SESSION_FILE not found (PPID=$PPID)"
    exit 0
fi
SESSION_ID=$(cat "$SESSION_FILE")

# CLI kb search via Bash (current path).
if [[ "$TOOL_NAME" == "Bash" ]]; then
    CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
    if echo "$CMD" | grep -qE '(^|[[:space:];&|`(])(~/\.local/bin/)?kb[[:space:]]+search\b'; then
        touch "$STATE_DIR/${SESSION_ID}-searched"
    fi
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
