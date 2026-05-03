#!/bin/bash
# PreToolUse hook: Task tool
# Blocks Task dispatch (non-kb-research) unless kb-research was run this session.

STATE_DIR="/tmp/claude-kb-state"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "Task" ]] && exit 0

SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('subagent_type', ''))
except:
    pass
" 2>/dev/null)

# Allow kb-research dispatches through (they satisfy the gate)
[[ "$SUBAGENT_TYPE" == "kb-research" ]] && exit 0

# Check session state
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

SEARCHED_FILE="$STATE_DIR/${SESSION_ID}-searched"
if [[ ! -f "$SEARCHED_FILE" ]]; then
    echo "BLOCKED: Dispatching agent without prior kb-research this session." >&2
    echo "" >&2
    echo "Run kb-research first this session; pass results in dispatch prompt." >&2
    echo "Example: Task(subagent_type='kb-research', model='haiku', prompt='TOPIC: <your topic>')" >&2
    exit 2
fi

exit 0
