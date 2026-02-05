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

# FALLBACK 2: No resume pointer at all — retroactively create handoff from previous session
# This recovers state after /clear (which has no PreClear hook to save state)
if [[ ! -f "$RESUME_FILE" ]]; then
    PROJECT_PATH=$(pwd | sed 's|/|-|g; s|^-||')
    PROJECT_DIR="$HOME/.claude/projects/-${PROJECT_PATH}"
    HELPER="$HOME/.claude/hooks/lib/find_session_jsonl.py"

    # Get SECOND most recent JSONL (n=1): current session is n=0
    PREV_JSONL=$(python3 "$HELPER" nth "$PROJECT_DIR" 1 2>/dev/null)

    if [[ -n "$PREV_JSONL" && -f "$PREV_JSONL" ]]; then
        PREV_SID=$(basename "$PREV_JSONL" .jsonl)
        PREV_DIR="$HOME/.claude/sessions/$PREV_SID"

        if [[ -f "$PREV_DIR/handoff.md" ]]; then
            # PreCompact already ran for this session — just create missing resume pointer
            echo "$PREV_SID" > "$HOME/.claude/sessions/resume-${PROJECT}.txt"
            RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}.txt"
        else
            # Create lightweight handoff from JSONL (no LLM, pure file I/O)
            mkdir -p "$PREV_DIR"
            CONTEXT_JSON=$(python3 "$HOME/.claude/hooks/lib/extract_session_state.py" \
                "$PREV_JSONL" 2>/dev/null)
            if [[ -n "$CONTEXT_JSON" ]]; then
                CONTEXT_JSON="$CONTEXT_JSON" python3 <<'PYEOF' "$PREV_SID" "$PROJECT" "$PREV_DIR"
import sys, json, os
ctx = json.loads(os.environ['CONTEXT_JSON'])
sid, proj, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
queries = ctx.get('last_queries', [])[-3:]
files_edited = ctx.get('files_edited', [])
kb_added = ctx.get('kb_added', [])[-3:]
with open(f"{out_dir}/handoff.md", 'w') as f:
    f.write("# Session Handoff (auto-recovered)\n\n")
    f.write(f"## Session\n- ID: {sid}\n- Project: {proj}\n")
    f.write("- Status: Auto-recovered (no /compact ran)\n\n")
    f.write("## Last User Queries\n")
    for i, q in enumerate(queries, 1):
        f.write(f"{i}. {q[:150]}\n")
    f.write("\n## Files Edited\n")
    for fe in files_edited:
        f.write(f"{fe}\n")
    f.write("\n## KB Added This Session\n")
    for ka in kb_added:
        f.write(f"- [{ka.get('finding_type','?')}] {ka.get('content','')[:200]}\n")
    f.write("\n## Resume\n1. kb_list(project) for recent findings\n2. Continue from last user query\n")
PYEOF
                echo "$PREV_SID" > "$HOME/.claude/sessions/resume-${PROJECT}.txt"
                RESUME_FILE="$HOME/.claude/sessions/resume-${PROJECT}.txt"
            fi
        fi
    fi
fi

if [[ -f "$RESUME_FILE" ]]; then
    SESSION_ID=$(cat "$RESUME_FILE")
    HANDOFF="$HOME/.claude/sessions/${SESSION_ID}/handoff.md"
    TASKS="$HOME/.claude/sessions/${SESSION_ID}/tasks.json"

    if [[ -f "$HANDOFF" ]]; then
        # Extract KB checkpoint ID from handoff (source of truth)
        KB_CHECKPOINT=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" | head -1)

        # Extract review status from handoff
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
