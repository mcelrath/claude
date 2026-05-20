#!/bin/bash
# PostToolUse hook on AskUserQuestion. Sets a per-session flag the
# block-markdown-files.sh hook honors. The flag is a timestamp file; the
# block-markdown hook checks mtime against a 1-hour window.
#
# We do NOT inspect the user's answer; "asked at all" is the gate. If user
# declined the question, Claude must respect that response regardless.
#
# Flag semantics: timestamp file at /tmp/claude-md-allow-${SESSION_ID}.
# Within 1 hour of the latest AskUserQuestion in this session, .md creation
# is allowed (subject to the reflex-pattern hard block, which is unconditional).
# The session-agnostic /tmp/claude-md-allow-any flag has been retired — it
# leaked across worktree agents and produced false "agent escape" suspicions.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "AskUserQuestion" ] && exit 0

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

# Per-session timestamp flag. The block-markdown hook checks mtime.
if [ -n "$SESSION_ID" ]; then
    : > "/tmp/claude-md-allow-${SESSION_ID}"
fi
exit 0
