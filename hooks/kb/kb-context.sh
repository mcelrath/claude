#!/bin/bash

# --- EMBEDDING-DOWN gate (ash:8081): surface hard STOP instead of blind retrieval ---
# SessionStart injects this hook's STDOUT into the agent's context (stderr is only
# logged), so the embedding-down warning MUST go to stdout to actually reach the
# agent at session start (kb-zma part 1). It is emitted FIRST so it leads the
# context block.
. "$HOME/.claude/hooks/lib/ash_health.sh" 2>/dev/null || true
if command -v ash_down >/dev/null 2>&1 && ash_down; then
  echo "$ASH_STOP_LINE"
fi

# KB Context Injection Hook
# Shows last work context and recent findings for current project
# TTY-aware: prefers TTY-specific handoff over project-wide KB dump
source "$HOME/.claude/hooks/lib/claude-env.sh"

KB_SCRIPT="${KB_SCRIPT:-$HOME/Projects/ai/kb/kb.py}"
KB_VENV="${KB_VENV:-$HOME/Projects/ai/kb/.venv/bin/python}"

# Gracefully exit if KB tools not installed
[[ ! -f "$KB_SCRIPT" || ! -f "$KB_VENV" ]] && exit 0
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

export KB_EMBEDDING_URL="${KB_EMBEDDING_URL:-http://ash:8081/embedding}"
export KB_EMBEDDING_DIM=4096

# Check for TTY-specific handoff first (avoids showing wrong session's KB findings)
TTY_ID=$(tty 2>/dev/null | tr '/' '-' | sed 's/^-//')
TTY_RESUME_FILE=""
if [[ -n "$TTY_ID" && "$TTY_ID" != "not a tty" ]]; then
    TTY_RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TTY_ID}.txt"
fi

if [[ -f "$TTY_RESUME_FILE" ]]; then
    SESSION_ID=$(cat "$TTY_RESUME_FILE")
    HANDOFF="$CLAUDE_DIR/sessions/${SESSION_ID}/handoff.md"
    if [[ -f "$HANDOFF" ]]; then
        # Extract KB IDs from THIS session's handoff (scoped to TTY's work)
        KB_IDS=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" 2>/dev/null | sort -u | head -5)
        if [[ -n "$KB_IDS" ]]; then
            echo "Session KB: $KB_IDS"
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

# Surface findings: SEMANTIC (relevance) when the saved session context gives a
# query signal; else fall back to recency. (kb-mrl: recency -> vector-query.)
# Per-prompt semantic surfacing lives in kb-prompt-surface.py (UserPromptSubmit);
# this SessionStart path only has the resume context to query with.
KB_IDS=""
CTX_QUERY=$(grep "^Context:" "$CONTEXT_FILE" 2>/dev/null | cut -d: -f2- | tr '\n' ' ' | head -c 300)
if [[ -n "$CTX_QUERY" ]]; then
    HITS=$("$KB_VENV" "$KB_SCRIPT" search "$CTX_QUERY" --project="$PROJECT" --limit=5 --json 2>/dev/null) || true
    if [[ -n "$HITS" ]]; then
        KB_IDS=$(printf '%s' "$HITS" | "$KB_VENV" -c "import sys,json
try: d=json.load(sys.stdin)
except Exception: d=[]
print(' '.join(r['id'] for r in d if float(r.get('similarity') or 0) >= 0.42)[:120])" 2>/dev/null)
    fi
    [[ -n "$KB_IDS" ]] && echo "Relevant KB ($PROJECT, semantic): $KB_IDS"
fi

# Recency fallback when no semantic query/hits available.
if [[ -z "$KB_IDS" ]]; then
    FINDINGS=$("$KB_VENV" "$KB_SCRIPT" list --project="$PROJECT" --limit=3 2>/dev/null) || true
    if [[ -n "$FINDINGS" && "$FINDINGS" != "No findings found." ]]; then
        KB_IDS=$(echo "$FINDINGS" | grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' | head -5 | tr '\n' ' ')
        [[ -n "$KB_IDS" ]] && echo "Recent KB ($PROJECT): $KB_IDS"
    fi
fi

exit 0
