#!/bin/bash
# PreToolUse hook for Bash. Blocks Bash commands that create or rename to .md
# files when the per-turn md-allow flag is not set. Closes the heredoc /
# tee / mv-to-md workaround for the Write-side hook.
#
# Detection (regex on the command string):
#   > x.md        — redirect output
#   >> x.md       — append redirect
#   tee x.md      — tee
#   mv X y.md     — rename to .md (always suspect)
#   cp X y.md     — copy to .md (always suspect)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# Quick pre-check: does the command mention .md at all?
if [[ "$CMD" != *.md* ]]; then
    exit 0
fi

# Honor the per-turn allow flag (set by md-asked-gate.sh when Claude calls
# AskUserQuestion). Also check the session-agnostic flag with a 15-min
# window so a single AskUserQuestion confirmation covers a batch of
# related .md operations.
FLAG="/tmp/claude-md-allow-${SESSION_ID}"
[ -e "$FLAG" ] && exit 0
ANY_FLAG=/tmp/claude-md-allow-any
if [ -e "$ANY_FLAG" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$ANY_FLAG" 2>/dev/null || echo 0)
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt 900 ]; then
        exit 0
    fi
fi

# Regex patterns that indicate .md creation/rename.
SUSPECT=0
if [[ "$CMD" =~ \>\>?[[:space:]]*[^\|\&\;\<\>]*\.md([[:space:]]|$|\;|\&|\|) ]]; then SUSPECT=1; fi
if [[ "$CMD" =~ (^|[[:space:]\;\&\|])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[^[:space:]]+\.md([[:space:]]|$|\;|\&|\|) ]]; then SUSPECT=1; fi
if [[ "$CMD" =~ (^|[[:space:]\;\&\|])(mv|cp)[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+\.md([[:space:]]|$|\;|\&|\|) ]]; then SUSPECT=1; fi

[ "$SUSPECT" = "0" ] && exit 0

cat >&2 <<EOF
BLOCKED: This Bash command would create or rename to a .md file.

Before creating a markdown file, use AskUserQuestion to confirm with the user. AskUserQuestion is the canonical user-intent capture mechanism; once you have called it this turn, the hook will allow the operation.

If the content is a summary, status, recap, or analysis: it does not belong in a markdown file. Put it in your conversation response, beads (bd create), or kb (kb_add).
EOF
exit 2
