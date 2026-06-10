#!/bin/bash
# Stop hook. Clear the per-turn md allow flag.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0
rm -f "/tmp/claude-md-allow-${SESSION_ID}" 2>/dev/null
exit 0
