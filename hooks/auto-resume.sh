#!/bin/bash
# UserPromptSubmit hook - expands minimal input to resume instructions if resume file exists

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

# Check terminal-specific resume file first (avoids concurrent session conflicts)
TTY_ID=$(tty 2>/dev/null | tr '/' '-' | sed 's/^-//')
if [[ -n "$TTY_ID" && "$TTY_ID" != "not a tty" ]]; then
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}-${TTY_ID}.txt"
fi

# Fallback to project-wide
if [[ ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}.txt"
fi

# FALLBACK: If project-specific doesn't exist, check for ANY resume file (most recent)
if [[ ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE=$(ls -t "$HOME/.claude/sessions/resume-"*.txt 2>/dev/null | head -1)
fi

# Check if resume file exists
if [[ ! -f "$RESUME_FILE" ]]; then
    exit 0  # No resume state, let normal processing happen
fi

SESSION_ID=$(cat "$RESUME_FILE")
HANDOFF="$HOME/.claude/sessions/${SESSION_ID}/handoff.md"

if [[ ! -f "$HANDOFF" ]]; then
    exit 0
fi

# Output resume instructions that Claude will see and act on
cat << EOF
AUTO-RESUME TRIGGERED
=====================
Resume file found: $RESUME_FILE
Session: $SESSION_ID

INSTRUCTIONS:
1. Read $HANDOFF
2. Parse the State JSON for context
3. kb_search("$PROJECT") for recent findings
4. TaskList to check task state
5. Continue from where handoff indicates
6. After resuming, run: rm $RESUME_FILE

BEGIN RESUME
EOF
