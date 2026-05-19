#!/bin/bash
# PreToolUse hook for Edit/Write
# BLOCKS unless `kb search` (Bash CLI) was called this session
# EXCEPTIONS: hooks directory, /tmp/, /dev/shm/
# MCP kb_search tool was removed 2026-05-19; canonical form is
# `~/.local/bin/kb search "<query>"` via Bash. See kb-search-track.sh.
source "$(dirname "$0")/lib/claude-env.sh"

STATE_DIR="/tmp/claude-kb-state"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Read session ID from PPID mapping (set by history-isolation.sh)
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

case "$TOOL_NAME" in
    Edit|Write)
        # Extract file path from tool_input
        FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(tool_input.get('file_path', ''))
except:
    pass
" 2>/dev/null)

        # Allow edits to hooks, /tmp, /dev/shm
        if [[ "$FILE_PATH" == "$CLAUDE_DIR/hooks/"* ]] || \
           [[ "$FILE_PATH" == "/tmp/"* ]] || \
           [[ "$FILE_PATH" == "/dev/shm/"* ]]; then
            exit 0
        fi

        # Skip gate if implementing an approved plan (post /clear resume)
        SESSION_DIR="$CLAUDE_DIR/sessions/$SESSION_ID"
        if [[ -f "$SESSION_DIR/current_plan" ]]; then
            PLAN_FILE=$(cat "$SESSION_DIR/current_plan")
            if [[ -f "$PLAN_FILE" ]] && grep -q 'Mode: IMPLEMENTATION' "$PLAN_FILE" 2>/dev/null; then
                exit 0
            fi
        fi

        # Check if search was done
        SEARCHED_FILE="$STATE_DIR/${SESSION_ID}-searched"
        if [[ ! -f "$SEARCHED_FILE" ]]; then
            echo "BLOCKED: No 'kb search' run yet this session." >&2
            echo "" >&2
            echo "Run: ~/.local/bin/kb search \"<what you are implementing>\"" >&2
            echo "(MCP kb_search was removed 2026-05-19; Bash CLI is the only entrypoint.)" >&2
            echo "This is mandatory. Every time. No exceptions." >&2
            exit 2
        fi
        ;;
esac

exit 0
