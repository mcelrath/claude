#!/bin/bash
# SessionStart hook: check for pending session resume
# State lives in beads; this hook provides context recovery hints
source "$(dirname "$0")/lib/claude-env.sh"

if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)

RESUME_FILE=""
[[ -n "$TERM_ID" ]] && RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TERM_ID}.txt"
[[ ! -f "$RESUME_FILE" ]] && RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}.txt"
[[ ! -f "$RESUME_FILE" ]] && exit 0

SESSION_ID=$(cat "$RESUME_FILE")
HANDOFF="$CLAUDE_DIR/sessions/${SESSION_ID}/handoff.md"

# Show recent KB findings
KB_VENV="${KB_VENV:-$HOME/Projects/ai/kb/.venv/bin/python}"
KB_SCRIPT="${KB_SCRIPT:-$HOME/Projects/ai/kb/kb.py}"
KB_RECENT=""
if [[ -f "$KB_SCRIPT" && -f "$KB_VENV" ]]; then
    KB_RECENT=$("$KB_VENV" "$KB_SCRIPT" list --project="$PROJECT" --limit=3 2>/dev/null | grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' | head -5 | tr '\n' ' ')
fi

# Show open beads epics
OPEN_EPICS=$(bd list --type epic --status open --json 2>/dev/null | python3 -c "
import sys, json
try:
    epics = json.load(sys.stdin)
    for e in epics[:3]:
        print(f\"  - {e['id']}: {e.get('title','')}\")
except:
    pass
" 2>/dev/null)

# Show in-progress work
IN_PROGRESS=$(bd list --status=in_progress --json 2>/dev/null | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)
    for i in items[:5]:
        print(f\"  - {i['id']}: {i.get('title','')}\")
except:
    pass
" 2>/dev/null)

echo "RESUME: Previous session $SESSION_ID"
[[ -f "$HANDOFF" ]] && echo "  Handoff: $HANDOFF"

KB_CHECKPOINT=""
[[ -f "$HANDOFF" ]] && KB_CHECKPOINT=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" | head -1)
[[ -n "$KB_CHECKPOINT" ]] && echo "  KB Checkpoint: $KB_CHECKPOINT (SOURCE OF TRUTH)"
[[ -n "$KB_RECENT" ]] && echo "  Recent KB ($PROJECT): $KB_RECENT"
[[ -n "$OPEN_EPICS" ]] && echo "  Open plan epics:" && echo "$OPEN_EPICS"
[[ -n "$IN_PROGRESS" ]] && echo "  In progress:" && echo "$IN_PROGRESS"

echo ""
echo "RESUME INSTRUCTIONS:"
[[ -f "$HANDOFF" ]] && echo "- Read $HANDOFF for full context"
echo "- Run: bd ready  (find available work)"
echo "- Run: bd list --status=in_progress  (your active work)"
echo "- Run: kb_list(project=\"$PROJECT\") for recent findings"
echo "- After resuming, run: rm $RESUME_FILE"
echo "- Do NOT ask 'What would you like to work on?' — just continue."
