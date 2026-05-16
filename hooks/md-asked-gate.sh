#!/bin/bash
# PostToolUse hook on AskUserQuestion. Sets a per-session flag the
# block-markdown-files.sh hook honors. Also sets a session-agnostic flag so
# the gate works regardless of session_id propagation.
#
# We do NOT inspect the user's answer; "asked at all" is the gate. If user
# declined the question, Claude must respect that response regardless.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "AskUserQuestion" ] && exit 0

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

# Per-session flag (when session_id is provided)
if [ -n "$SESSION_ID" ]; then
    : > "/tmp/claude-md-allow-${SESSION_ID}"
fi

# Session-agnostic flag, time-bounded. block-markdown-files.sh checks mtime
# within a recent window (15 minutes) so the consent persists for the rest of
# the user's current intent but does NOT leak across days.
: > /tmp/claude-md-allow-any
exit 0
