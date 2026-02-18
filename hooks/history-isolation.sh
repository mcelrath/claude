#!/bin/bash
# Session isolation hook for Claude Code
# Sets unique HISTFILE per session to prevent history collision between concurrent sessions
source "$(dirname "$0")/lib/claude-env.sh"

# Read JSON input from stdin
input=$(cat)

# Extract session_id from JSON input
session_id=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)

if [[ -n "$session_id" ]]; then
    # Write to CLAUDE_ENV_FILE for Bash commands
    if [[ -n "$CLAUDE_ENV_FILE" ]]; then
        mkdir -p "$CLAUDE_DIR/history"
        echo "export HISTFILE=\"\$CLAUDE_DIR/history/${session_id}\"" >> "$CLAUDE_ENV_FILE"
        echo "export CLAUDE_SESSION_ID=\"${session_id}\"" >> "$CLAUDE_ENV_FILE"
    fi

    # Write PPID mapping for hooks (hooks can't access CLAUDE_ENV_FILE)
    STATE_DIR="/tmp/claude-kb-state"
    mkdir -p "$STATE_DIR"
    echo "$session_id" > "$STATE_DIR/session-$PPID"
fi
