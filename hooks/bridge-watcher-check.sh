#!/bin/bash
# Dual-event hook for bridge integration:
#
#   PreToolUse (Bash) — call `bridge recv` to drain any unread peer
#     messages. If any, BLOCK the tool call (exit 2) with content in
#     stderr; the block channel reliably surfaces. Claude re-issues
#     the tool call; recv now returns empty; hook exits 0; tool proceeds.
#     One-round-trip cost per bridge update batch. The bridge store IS
#     the source of truth — no daemon/log needed.
#
#   UserPromptSubmit — same drain pattern but surface via stdout
#     (UserPromptSubmit stdout is injected as system-reminder).
#
# Why not use the daemon's watcher.log? In nohup mode the daemon
# accumulates duplicate "unread_at_launch" wake headers without
# advancing the bridge cursor, causing thrash. `bridge recv` reads
# from the bridge store directly and advances the cursor atomically.

if [ ! -x "$HOME/.agent-bridge/bridge" ]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)

WHOAMI=$("$HOME/.agent-bridge/bridge" whoami 2>/dev/null)
ID=$(echo "$WHOAMI" | sed -nE 's/^Effective identity:\s*(\S+).*$/\1/p')
[ -z "$ID" ] && exit 0

# Drain unread. `bridge recv` prints all unread messages addressed to
# the reader and advances the cursor atomically.
UNREAD=$("$HOME/.agent-bridge/bridge" recv "$ID" 2>/dev/null)

# Empty → tool proceeds normally.
[ -z "$UNREAD" ] && exit 0

if [ "$EVENT" = "PreToolUse" ]; then
    cat >&2 <<EOF
BRIDGE_UPDATE: new peer messages received. Re-issue your tool call after reading.

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
