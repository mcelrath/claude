#!/bin/bash
# PreCompact hook - extracts session state from JSONL using local LLM
# Creates handoff.md for session resume after compact

LLM_URL="http://localhost:9510/v1/chat/completions"

# Ensure lib directory exists
mkdir -p "$HOME/.claude/hooks/lib"

# Trap to create minimal handoff if script fails
create_minimal_handoff() {
    if [[ -n "$OUT_DIR" && -n "$SESSION_ID" && ! -f "$OUT_DIR/handoff.md" ]]; then
        mkdir -p "$OUT_DIR"
        cat > "$OUT_DIR/handoff.md" << MINEOF
# Session Handoff (Minimal)

## Session
- ID: $SESSION_ID
- Project: ${PROJECT_NAME:-unknown}
- Extracted: $(python3 -c "from datetime import datetime as d;print(d.now().astimezone().isoformat())" 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
- Status: Precompact failed, minimal fallback

## Plan
${PLAN_FILE:-unknown}

## Resume
1. Read current_plan file in this directory
2. kb_search for recent findings
3. TaskList for task state
MINEOF
        source "$HOME/.claude/hooks/lib/get_terminal_id.sh" 2>/dev/null
        _TERM_ID=$(_get_terminal_id 2>/dev/null)
        if [[ -n "$_TERM_ID" ]]; then
            echo "$SESSION_ID" > "$HOME/.claude/sessions/resume-${PROJECT_NAME:-unknown}-${_TERM_ID}.txt" 2>/dev/null
        else
            echo "$SESSION_ID" > "$HOME/.claude/sessions/resume-${PROJECT_NAME:-unknown}.txt" 2>/dev/null
        fi
        echo "PRE-COMPACT: Minimal handoff created (fallback)"
    fi
}
trap create_minimal_handoff EXIT

# Read hook input JSON (may contain session_id)
HOOK_INPUT=$(cat)
HOOK_SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null)

# Get project path (Claude's format: dashes replace slashes)
PROJECT_PATH=$(pwd | sed 's|/|-|g; s|^-||')
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")

# Get CURRENT session ID: prefer hook input, then PPID mapping, then ls -t
STATE_DIR="/tmp/claude-kb-state"
if [[ -n "$HOOK_SESSION_ID" ]]; then
    CURRENT_SESSION_ID="$HOOK_SESSION_ID"
elif [[ -f "$STATE_DIR/session-$PPID" ]]; then
    CURRENT_SESSION_ID=$(cat "$STATE_DIR/session-$PPID")
fi

# Find session JSONL - search ALL projects if we have session ID
FIND_HELPER="$HOME/.claude/hooks/lib/find_session_jsonl.py"

CONTEXT_HELPER="$HOME/.claude/hooks/lib/gather_session_context.py"

if [[ -z "$CURRENT_SESSION_ID" ]]; then
    echo "PRE-COMPACT: RECOVERY NEEDED - No session ID available"
    echo ""
    echo "RECOVERY_CONTEXT_JSON:$(python3 "$CONTEXT_HELPER" 2>/dev/null)"
    echo ""
    echo "Claude: Use AskUserQuestion to ask which session/plan the user was working on."
    echo "Show the sessions and plans from RECOVERY_CONTEXT_JSON in a table."
    exit 1
fi

# Search all projects for this session ID
JSONL=$(python3 "$FIND_HELPER" find "$CURRENT_SESSION_ID" 2>/dev/null)
if [[ -z "$JSONL" || ! -f "$JSONL" ]]; then
    echo "PRE-COMPACT: RECOVERY NEEDED - Session $CURRENT_SESSION_ID not found"
    echo ""
    echo "RECOVERY_CONTEXT_JSON:$(python3 "$CONTEXT_HELPER" 2>/dev/null)"
    echo ""
    echo "Claude: Use AskUserQuestion to ask which session/plan the user was working on."
    exit 1
fi

echo "PRE-COMPACT: Found session $CURRENT_SESSION_ID in $(dirname "$JSONL" | xargs basename)"

# SESSION_ID from JSONL filename (consistent source)
SESSION_ID=$(basename "$JSONL" .jsonl)
OUT_DIR="$HOME/.claude/sessions/$SESSION_ID"
mkdir -p "$OUT_DIR"

