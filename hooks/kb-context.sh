#!/bin/bash
# KB Context Injection Hook
# Shows last work context and recent findings for current project
# TTY-aware: prefers TTY-specific handoff over project-wide KB dump

KB_SCRIPT="$HOME/Projects/ai/kb/kb.py"
KB_VENV="$HOME/Projects/ai/kb/.venv/bin/python"
CONTEXT_FILE="$HOME/.cache/kb/last_work_context.txt"

# Get project name from git root or current directory
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

# Skip if no project detected
if [[ -z "$PROJECT" ]]; then
    exit 0
fi

export KB_EMBEDDING_URL="http://ash:8080/embedding"
export KB_EMBEDDING_DIM=4096

# Check for TTY-specific handoff first (avoids showing wrong session's KB findings)
TTY_ID=$(tty 2>/dev/null | tr '/' '-' | sed 's/^-//')
TTY_RESUME_FILE=""
if [[ -n "$TTY_ID" && "$TTY_ID" != "not a tty" ]]; then
    TTY_RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}-${TTY_ID}.txt"
fi

if [[ -f "$TTY_RESUME_FILE" ]]; then
    SESSION_ID=$(cat "$TTY_RESUME_FILE")
    HANDOFF="$HOME/.claude/sessions/${SESSION_ID}/handoff.md"
    if [[ -f "$HANDOFF" ]]; then
        # Extract KB IDs from THIS session's handoff (scoped to TTY's work)
        KB_IDS=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" 2>/dev/null | sort -u | head -5)
        if [[ -n "$KB_IDS" ]]; then
            echo "=== KB Findings (this TTY's session) ==="
            for KB_ID in $KB_IDS; do
                "$KB_VENV" "$KB_SCRIPT" get "$KB_ID" 2>/dev/null | head -3
            done
            exit 0  # Skip project-wide dump - TTY-specific context is sufficient
        fi
    fi
fi

# No TTY-specific handoff - fall back to project-wide context

# Show last work context if available and recent (within last hour)
if [[ -f "$CONTEXT_FILE" ]]; then
    CONTEXT_AGE=$(($(date +%s) - $(python3 -c "import os;print(int(os.path.getmtime('$CONTEXT_FILE')))" 2>/dev/null || echo 0)))
    if [[ $CONTEXT_AGE -lt 3600 ]]; then
        SAVED_PROJECT=$(grep "^Project:" "$CONTEXT_FILE" | cut -d: -f2- | xargs)
        if [[ "$SAVED_PROJECT" == "$PROJECT" ]]; then
            echo "=== Last Session Context ==="
            grep "^Context:" "$CONTEXT_FILE" | cut -d: -f2-
            echo ""
        fi
    fi
fi

# Show recent findings for this project
FINDINGS=$("$KB_VENV" "$KB_SCRIPT" list --project="$PROJECT" --limit=3 2>/dev/null) || true

if [[ -n "$FINDINGS" && "$FINDINGS" != "No findings found." ]]; then
    echo "=== Recent KB Findings ($PROJECT) ==="
    echo "$FINDINGS" | head -15
fi

# Show any recent errors for this project
ERRORS=$("$KB_VENV" "$KB_SCRIPT" error list --project="$PROJECT" --limit=2 2>/dev/null) || true

if [[ -n "$ERRORS" && "$ERRORS" != "No errors recorded." ]]; then
    echo ""
    echo "=== Known Errors ($PROJECT) ==="
    echo "$ERRORS" | head -10
fi

exit 0
