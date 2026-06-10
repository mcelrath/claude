#!/bin/bash
# SessionStart hook: check for pending session resume
# State lives in beads; this hook provides context recovery hints
source "$HOME/.claude/hooks/lib/claude-env.sh"

if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)

# PTY-keyed resume file only (project-wide fallback removed: multi-agent cwd makes it unsafe)
RESUME_FILE=""
[[ -n "$TERM_ID" ]] && RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TERM_ID}.txt"
[[ -z "$RESUME_FILE" || ! -f "$RESUME_FILE" ]] && exit 0

SESSION_ID=$(cat "$RESUME_FILE")

# Resolve this session's bridge-id (used to scope in-progress beads to THIS agent).
_resolve_bridge_id() {
    local sid="$1"
    local result=""
    if [[ -n "$AGENT_ID" ]]; then
        result="$AGENT_ID"
    elif [[ -n "$sid" ]]; then
        local pin_file="$PWD/.claude/.persona/session-$sid"
        if [[ -f "$pin_file" ]]; then
            # The persona name IS the bridge id (no mapping layer — kb-bp4 P7).
            result=$(cat "$pin_file" 2>/dev/null | tr -d '[:space:]')
        fi
    fi
    if [[ -z "$result" && -n "$sid" && -f "$HOME/.agent-bridge/agents.json" ]]; then
        result=$(python3 -c "
import json
try:
    d = json.load(open('$HOME/.agent-bridge/agents.json'))
    sid = '$sid'
    a = next((x for x in d.get('agents', []) if x.get('session_id','') in (sid, sid[:8])), None)
    print(a['id'] if a else '')
except: pass
" 2>/dev/null)
    fi
    echo "${result:-unknown}"
}

MY_BRIDGE_ID=$(_resolve_bridge_id "${CLAUDE_SESSION_ID:-}")

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

# Show in-progress work — scope to this agent's assignee, plus count others'
IN_PROGRESS=""
OTHERS_COUNT=0
if [[ "$MY_BRIDGE_ID" != "unknown" ]]; then
    MY_IN_PROGRESS=$(bd list --status=in_progress --assignee="$MY_BRIDGE_ID" --json 2>/dev/null | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)
    for i in items[:5]:
        print(f\"  - {i['id']}: {i.get('title','')}\")
except:
    pass
" 2>/dev/null)
    OTHERS_COUNT=$(bd list --status=in_progress --json 2>/dev/null | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)
    mine = [x for x in items if x.get('assignee','') == '$MY_BRIDGE_ID']
    print(len(items) - len(mine))
except:
    print(0)
" 2>/dev/null)
    IN_PROGRESS="$MY_IN_PROGRESS"
    [[ "${OTHERS_COUNT:-0}" -gt 0 ]] && IN_PROGRESS="${IN_PROGRESS}"$'\n'"  (${OTHERS_COUNT} other agents' in-progress items not shown)"
else
    IN_PROGRESS=$(bd list --status=in_progress --json 2>/dev/null | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)
    for i in items[:5]:
        print(f\"  - {i['id']}: {i.get('title','')}\")
except:
    pass
" 2>/dev/null)
fi

echo "RESUME: Previous session $SESSION_ID"
[[ -n "$KB_RECENT" ]] && echo "  Recent KB ($PROJECT): $KB_RECENT"
[[ -n "$OPEN_EPICS" ]] && echo "  Open plan epics:" && echo "$OPEN_EPICS"
[[ -n "$IN_PROGRESS" ]] && echo "  In progress:" && echo "$IN_PROGRESS"

echo ""
echo "RESUME INSTRUCTIONS (handoff.md deprecated — resume = drain bridge mail, then your claimed beads):"
if [[ "$MY_BRIDGE_ID" != "unknown" ]]; then
    echo "- Run: bd list --assignee=$MY_BRIDGE_ID --status=in_progress  (YOUR active work)"
    echo "- Run: bd list --ready --no-assignee  (unassigned work — claim before working)"
else
    echo "- Run: bd list --status=in_progress  (all active work — identity unknown, run /persona first)"
fi
echo "- Run: ~/.local/bin/kb list -p \"$PROJECT\"  (recent findings; MCP kb_list removed 2026-05-19)"
echo "- After resuming, run: rm $RESUME_FILE"
echo "- Do NOT ask 'What would you like to work on?' — just continue."
