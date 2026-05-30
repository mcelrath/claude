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

# Bridge protocol — injected into the MAIN session's context only. SessionStart
# hooks do not fire for sub-agents, so this is the canonical home for the bridge
# mandate: it lives HERE and intentionally NOT in CLAUDE.md, so sub-agents (which
# read CLAUDE.md as "user instructions") never ingest it and never touch the bridge.
cat <<'BRIDGEDOC'
BRIDGE PROTOCOL (main session only — sub-agents never run bridge commands; they return results to their dispatcher):
- You MUST be on the bridge. Keep `~/.agent-bridge/bridge watch <your-id>` running via run_in_background=true at ALL times. It is single-shot: it exits on each wake, so relaunch it after EVERY wake AND at the end of EVERY turn. A trailing `&` is NOT equivalent — it fires no task-notification and is reaped when the call returns; only run_in_background=true creates the tracked task that wakes you. Idle/done is the MOST important time to be watching ("done with my task" != "done on the bridge"). If `bridge agents` would show you offline, you broke this.
- `bridge send` is synchronous — never run_in_background. Put the message body on stdin via heredoc. Never pipe bridge output through head/tail/awk/sed.
- After every compaction: `bridge recv` -> `bridge announce` -> relaunch `bridge watch` (run_in_background, no `&`).
BRIDGEDOC

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

# Clean any stale watcher pidfile. Do NOT launch a watcher here: a setsid
# launch detaches it from the Claude session (PPID=1), so its exit won't
# fire a task-notification — defeating the proactive-wake mechanism. The
# alive-check hook (bridge-watcher-alive.sh) will emit BRIDGE_WATCHER_DOWN
# on the first prompt/tool call, prompting Claude to launch it via
# run_in_background=true (Claude-session sibling, task-notification on exit).
PIDFILE="$HOME/.agent-bridge/${AGENT_ID}.watcher.pid"
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    [[ -n "$OLD_PID" ]] && kill "$OLD_PID" 2>/dev/null
    rm -f "$PIDFILE"
fi
echo "BRIDGE RESUME [$AGENT_ID]: pidfile cleared. Launch watcher via run_in_background=true on first tool call (alive-check will remind)."
