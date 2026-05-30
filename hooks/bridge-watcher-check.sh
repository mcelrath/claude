#!/bin/bash
# Dual-event hook for bridge integration (bridge-quiet design, 2026-05-29):
#
#   `bridge watch` is now the PRIMARY deliverer: on wake it renders message bodies
#   to its task-output AND advances the cursor (drains, identical to `recv`). So this
#   hook normally finds NOTHING and the tool proceeds with NO block.
#
#   PreToolUse (Bash) — NO-OP (exit 0, no drain, no block). Rationale (fix 2026-05-30):
#     a PreToolUse hook that exits 2 BLOCKS the tool call AND the harness CANCELS the
#     whole PARALLEL tool batch (sibling calls die). A peer message arriving between the
#     single-shot watcher's exit and its relaunch used to trigger exactly that, nuking
#     unrelated in-flight work. So PreToolUse never drains/blocks; the watcher
#     (relaunched on every wake, forced at turn-end) + the UserPromptSubmit path below
#     are the deliverers. No message is lost; no tool batch is ever cancelled.
#
#   UserPromptSubmit — same drain, surfaced via stdout (injected as system-reminder).
#
# The bridge store IS the source of truth. `bridge recv` advances the cursor
# atomically; the watcher advances it identically (jq .id | tail -n1).

if [ ! -x "$HOME/.agent-bridge/bridge" ]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

# NON-BLOCKING on PreToolUse: a PreToolUse hook exit-2 blocks the call AND cancels the
# whole parallel tool batch. NEVER do that for a bridge message — exit 0 immediately,
# WITHOUT draining (so the message stays unread for the watcher to deliver). The watcher
# is relaunched on every wake and forced at turn-end by block-stop-without-bridge-watcher,
# so unread messages surface within the turn; tool batches are never cancelled.
[ "$EVENT" = "PreToolUse" ] && exit 0

# Identity resolution: trust SESSION_ID from Claude's hook input (authoritative,
# unlike subprocess env/cwd). Look up agent in agents.json by session_id directly.
# Fall back to `bridge whoami` only if no match.
AGENTS_FILE="$HOME/.agent-bridge/agents.json"
ID=""
if [ -n "$SESSION_ID" ] && [ -f "$AGENTS_FILE" ]; then
    ID=$(jq -r --arg sid "$SESSION_ID" '.agents[] | select(.session_id == $sid) | .id' "$AGENTS_FILE" 2>/dev/null | head -n1)
fi
if [ -z "$ID" ]; then
    WHOAMI=$("$HOME/.agent-bridge/bridge" whoami 2>/dev/null)
    ID=$(echo "$WHOAMI" | sed -nE 's/^Effective identity:\s*(\S+).*$/\1/p')
fi
case "$ID" in
    ""|"("*) exit 0 ;;
esac

# Drain unread. `bridge recv` prints all unread messages addressed to
# the reader and advances the cursor atomically.
UNREAD=$(AGENT_ID="$ID" "$HOME/.agent-bridge/bridge" recv 2>/dev/null)

# Empty → tool proceeds normally.
[ -z "$UNREAD" ] && exit 0

# Only UserPromptSubmit reaches here (PreToolUse exited above, non-blocking).
# stdout is injected as a system-reminder — no block, no cancellation.
echo "BRIDGE_UPDATE (new peer messages since last user prompt):"
echo "$UNREAD"
echo "(end bridge messages)"
exit 0
