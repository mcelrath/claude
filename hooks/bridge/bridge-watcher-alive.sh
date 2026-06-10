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

# (#3) Recent-exit suppression: if the watcher exited cleanly less than ~10s
# ago, suppress the nag.  The exit trap in `bridge watch` touches
# `${ID}.last_watcher_exit` on every clean shutdown.  This gives the agent
# room to relaunch in its next tool call without an immediate spurious nag
# claiming the watcher is down.
EXIT_FILE="$HOME/.agent-bridge/${ID}.last_watcher_exit"
if [ -f "$EXIT_FILE" ]; then
    EXIT_AGE=$(( $(date +%s) - $(stat -c %Y "$EXIT_FILE" 2>/dev/null || echo 0) ))
    if [ "$EXIT_AGE" -lt 10 ]; then
        exit 0
    fi
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
RELAUNCH ONLY after a watcher-completion (task) notification — that is when the
single-shot watcher exited on a wake. Do NOT relaunch at the end of every turn, and
NOT while a watcher is already alive: it stays alive polling between messages, so an
extra relaunch spawns a redundant concurrent poller (these accumulate into a leak).
One live watcher covers you until it next exits. See AGENTS.md for the cycle."

# UserPromptSubmit: stdout becomes system-reminder. Always emit; reliable.
if [ "$EVENT" = "UserPromptSubmit" ]; then
    echo "$MSG"
    exit 0
fi

# PreToolUse: warn (exit 0) — downgraded from exit 2 (block) per user request 2026-05-25.
# The watcher exits after each message by design; blocking every tool call was disruptive.
if [ -f "$SENTINEL" ]; then
    exit 0
fi
: > "$SENTINEL"
echo "$MSG" >&2
exit 0
