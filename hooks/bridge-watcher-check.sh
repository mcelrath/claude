#!/bin/bash
# Dual-event hook for bridge integration (bridge-quiet design, 2026-05-29):
#
#   `bridge watch` is now the PRIMARY deliverer: on wake it renders message bodies
#   to its task-output AND advances the cursor (drains, identical to `recv`). So this
#   hook normally finds NOTHING and the tool proceeds with NO block.
#
#   PreToolUse (Bash) — `bridge recv` drains. Common case: empty (the watcher already
#     drained) → exit 0, tool proceeds, no block. Non-empty ONLY for messages the
#     watcher MISSED while it was DOWN; those are surfaced via the exit-2 block (the
#     only reliable PreToolUse channel), framed as BRIDGE_WATCHER_DOWN + relaunch
#     advice. So the hook only speaks up when the watcher isn't running.
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

if [ "$EVENT" = "PreToolUse" ]; then
    cat >&2 <<EOF
BRIDGE_WATCHER_DOWN (missed messages): these arrived while no 'bridge watch' was
running, so the watcher did not deliver them (they are now drained). Relaunch the
watcher as its OWN Bash call (run_in_background=true, no '&') so future messages wake
you via its task-output without blocking your tool calls.

$UNREAD

(end bridge messages)
EOF
    exit 2
fi

# UserPromptSubmit: stdout is injected as system-reminder.
echo "BRIDGE_UPDATE (new peer messages since last user prompt):"
echo "$UNREAD"
echo "(end bridge messages)"
exit 0
