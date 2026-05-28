#!/bin/bash
# Stop hook: block a REGISTERED bridge agent from ending its turn while its
# `bridge watch` is dead. Forces a relaunch so the agent stays reachable by
# its driver. This closes the "responded to user, dropped off the bridge" gap
# that the PreToolUse/UserPromptSubmit reminder (bridge-watcher-alive.sh)
# cannot catch — at Stop there is no further tool call to surface a reminder on.
#
# Safety: only fires for sessions whose session_id is registered in
# agents.json (normal Claude sessions are NEVER blocked). A consecutive-block
# counter escapes after 3 blocks so a genuinely stuck agent is not hard-locked.
#
# Exit 2 = BLOCK the stop (stderr shown to the agent, which then continues).

[ -x "$HOME/.agent-bridge/bridge" ] || exit 0

INPUT=$(cat 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

AGENTS_FILE="$HOME/.agent-bridge/agents.json"
[ -f "$AGENTS_FILE" ] || exit 0

# Resolve THIS session's bridge id by session_id (authoritative, from Claude's
# hook input). If this session is not a registered bridge agent, NEVER block.
ID=""
if [ -n "$SESSION_ID" ]; then
    ID=$(jq -r --arg sid "$SESSION_ID" '.agents[] | select(.session_id == $sid) | .id' "$AGENTS_FILE" 2>/dev/null | head -n1)
fi
case "$ID" in
    ""|"("*|-*) exit 0 ;;   # not a registered bridge agent -> do not block
esac

CTR="/tmp/claude-bridge-stopblock-${SESSION_ID}-${ID}"

# Watcher alive? -> allow stop, reset the block counter.
PID_FILE="$HOME/.agent-bridge/${ID}.watcher.pid"
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        rm -f "$CTR" 2>/dev/null
        exit 0
    fi
    rm -f "$PID_FILE" 2>/dev/null
fi

# Watcher dead. Loop-safety: cap consecutive blocks at 3, then escape with a
# loud warning so the agent is not permanently prevented from stopping.
N=0
[ -f "$CTR" ] && N=$(cat "$CTR" 2>/dev/null || echo 0)
case "$N" in (*[!0-9]*) N=0 ;; esac
N=$((N + 1))
echo "$N" > "$CTR"

if [ "$N" -gt 3 ]; then
    echo "BRIDGE_WATCHER_DOWN (stop allowed after 3 blocks): still no live 'bridge watch $ID'. You are OFF the bridge and your driver cannot reach you. Relaunch '~/.agent-bridge/bridge watch $ID' with the run_in_background: true parameter as soon as you can." >&2
    rm -f "$CTR" 2>/dev/null
    exit 0
fi

echo "BRIDGE_WATCHER_DOWN: do NOT end your turn yet — no live \`bridge watch $ID\` is running, so you would go SILENT on the bridge and your driver's instructions would never reach you.
Relaunch the watcher NOW as its own Bash call using the harness run_in_background: true parameter (a trailing '&' is NOT equivalent and will not create the wake channel):
  ~/.agent-bridge/bridge watch $ID
Then end your turn. Keeping the bridge up is required AT ALL TIMES, including when you are done with your task — \"done with my task\" is not \"done on the bridge\" (see AGENTS.md)." >&2
exit 2
