#!/bin/bash
# PreCompact hook — write a per-TTY resume pointer (TTY -> last session id) so
# the SessionStart resume hook can surface this agent's in-progress beads after
# compaction.
#
# handoff.md is DEPRECATED (kb-bp4, user decision 2026-06-08): the model's own
# compaction summary covers the narrative, so a separate handoff doc is
# redundant. Resume state = (1) drain peer/bridge mail, (2) check this agent's
# claimed beads — already codified in session-persona.sh's RESUME PROTOCOL,
# bridge-resume.sh, and CLAUDE.md "Resume". The kb checkpoint is handled by
# kb-precompact.sh. This hook now only maintains the resume pointer.
source "$HOME/.claude/hooks/lib/claude-env.sh"

HOOK_INPUT=$(cat)
HOOK_SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null)

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")

source "$HOME/.claude/hooks/lib/state.sh"
if [[ -n "$HOOK_SESSION_ID" ]]; then
    CURRENT_SESSION_ID="$HOOK_SESSION_ID"
elif [[ -f "$STATE_DIR/session-$PPID" ]]; then
    CURRENT_SESSION_ID=$(cat "$STATE_DIR/session-$PPID")
fi
[[ -z "$CURRENT_SESSION_ID" ]] && exit 0

source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)
if [[ -n "$TERM_ID" ]]; then
    echo "$CURRENT_SESSION_ID" > "$CLAUDE_DIR/sessions/resume-${PROJECT_NAME}-${TERM_ID}.txt"
fi
echo "PRE-COMPACT: resume pointer saved (handoff.md deprecated; resume = bridge mail + claimed beads)"
