#!/bin/bash
# PreCompact hook - extracts session state for resume after compact
# Creates handoff.md with KB findings, git status, files edited
# Plan state lives in beads — no plan files to track
source "$(dirname "$0")/lib/claude-env.sh"

mkdir -p "$CLAUDE_DIR/hooks/lib"

# Trap to create minimal handoff if script fails
create_minimal_handoff() {
    if [[ -n "$OUT_DIR" && -n "$SESSION_ID" && ! -f "$OUT_DIR/handoff.md" ]]; then
        mkdir -p "$OUT_DIR"
        cat > "$OUT_DIR/handoff.md" << MINEOF
# Session Handoff (Minimal)
- ID: $SESSION_ID
- Project: ${PROJECT_NAME:-unknown}
- Extracted: $(date +%Y-%m-%dT%H:%M:%S)
- Status: Precompact failed, minimal fallback
MINEOF
        source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh" 2>/dev/null
        _TERM_ID=$(_get_terminal_id 2>/dev/null)
        if [[ -n "$_TERM_ID" ]]; then
            echo "$SESSION_ID" > "$CLAUDE_DIR/sessions/resume-${PROJECT_NAME:-unknown}-${_TERM_ID}.txt" 2>/dev/null
        else
            echo "$SESSION_ID" > "$CLAUDE_DIR/sessions/resume-${PROJECT_NAME:-unknown}.txt" 2>/dev/null
        fi
        echo "PRE-COMPACT: Minimal handoff created (fallback)"
    fi
}
trap create_minimal_handoff EXIT

HOOK_INPUT=$(cat)
HOOK_SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null)

PROJECT_PATH=$(pwd | sed 's|/|-|g; s|^-||')
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")

STATE_DIR="/tmp/claude-kb-state"
if [[ -n "$HOOK_SESSION_ID" ]]; then
    CURRENT_SESSION_ID="$HOOK_SESSION_ID"
elif [[ -f "$STATE_DIR/session-$PPID" ]]; then
    CURRENT_SESSION_ID=$(cat "$STATE_DIR/session-$PPID")
fi

FIND_HELPER="$CLAUDE_DIR/hooks/lib/find_session_jsonl.py"
CONTEXT_HELPER="$CLAUDE_DIR/hooks/lib/gather_session_context.py"

if [[ -z "$CURRENT_SESSION_ID" ]]; then
    echo "PRE-COMPACT: RECOVERY NEEDED - No session ID available"
    echo "RECOVERY_CONTEXT_JSON:$(python3 "$CONTEXT_HELPER" 2>/dev/null)"
    exit 1
fi

JSONL=$(python3 "$FIND_HELPER" find "$CURRENT_SESSION_ID" 2>/dev/null)
if [[ -z "$JSONL" || ! -f "$JSONL" ]]; then
    echo "PRE-COMPACT: RECOVERY NEEDED - Session $CURRENT_SESSION_ID not found"
    echo "RECOVERY_CONTEXT_JSON:$(python3 "$CONTEXT_HELPER" 2>/dev/null)"
    exit 1
fi

SESSION_ID=$(basename "$JSONL" .jsonl)
OUT_DIR="$CLAUDE_DIR/sessions/$SESSION_ID"
mkdir -p "$OUT_DIR"

CONTEXT_JSON=$(python3 "$CLAUDE_DIR/hooks/lib/extract_session_state.py" "$JSONL" 2>/dev/null)
CONTEXT_JSON=${CONTEXT_JSON:-'{"messages":[],"tasks":[],"kb_ids":[]}'}

