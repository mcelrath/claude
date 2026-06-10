#!/bin/bash
# PostToolUse hook on AskUserQuestion. Arms a short-lived per-session bypass flag
# that guard-destructive-git.sh honors (10-minute window). Mirrors md-asked-gate.sh,
# but registered on the CORRECT event (PostToolUse / AskUserQuestion) so the flag is
# set when the human actually answers a question — not at compaction time.
#
# We do NOT inspect the answer; "the human was asked at all" is the gate. The guard
# requires the agent to first state what will be discarded, so the AskUserQuestion
# the human sees is about the destructive op.
#
# Flag: timestamp file at /tmp/claude-gitdestruct-allow-${SESSION_ID}; the guard
# checks mtime against a 10-minute window. Per-session (no cross-agent leak).

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "AskUserQuestion" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -n "$SESSION_ID" ] && : > "/tmp/claude-gitdestruct-allow-${SESSION_ID}"
exit 0
