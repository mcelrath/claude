#!/bin/bash
# PostToolUse hook for Edit/Write on implementation files
# Reminds to record alternative approaches before they're lost to compaction
# Fires ONCE per session (uses flag file to avoid spam)
source "$(dirname "$0")/lib/claude-env.sh"

STATE_DIR="/tmp/claude-kb-state"
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

case "$TOOL_NAME" in
    Edit|Write)
        FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', ''))
except:
    pass
" 2>/dev/null)

        # Only fire for implementation files (not config/meta)
        [[ "$FILE_PATH" == "$CLAUDE_DIR/"* ]] && exit 0
        [[ "$FILE_PATH" == "/tmp/"* ]] && exit 0
        [[ "$FILE_PATH" == "/dev/shm/"* ]] && exit 0
        [[ "$FILE_PATH" == *"/CLAUDE.md" ]] && exit 0
        [[ "$FILE_PATH" == *"/memory/"* ]] && exit 0
        [[ "$FILE_PATH" == *"/MEMORY.md" ]] && exit 0

        # Get session ID
        SESSION_FILE="$STATE_DIR/session-$PPID"
        [[ ! -f "$SESSION_FILE" ]] && exit 0
        SESSION_ID=$(cat "$SESSION_FILE")

        # Fire only once per session
        FLAG="$STATE_DIR/${SESSION_ID}-alternatives-reminded"
        [[ -f "$FLAG" ]] && exit 0
        touch "$FLAG"

        echo "ALTERNATIVES CHECK: You're starting implementation. Before the conversation history"
        echo "compacts, record any alternative approaches you considered but rejected."
        echo ""
        echo "For each rejected alternative: bd create -t idea \"<alternative approach>\" --description=\"Rejected in favor of <chosen>. Reason: <why>\""
        echo ""
        echo "This is a one-time reminder per session. Alternatives lost to compaction cannot be recovered."
        ;;
esac

exit 0
