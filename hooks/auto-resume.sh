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

# PTY-keyed resume file only (project-wide fallback removed: multi-agent cwd makes it unsafe)
RESUME_FILE=""
if [[ -n "$TERM_ID" ]]; then
    RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TERM_ID}.txt"
fi

# Check if resume file exists
if [[ -z "$RESUME_FILE" || ! -f "$RESUME_FILE" ]]; then
    exit 0  # No resume state, let normal processing happen
fi

SESSION_ID=$(cat "$RESUME_FILE")
HANDOFF="$CLAUDE_DIR/sessions/${SESSION_ID}/handoff.md"

if [[ ! -f "$HANDOFF" ]]; then
    exit 0
fi

# Phase 4: identity gate — resolve current session's bridge-id, compare to handoff's bridge_id
_resolve_bridge_id_ar() {
    local sid="$1"
    local result=""
    if [[ -n "$AGENT_ID" ]]; then
        result="$AGENT_ID"
    elif [[ -n "$sid" ]]; then
        local pin_file="$PWD/.claude/.persona/session-$sid"
        if [[ -f "$pin_file" ]]; then
            local persona
            persona=$(cat "$pin_file" 2>/dev/null | tr -d '[:space:]')
            case "$persona" in
                archie) result="architect" ;;
                tip)    result="theorem-prover" ;;
                pip)    result="secular-constraints" ;;
                pip3)   result="pip3" ;;
                emmy)   result="emitter" ;;
                *)      result="$persona" ;;
            esac
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

MY_BRIDGE_ID=$(_resolve_bridge_id_ar "${CLAUDE_SESSION_ID:-}")

HANDOFF_BRIDGE_ID=$(python3 -c "
import re, sys
try:
    content = open('$HANDOFF').read()
    m = re.match(r'^---\s*\nbridge_id:\s*(\S+)', content)
    print(m.group(1) if m else 'legacy-unknown')
except:
    print('legacy-unknown')
" 2>/dev/null)
[[ -z "$HANDOFF_BRIDGE_ID" ]] && HANDOFF_BRIDGE_ID="legacy-unknown"

# Gate: if bridge_id doesn't match, warn and inject nothing
if [[ "$MY_BRIDGE_ID" == "unknown" || "$HANDOFF_BRIDGE_ID" == "unknown" || "$HANDOFF_BRIDGE_ID" == "legacy-unknown" || "$HANDOFF_BRIDGE_ID" != "$MY_BRIDGE_ID" ]]; then
    echo "A handoff for ${HANDOFF_BRIDGE_ID} exists; your identity is ${MY_BRIDGE_ID}. Run /persona to pin identity; do not adopt other agents' work."
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
4. If no plan was shown, ~/.local/bin/kb search "" -p "$PROJECT" for context and continue the last task
5. After resuming, run: rm $RESUME_FILE
6. Do NOT ask "What would you like to work on?" — just continue.

BEGIN RESUME
EOF
