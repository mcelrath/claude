#!/bin/bash
# KB Context Injection Hook
# Shows last work context and recent findings for current project

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

# Show last work context if available and recent (within last hour)
if [[ -f "$CONTEXT_FILE" ]]; then
    CONTEXT_AGE=$(($(date +%s) - $(stat -c %Y "$CONTEXT_FILE" 2>/dev/null || echo 0)))
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
