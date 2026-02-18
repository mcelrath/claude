#!/bin/bash
# UserPromptSubmit hook - expands minimal input to resume instructions if resume file exists
source "$(dirname "$0")/lib/claude-env.sh"

# Read the user's input from stdin (JSON format)
INPUT=$(cat)
USER_MSG=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null)

# Check if input is minimal (single char or common resume triggers)
if [[ ! "$USER_MSG" =~ ^[.cCrR]?$ && "$USER_MSG" != "continue" && "$USER_MSG" != "resume" ]]; then
    exit 0  # Not a resume trigger, let normal processing happen
fi

# Get project name
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

# Get terminal-specific ID (PTY from /proc walk, falls back to CLAUDE_SESSION env)
source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)

# Terminal-specific resume file first
RESUME_FILE=""
if [[ -n "$TERM_ID" ]]; then
    RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TERM_ID}.txt"
fi

# Fallback to project-wide (safe only if single session per project)
if [[ -z "$RESUME_FILE" || ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}.txt"
fi

# Check if resume file exists
if [[ ! -f "$RESUME_FILE" ]]; then
    exit 0  # No resume state, let normal processing happen
fi

SESSION_ID=$(cat "$RESUME_FILE")
HANDOFF="$CLAUDE_DIR/sessions/${SESSION_ID}/handoff.md"

if [[ ! -f "$HANDOFF" ]]; then
    exit 0
fi

# Check if plan content was already output by session-start-resume.sh
PLAN_ALREADY_OUTPUT=false
CURRENT_PLAN=""
OLD_SESSION_DIR="$CLAUDE_DIR/sessions/${SESSION_ID}"
if [[ -f "$OLD_SESSION_DIR/current_plan" ]]; then
    CURRENT_PLAN=$(cat "$OLD_SESSION_DIR/current_plan")
fi

# Check work context
WORK_TYPE=""
if [[ -f "$OLD_SESSION_DIR/work_context.json" ]]; then
    WORK_TYPE=$(python3 -c "import json; print(json.load(open('$OLD_SESSION_DIR/work_context.json')).get('work_type',''))" 2>/dev/null)
fi

# Output resume instructions that Claude will see and act on
cat << EOF
AUTO-RESUME TRIGGERED
=====================
Resume file found: $RESUME_FILE
Session: $SESSION_ID

INSTRUCTIONS:
1. Read $HANDOFF for context
2. The plan content was already shown by SessionStart hook — DO NOT re-summarize it
3. If a plan was shown above, CONTINUE WORKING ON IT immediately:
   - PLANNING mode: continue developing the plan, run expert-review when ready
   - IMPLEMENTATION mode: start implementing, do not call ExitPlanMode
4. If no plan was shown, kb_search("$PROJECT") for context and continue the last task
5. After resuming, run: rm $RESUME_FILE
6. Do NOT ask "What would you like to work on?" — just continue.

BEGIN RESUME
EOF
