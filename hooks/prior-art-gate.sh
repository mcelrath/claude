#!/bin/bash
# PreToolUse hook: Task and Edit/Write
# Blocks Task dispatch (non-kb-research) unless kb-research was run this session.
# Blocks Edit/Write to cl44/, proofs/, or .tex files unless kb search was run.

STATE_DIR="/tmp/claude-kb-state"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# --- Task dispatch gate (unchanged) ---
if [[ "$TOOL_NAME" == "Task" ]]; then
    SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('subagent_type', ''))
except:
    pass
" 2>/dev/null)

    [[ "$SUBAGENT_TYPE" == "kb-research" ]] && exit 0

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
fi

# --- Edit/Write gate for physics files ---
if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
    FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
    [[ -z "$FILE_PATH" ]] && exit 0

    # Only gate physics-critical paths
    GATED=0
    case "$FILE_PATH" in
        */cl44/*.py)           GATED=1 ;;
        */proofs/*.lean)       GATED=1 ;;
        */*.tex)               GATED=1 ;;
    esac
    [[ "$GATED" == "0" ]] && exit 0

    # Skip if file is a test
    case "$FILE_PATH" in
        */test_*|*_test.py|*/tests/*) exit 0 ;;
    esac

    SESSION_FILE="$STATE_DIR/session-$PPID"
    [[ ! -f "$SESSION_FILE" ]] && exit 0
    SESSION_ID=$(cat "$SESSION_FILE")

    SEARCHED_FILE="$STATE_DIR/${SESSION_ID}-searched"
    if [[ ! -f "$SEARCHED_FILE" ]]; then
        cat >&2 <<EOF
BLOCKED: Editing physics file without prior-art check this session.
  Target: $FILE_PATH

Before editing cl44/, proofs/, or .tex files, run at least ONE of:
  1. ~/.local/bin/kb search "<what you are implementing>"
  2. Task(subagent_type='kb-research', model='haiku', prompt='TOPIC: ...')

This prevents reimplementing existing work or contradicting proven results.
The search flag persists for the rest of the session after one search.
EOF
        exit 2
    fi
fi

exit 0
