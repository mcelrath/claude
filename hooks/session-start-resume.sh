#!/bin/bash
# Notification hook - checks for pending session resume on session start
# Runs on session start to detect if previous session saved state

# Get project name
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

# Check terminal-specific resume file first (avoids concurrent session conflicts)
TTY_ID=$(tty 2>/dev/null | tr '/' '-' | sed 's/^-//')
if [[ -n "$TTY_ID" && "$TTY_ID" != "not a tty" ]]; then
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}-${TTY_ID}.txt"
else
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}.txt"
fi

# Fallback to project-wide if terminal-specific doesn't exist
if [[ ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}.txt"
fi

# FALLBACK: If project-specific doesn't exist, check for ANY resume file (most recent)
# This handles cases where Claude starts from different directory than /compact ran
if [[ ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE=$(ls -t "$HOME/.claude/sessions/resume-"*.txt 2>/dev/null | head -1)
fi

if [[ -f "$RESUME_FILE" ]]; then
    SESSION_ID=$(cat "$RESUME_FILE")
    HANDOFF="$HOME/.claude/sessions/${SESSION_ID}/handoff.md"
    TASKS="$HOME/.claude/sessions/${SESSION_ID}/tasks.json"

    if [[ -f "$HANDOFF" ]]; then
        # Extract KB checkpoint ID from handoff (source of truth)
        KB_CHECKPOINT=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" | head -1)

        echo "RESUME: Previous session state found"
        echo "  Handoff: $HANDOFF"
        echo "  Tasks: $TASKS"
        if [[ -n "$KB_CHECKPOINT" ]]; then
            echo "  KB Checkpoint: $KB_CHECKPOINT (SOURCE OF TRUTH)"
            echo "  Action: Read handoff, kb_list(project) for recent findings, summarize state"
            echo "  IMPORTANT: Do NOT auto-create tasks from tasks.json - they are often stale."
            echo "  Tasks.json is for CONTEXT only. KB findings show actual work done."
        else
            echo "  Action: Read handoff, kb_list for context, summarize state"
            echo "  IMPORTANT: Do NOT auto-create tasks from tasks.json - they are often stale."
        fi
    fi
fi
