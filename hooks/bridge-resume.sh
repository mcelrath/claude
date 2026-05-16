#!/bin/bash
# SessionStart hook: restore bridge registration and drain pending messages.
#
# Three invariants maintained across compaction:
#   1. Agent is announced (registry shows correct session_id + role).
#   2. Pending messages are drained (bridge recv) so nothing is missed.
#   3. A single bridge watch is running for this agent (background watcher).
#
# Identity resolution: bridge whoami reads AGENT_ID env, then CLAUDE_SESSION_ID,
# then cwd. SessionStart hooks run in the correct cwd with CLAUDE_SESSION_ID set,
# so cwd-based resolution works without explicit AGENT_ID.

BRIDGE="$HOME/.agent-bridge/bridge"
[[ ! -x "$BRIDGE" ]] && exit 0

# Resolve agent id
AGENT_ID=$("$BRIDGE" whoami 2>/dev/null | grep "^Effective identity:" | awk '{print $3}')
[[ -z "$AGENT_ID" ]] && exit 0

# Read current registry entry to get role/focus for re-announce
AGENTS_JSON="$HOME/.agent-bridge/agents.json"
if [[ -f "$AGENTS_JSON" ]]; then
    ROLE=$(python3 -c "
import sys, json
try:
    agents = json.load(open('$AGENTS_JSON'))
    a = agents.get('$AGENT_ID', {})
    print(a.get('role', ''))
except: pass
" 2>/dev/null)
    FOCUS=$(python3 -c "
import sys, json
try:
    agents = json.load(open('$AGENTS_JSON'))
    a = agents.get('$AGENT_ID', {})
    print(a.get('focus', ''))
except: pass
" 2>/dev/null)
    OFFERING=$(python3 -c "
import sys, json
try:
    agents = json.load(open('$AGENTS_JSON'))
    a = agents.get('$AGENT_ID', {})
    print(a.get('offering', ''))
except: pass
" 2>/dev/null)
fi

# Re-announce to update session_id in registry (compaction changes session_id)
if [[ -n "$ROLE" ]]; then
    "$BRIDGE" announce \
        --id "$AGENT_ID" \
        --role "$ROLE" \
        --focus "${FOCUS:-resumed after compaction}" \
        --offering "${OFFERING:-}" \
        --directed "checking bridge for missed messages" \
        </dev/null 2>/dev/null
fi

# Drain pending messages (print to stdout so SessionStart context shows them)
PENDING=$("$BRIDGE" recv "$AGENT_ID" 2>/dev/null)
if [[ -n "$PENDING" ]]; then
    echo "BRIDGE RESUME [$AGENT_ID]: pending messages:"
    echo "$PENDING"
fi

# Kill any stale watcher for this agent, launch a fresh one
PIDFILE="$HOME/.agent-bridge/${AGENT_ID}.watcher.pid"
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    [[ -n "$OLD_PID" ]] && kill "$OLD_PID" 2>/dev/null
    rm -f "$PIDFILE"
fi

# Launch fresh watcher in background (setsid so it survives hook process exit)
setsid "$BRIDGE" watch "$AGENT_ID" </dev/null >/dev/null 2>&1 &
echo "BRIDGE RESUME [$AGENT_ID]: watcher relaunched (pid $!)"
