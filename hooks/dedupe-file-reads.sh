#!/bin/bash
# PreToolUse hook for Read - warn if file was already read this session

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

[[ "$TOOL_NAME" != "Read" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

# Get session ID
STATE_DIR="/tmp/claude-kb-state"
SESSION_FILE="$STATE_DIR/session-$PPID"
[[ ! -f "$SESSION_FILE" ]] && exit 0
SESSION_ID=$(cat "$SESSION_FILE")

# Track reads per session
READS_FILE="$STATE_DIR/${SESSION_ID}-reads"
touch "$READS_FILE"

# Check if already read
if grep -qF "$FILE_PATH" "$READS_FILE" 2>/dev/null; then
    SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || echo 0)
    if [[ $SIZE -gt 5000 ]]; then
        echo "NOTE: $FILE_PATH ($(($SIZE/1024))KB) was already read this session"
    fi
fi

# Record this read
echo "$FILE_PATH" >> "$READS_FILE"
exit 0