# Detect active agent team
TEAM_STATE=""
for tc in "$CLAUDE_DIR/teams"/*/config.json; do
    [[ -f "$tc" ]] || continue
    tc_session=$(python3 -c "import json; print(json.load(open('$tc')).get('leadSessionId',''))" 2>/dev/null)
    if [[ "$tc_session" == "$SESSION_ID" || "$tc_session" == "$CURRENT_SESSION_ID" ]]; then
        TEAM_STATE=$(python3 - "$tc" << 'PYEOF'
import json, sys, glob, os
cfg = json.load(open(sys.argv[1]))
lines = [f"## Agent Team: {cfg.get('name', 'unknown')}"]
for m in cfg.get('members', []):
    lines.append(f"  - {m['name']} ({m.get('agentType','?')}, {m.get('model','?')})")
print('\n'.join(lines))
PYEOF
)
        break
    fi
done

# Extract session data
KB_IDS=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d.get('kb_ids',[])[-20:]))" 2>/dev/null)
KB_COUNT=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('kb_ids',[])))" 2>/dev/null)
KB_ADDED=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for e in d.get('kb_added', [])[-3:]:
    print(f\"- [{e.get('finding_type','?')}] {e.get('content','')[:500]}\")
" 2>/dev/null)
FILES_EDITED=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f) for f in d.get('files_edited',[])]" 2>/dev/null)
LAST_QUERIES=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for i, q in enumerate(d.get('last_queries', [])[-3:], 1):
    print(f'{i}. {q[:500]}')
" 2>/dev/null)
REVIEW_SUMMARY=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
verdicts = d.get('review_verdicts', [])
if verdicts:
    print(f'Last verdict: {verdicts[-1]} ({len(verdicts)} verdicts this session)')
else:
    print('No expert review this session')
" 2>/dev/null)

GIT_LOG=$(git log --oneline -5 2>/dev/null)
GIT_UNCOMMITTED=$(git status --short 2>/dev/null | grep -v '^?' | head -10)

# Beads state snapshot
BEADS_IN_PROGRESS=$(bd list --status=in_progress --json 2>/dev/null | python3 -c "
import sys,json
try:
    items = json.load(sys.stdin)
    for i in items[:5]:
        print(f\"- {i['id']}: {i.get('title','')}\")
except:
    pass
" 2>/dev/null)

SUMMARY=$(python3 "$CLAUDE_DIR/hooks/lib/summarize_session.py" "$JSONL" "none" "$LLM_URL" 2>/dev/null)
if ! echo "$SUMMARY" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    SUMMARY='{"summary":"LLM unavailable","current_task":"unknown","next_steps":["kb_list for context"],"blockers":[]}'
fi

cat > "$OUT_DIR/handoff.md.tmp" << EOF
# Session Handoff

## Session
- ID: $SESSION_ID
- Project: $PROJECT_NAME
- Extracted: $(date +%Y-%m-%dT%H:%M:%S)

## Last User Queries
${LAST_QUERIES:-[none captured]}

## Beads In Progress
${BEADS_IN_PROGRESS:-[none]}

${TEAM_STATE}

## Expert Review
${REVIEW_SUMMARY:-No expert review this session}

## State (LLM-summarized)
\`\`\`json
$SUMMARY
\`\`\`

## Git Status
Recent commits:
${GIT_LOG:-[no git history]}

Uncommitted changes:
${GIT_UNCOMMITTED:-[none]}

## Files Edited
${FILES_EDITED:-[none]}

## KB Added This Session
${KB_ADDED:-[none]}

## KB Queried (${KB_COUNT:-0} total, showing last 20)
${KB_IDS:-[none]}

## Resume
1. Read this handoff for context
2. Run: bd ready (find available work)
3. Run: bd list --status=in_progress (active work)
4. kb_list(project="$PROJECT_NAME") for session findings
5. Continue from last user query — do NOT ask what to work on
EOF

mv "$OUT_DIR/handoff.md.tmp" "$OUT_DIR/handoff.md"

source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)
if [[ -n "$TERM_ID" ]]; then
    echo "$SESSION_ID" > "$CLAUDE_DIR/sessions/resume-${PROJECT_NAME}-${TERM_ID}.txt"
else
    echo "$SESSION_ID" > "$CLAUDE_DIR/sessions/resume-${PROJECT_NAME}.txt"
fi

echo "PRE-COMPACT: State saved"
echo "  Handoff: $OUT_DIR/handoff.md"
echo "  KB findings: $(echo $KB_IDS | wc -w)"
