#!/bin/bash
# PostToolUse hook: Task
# If agent output contains closure verbs, inject a scope-verification reminder.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "Task" ]] && exit 0

OUTPUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    r = data.get('tool_result', {})
    # Task result may be a string or dict
    if isinstance(r, str):
        print(r[:8000])
    elif isinstance(r, dict):
        print(str(r.get('output', r.get('content', str(r))))[:8000])
    else:
        print(str(r)[:8000])
except:
    pass
" 2>/dev/null)

[[ -z "$OUTPUT" ]] && exit 0

FOUND=$(echo "$OUTPUT" | grep -iE '\b(complete|completed|verified|closed|negative|proven|proved|done|finished)\b' | head -1)

if [[ -n "$FOUND" ]]; then
    echo "" >&2
    echo "AGENT CLOSURE DETECTED: Agent used a closure verb in its report." >&2
    echo "  Matched: $(echo "$FOUND" | head -c 120)" >&2
    echo "" >&2
    echo "Agent claimed CLOSURE — verify SCOPE: what was tested vs implied?" >&2
    echo "  1. Does the agent's tested scope match the title/claim?" >&2
    echo "  2. Are negative results specific (narrow probe) or general?" >&2
    echo "  3. Was a random/null baseline included if a match ratio was reported?" >&2
fi

exit 0
