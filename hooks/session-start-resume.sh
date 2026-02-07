#!/bin/bash
# Notification hook - checks for pending session resume on session start
# Runs on session start to detect if previous session saved state

# Get project name
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

# Get terminal-specific ID (PTY from /proc walk, falls back to CLAUDE_SESSION env)
source "$HOME/.claude/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)

# Terminal-specific resume file first
RESUME_FILE=""
if [[ -n "$TERM_ID" ]]; then
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}-${TERM_ID}.txt"
fi

# Fallback to project-wide (safe only if single session per project)
if [[ ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}.txt"
fi

if [[ -f "$RESUME_FILE" ]]; then
    SESSION_ID=$(cat "$RESUME_FILE")
    HANDOFF="$HOME/.claude/sessions/${SESSION_ID}/handoff.md"
    TASKS="$HOME/.claude/sessions/${SESSION_ID}/tasks.json"

    if [[ -f "$HANDOFF" ]]; then
        KB_CHECKPOINT=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" | head -1)
        REVIEW_LINE=$(grep -A1 "## Expert Review" "$HANDOFF" 2>/dev/null | tail -1)

        echo "RESUME: Previous session state found"
        echo "  Handoff: $HANDOFF"
        echo "  Tasks: $TASKS"
        if [[ -n "$REVIEW_LINE" && "$REVIEW_LINE" != "No expert review this session" ]]; then
            echo "  Expert Review: $REVIEW_LINE"
        fi
        if [[ -n "$KB_CHECKPOINT" ]]; then
            echo "  KB Checkpoint: $KB_CHECKPOINT (SOURCE OF TRUTH)"
            echo "  Action: Read handoff, kb_list(project) for recent findings, summarize state"
            echo "  IMPORTANT: Do NOT auto-create tasks from tasks.json - they are often stale."
            echo "  Tasks.json is for CONTEXT only. KB findings show actual work done."
        else
            echo "  Action: Read handoff, kb_list for context, summarize state"
            echo "  IMPORTANT: Do NOT auto-create tasks from tasks.json - they are often stale."
        fi
        if ls "$HOME/.claude/teams"/*/config.json &>/dev/null 2>&1; then
            echo "  WARNING: Agent team config found. Teammates don't survive /compact."
            echo "  Spawn fresh teammates if team work needs to continue."
        fi
        # Detect plan file migration needed
        PREV_PLAN_REL=$(grep -E "^plans/" "$HANDOFF" 2>/dev/null | head -1)
        if [[ -n "$PREV_PLAN_REL" ]]; then
            PREV_PLAN_FULL="$HOME/.claude/$PREV_PLAN_REL"
        else
            PREV_PLAN_FULL=$(grep -oE '/[^ ]*/.claude/plans/[a-z0-9][-a-z0-9_]+\.md' "$HANDOFF" 2>/dev/null | head -1)
        fi
        if [[ -n "$PREV_PLAN_FULL" && -f "$PREV_PLAN_FULL" ]]; then
            echo "  PLAN_MIGRATION: $PREV_PLAN_FULL"
            echo "  ACTION: If in plan mode, copy contents to your new plan file"
        fi
    fi
fi

# Inject code map for projects with lib/ directory
LIB_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/lib"
if [[ -d "$LIB_DIR" ]]; then
    CODEMAP=$(python3 "$HOME/.claude/hooks/lib/generate_codemap.py" "$LIB_DIR" 2>/dev/null | head -80)
    if [[ -n "$CODEMAP" ]]; then
        echo ""
        echo "=== Code Map ==="
        echo "$CODEMAP"
    fi
fi