# Use Python helper with error handling for task extraction
CONTEXT_JSON=$(python3 "$HOME/.claude/hooks/lib/extract_session_state.py" "$JSONL" 2>/dev/null)
CONTEXT_JSON=${CONTEXT_JSON:-'{"messages":[],"tasks":[],"kb_ids":[]}'}

# Detect active agent team
TEAM_CONFIG=$(ls -t "$HOME/.claude/teams"/*/config.json 2>/dev/null | head -1)
if [[ -n "$TEAM_CONFIG" && -f "$TEAM_CONFIG" ]]; then
    TEAM_NAME=$(python3 -c "import json; d=json.load(open('$TEAM_CONFIG')); print(d.get('name','unknown'))" 2>/dev/null)
    TEAM_MEMBERS=$(python3 -c "
import json
d=json.load(open('$TEAM_CONFIG'))
for m in d.get('members', d.get('teammates', [])):
    name = m.get('name', m) if isinstance(m, dict) else str(m)
    print(f'  - {name}')
" 2>/dev/null)
fi

# Extract tasks to file (for session resume)
if command -v jq &>/dev/null; then
    echo "$CONTEXT_JSON" | jq -c '.tasks // []' > "$OUT_DIR/tasks.json"
else
    echo '[]' > "$OUT_DIR/tasks.json"
fi

# Extract all session data from context
KB_IDS=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d.get('kb_ids',[])[:20]))" 2>/dev/null)
KB_COUNT=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('kb_ids',[])))" 2>/dev/null)
KB_SUPERSEDED=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d.get('kb_superseded',[])))" 2>/dev/null)
KB_ADDED=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for e in d.get('kb_added', [])[-3:]:
    print(f\"- [{e.get('finding_type','?')}] {e.get('content','')[:200]}\")
" 2>/dev/null)
FILES_READ=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f) for f in d.get('files_read',[])[:15]]" 2>/dev/null)
FILES_EDITED=$(echo "$CONTEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f) for f in d.get('files_edited',[])]" 2>/dev/null)
LAST_QUERIES=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
queries = d.get('last_queries', [])
for i, q in enumerate(queries[-3:], 1):
    print(f'{i}. {q[:150]}')
" 2>/dev/null)

# Extract expert review state
REVIEW_SUMMARY=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
launches = d.get('review_launches', [])
verdicts = d.get('review_verdicts', [])
if not launches and not verdicts:
    print('No expert review this session')
else:
    if verdicts:
        print(f'Last verdict: {verdicts[-1]} ({len(verdicts)} total)')
    for r in launches[-3:]:
        print(f\"  - {r.get('type','?')}: {r.get('description','')[:80]}\")
" 2>/dev/null)

# Get plan file: ONLY from current_plan (set when plan is created/edited)
# Do NOT grep JSONL - it finds plan mentions that aren't the actual work
if [[ -f "$OUT_DIR/current_plan" ]]; then
    PLAN_FILE=$(cat "$OUT_DIR/current_plan" | sed 's|.*/plans/|plans/|')
else
    PLAN_FILE=""  # No plan = no plan (don't guess)
fi

# Extract plan approval status if plan exists
PLAN_APPROVAL=""
if [[ -n "$PLAN_FILE" ]]; then
    FULL_PLAN="$HOME/.claude/$PLAN_FILE"
    if [[ -f "$FULL_PLAN" ]]; then
        PLAN_APPROVAL=$(grep -A5 "## Approval Status" "$FULL_PLAN" 2>/dev/null | head -5)
    fi
fi

# Build LLM request for session summary
if command -v jq &>/dev/null; then
    # Include last queries and KB added in context for better summary
    LLM_CONTEXT=$(echo "$CONTEXT_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
out = {
    'last_queries': d.get('last_queries',[]),
    'kb_added': d.get('kb_added',[]),
    'files_edited': d.get('files_edited',[]),
    'review_verdicts': d.get('review_verdicts',[]),
    'review_count': len(d.get('review_launches',[]))
}
print(json.dumps(out))
" 2>/dev/null)
    REQUEST=$(jq -n \
      --arg ctx "$LLM_CONTEXT" \
      --arg plan "${PLAN_FILE:-none}" \
      '{
        model: "GLM-4.7-Flash-Q4_K_M.gguf",
        messages: [
          {role: "system", content: "Summarize session for handoff. Output ONLY valid JSON."},
          {role: "user", content: "Session data:\n\($ctx)\nPlan: \($plan)\n\nOutput JSON: {\"summary\": \"1-2 sentence description of what was being worked on\", \"current_task\": \"specific task in progress\", \"next_steps\": [\"2-3 items\"], \"blockers\": []}"}
        ],
        max_tokens: 300,
        temperature: 0.3
      }')
else
    REQUEST='{"model":"GLM-4.7-Flash-Q4_K_M.gguf","messages":[{"role":"system","content":"Summarize session."},{"role":"user","content":"Output: {\"summary\":\"unknown\",\"current_task\":\"unknown\",\"next_steps\":[],\"blockers\":[]}"}],"max_tokens":300}'
fi

# Call local LLM to generate summary
# Note: GLM model may put JSON in reasoning_content instead of content
SUMMARY=$(curl -s --max-time 30 "$LLM_URL" \
    -H "Content-Type: application/json" \
    -d "$REQUEST" 2>/dev/null | \
    python3 -c "
import sys,json
r=json.load(sys.stdin)
msg=r.get('choices',[{}])[0].get('message',{})
content=msg.get('content','') or msg.get('reasoning_content','{}')
print(content)
" 2>/dev/null)

# Default if LLM fails
if [[ -z "$SUMMARY" || "$SUMMARY" == "{}" ]]; then
    SUMMARY='{"current_task": "unknown", "key_decisions": [], "next_steps": ["Check TaskList", "kb_search for context"], "blockers": []}'
fi

# Write handoff
cat > "$OUT_DIR/handoff.md.tmp" << EOF
# Session Handoff

## Session
- ID: $SESSION_ID
- Project: $PROJECT_NAME
- Extracted: $(python3 -c "from datetime import datetime as d;print(d.now().astimezone().isoformat())" 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

## Last User Queries
${LAST_QUERIES:-[none captured]}

## Plan
${PLAN_FILE:-none}
${PLAN_APPROVAL:+
## Plan Approval
$PLAN_APPROVAL}

${TEAM_NAME:+## Agent Team: $TEAM_NAME
$TEAM_MEMBERS
Note: Teammates do not survive /compact. Spawn fresh if needed.
}
## Expert Review
${REVIEW_SUMMARY:-No expert review this session}

## State (LLM-summarized)
\`\`\`json
$SUMMARY
\`\`\`

## Files Edited
${FILES_EDITED:-[none]}

## Files Read
${FILES_READ:-[none]}

## KB Added This Session
${KB_ADDED:-[none]}

## KB Queried (${KB_COUNT:-0} total, showing first 20)
${KB_IDS:-[none]}

## KB Superseded
${KB_SUPERSEDED:-[none]}

## Resume
1. Review LLM summary above for context
2. kb_list(project="$PROJECT_NAME") - KB findings are the source of truth
3. Review tasks.json for CONTEXT only - DO NOT auto-create tasks (often stale)
4. Summarize actual work done based on KB findings
5. Continue from last user query
EOF

# Atomic commit
mv "$OUT_DIR/handoff.md.tmp" "$OUT_DIR/handoff.md"

# Get terminal-specific ID (PTY from /proc walk, falls back to CLAUDE_SESSION env)
source "$HOME/.claude/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)
if [[ -n "$TERM_ID" ]]; then
    echo "$SESSION_ID" > "$HOME/.claude/sessions/resume-${PROJECT_NAME}-${TERM_ID}.txt"
else
    # Fallback to project-wide (may have conflicts with concurrent sessions)
    echo "$SESSION_ID" > "$HOME/.claude/sessions/resume-${PROJECT_NAME}.txt"
fi

echo "PRE-COMPACT: State saved (LLM-summarized)"
echo "  Handoff: $OUT_DIR/handoff.md"
echo "  Tasks: $OUT_DIR/tasks.json"
echo "  KB findings: $(echo $KB_IDS | wc -w)"
