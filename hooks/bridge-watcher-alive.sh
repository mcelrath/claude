#!/bin/bash
# UserPromptSubmit + PreToolUse Bash hook: check that `bridge watch` is
# alive for this agent. If not, emit a reminder for Claude to launch one
# as a run_in_background=true Bash task.
#
# The bridge watch process must be a sibling of the Claude session so its
# exit fires a task-notification (which is the proactive-wake mechanism).
# Liveness is tracked via pidfile written by bridge watch on entry.

if [ ! -x "$HOME/.agent-bridge/bridge" ]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)

# Identity resolution: trust the SESSION_ID from Claude's hook input (it's
# authoritative — Claude Code's own session id, not something derived from
# the hook subprocess's env or cwd, both of which can disagree with reality).
# Look up the agent in agents.json by session_id directly. Fall back to
# `bridge whoami` only if session_id is missing or unmatched.
AGENTS_FILE="$HOME/.agent-bridge/agents.json"
ID=""
if [ -n "$SESSION_ID" ] && [ -f "$AGENTS_FILE" ]; then
    ID=$(jq -r --arg sid "$SESSION_ID" '.agents[] | select(.session_id == $sid) | .id' "$AGENTS_FILE" 2>/dev/null | head -n1)
fi
if [ -z "$ID" ]; then
    # Fallback path: bridge whoami uses its own resolution (AGENT_ID env,
    # CLAUDE_SESSION_ID env, then cwd). Less reliable in hook context.
    WHOAMI=$("$HOME/.agent-bridge/bridge" whoami 2>/dev/null)
    ID=$(echo "$WHOAMI" | sed -nE 's/^Effective identity:\s*(\S+).*$/\1/p')
fi
case "$ID" in
    ""|"("*) exit 0 ;;
esac
PID_FILE="$HOME/.agent-bridge/${ID}.watcher.pid"
SENTINEL="/tmp/claude-bridge-reminded-${SESSION_ID}-${ID}"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # Watcher alive — clear the "already reminded" sentinel so the
        # next death-cycle triggers a fresh reminder.
        rm -f "$SENTINEL" 2>/dev/null
        exit 0
    fi
    rm -f "$PID_FILE" 2>/dev/null
fi

# Watcher dead. Emit reminder. The same message goes via stdout (UserPromptSubmit
# injects as system-reminder, reliably surfaced) AND via stderr on a blocking
# exit (PreToolUse exit-2 stderr is the only reliable way to surface to Claude
# on a Bash tool call). The sentinel ensures only the FIRST Bash call per
# death-cycle blocks — subsequent calls pass through so Claude isn't blocked
# from doing other work after the reminder lands.
MSG="BRIDGE_WATCHER_DOWN: no \`bridge watch\` running for agent '$ID'.
Between turns, peer messages will not wake you proactively — they only
surface on your next tool call or user prompt via the synchronous hook.
To enable proactive wakes, launch in run_in_background=true:
  ~/.agent-bridge/bridge watch $ID
The watcher exits on the next peer message; relaunch it then to receive
the wake AFTER that. AGENTS.md documents the full launch+relaunch cycle."

# UserPromptSubmit: stdout becomes system-reminder. Always emit; reliable.
if [ "$EVENT" = "UserPromptSubmit" ]; then
    echo "$MSG"
    exit 0
fi

# PreToolUse: block (exit 2) only once per watcher death-cycle.
if [ -f "$SENTINEL" ]; then
    exit 0
fi
: > "$SENTINEL"
echo "$MSG" >&2
exit 2
