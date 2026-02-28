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

    # Create session directory and carry forward current_plan from previous session
    SESSION_DIR="$CLAUDE_DIR/sessions/$session_id"
    mkdir -p "$SESSION_DIR"

    # Find previous session on the same terminal and carry forward current_plan
    source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
    TERM_ID=$(_get_terminal_id)
    if [[ -n "$TERM_ID" ]]; then
        if git rev-parse --show-toplevel &>/dev/null; then
            PROJECT=$(basename "$(git rev-parse --show-toplevel)")
        else
            PROJECT=$(basename "$PWD")
        fi
        RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TERM_ID}.txt"
        if [[ -f "$RESUME_FILE" ]]; then
            OLD_SESSION_ID=$(cat "$RESUME_FILE")
            OLD_PLAN="$CLAUDE_DIR/sessions/${OLD_SESSION_ID}/current_plan"
            if [[ -f "$OLD_PLAN" ]]; then
                PLAN_PATH=$(cat "$OLD_PLAN")
                if [[ -f "$PLAN_PATH" ]]; then
                    echo "$PLAN_PATH" > "$SESSION_DIR/current_plan"
                fi
            fi
        fi
    fi
fi
