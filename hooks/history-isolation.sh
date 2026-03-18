#!/bin/bash
# SessionStart hook: set unique HISTFILE per session to prevent history collision
source "$(dirname "$0")/lib/claude-env.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)

if [[ -n "$session_id" ]]; then
    if [[ -n "$CLAUDE_ENV_FILE" ]]; then
        mkdir -p "$CLAUDE_DIR/history"
        echo "export HISTFILE=\"\$CLAUDE_DIR/history/${session_id}\"" >> "$CLAUDE_ENV_FILE"
        echo "export CLAUDE_SESSION_ID=\"${session_id}\"" >> "$CLAUDE_ENV_FILE"
    fi

    STATE_DIR="/tmp/claude-kb-state"
    mkdir -p "$STATE_DIR"
    echo "$session_id" > "$STATE_DIR/session-$PPID"

    mkdir -p "$CLAUDE_DIR/sessions/$session_id"
fi
