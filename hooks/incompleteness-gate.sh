#!/bin/bash
# PreToolUse hook for Bash — blocks git commit if staged changes have
# incompleteness markers without corresponding bd issues
source "$(dirname "$0")/lib/claude-env.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# Only fire on git commit commands
echo "$COMMAND" | grep -qE '^\s*git\s+commit\b' || exit 0

# Get staged diff (added lines only)
STAGED_DIFF=$(git diff --cached --unified=0 2>/dev/null) || exit 0
[[ -z "$STAGED_DIFF" ]] && exit 0

# Scan staged additions for incompleteness markers
FOUND=$(echo "$STAGED_DIFF" | python3 -c "
import sys, re

diff = sys.stdin.read()
markers = []
current_file = ''
current_line = 0
skip_file = False

skip_patterns = ['.md', 'hooks/', 'CLAUDE.md', 'MEMORY.md', 'memory/']

for line in diff.split('\n'):
    if line.startswith('diff --git'):
        m = re.search(r' b/(.+)$', line)
        if m:
            current_file = m.group(1)
            skip_file = any(p in current_file for p in skip_patterns)
    elif line.startswith('@@'):
        m = re.search(r'\+(\d+)', line)
        if m:
            current_line = int(m.group(1))
    elif line.startswith('+') and not line.startswith('+++') and not skip_file:
        content = line[1:]
        patterns = [
            (r'\bTODO\b', 'TODO'),
            (r'\bFIXME\b', 'FIXME'),
            (r'\bXXX\b', 'XXX'),
            (r'\bHACK\b', 'HACK'),
            (r'\bSTUB\b', 'STUB'),
            (r'assert\s*\(\s*false\s*\)', 'assert(false)'),
            (r'raise\s+NotImplementedError', 'NotImplementedError'),
            (r'unimplemented!\s*\(\s*\)', 'unimplemented!()'),
            (r'panic!\s*\(\s*\"not implemented', 'panic-not-implemented'),
            (r'\bsorry\b', 'sorry'),
            (r'\badmit\b', 'admit'),
            (r'\bplaceholder\b', 'placeholder'),
            (r'\bnative_decide\b', 'native_decide'),
            (r'\bdbg_trace\b', 'dbg_trace'),
            (r'decreasing_by\s+sorry', 'decreasing_by-sorry'),
        ]
        for pat, name in patterns:
            if re.search(pat, content):
                markers.append(f'{current_file}:{current_line}:{name}:{content.strip()}')
        current_line += 1
    elif not line.startswith('-'):
        current_line += 1

for m in markers:
    print(m)
" 2>/dev/null)

[[ -z "$FOUND" ]] && exit 0

# Batch check: get all bd issues once, grep locally
BD_ISSUES=$(bd list --json 2>/dev/null | python3 -c "
import sys, json
try:
    issues = json.load(sys.stdin)
    for i in issues:
        t = i.get('title','') + ' ' + i.get('description','')
        print(t.lower())
except:
    pass
" 2>/dev/null)

UNTRACKED=""
COUNT=0
while IFS= read -r marker; do
    FILE="${marker%%:*}"
    REST="${marker#*:}"
    LINE="${REST%%:*}"
    REST2="${REST#*:}"
    TYPE="${REST2%%:*}"
    CONTENT="${REST2#*:}"

    # Check if any bd issue references this file+marker
    SEARCH_TERM=$(echo "$FILE $TYPE" | tr '[:upper:]' '[:lower:]')
    if ! echo "$BD_ISSUES" | grep -qi "$TYPE" 2>/dev/null; then
        UNTRACKED="${UNTRACKED}  - ${FILE}:${LINE}: ${TYPE} — ${CONTENT}\n"
        COUNT=$((COUNT + 1))
    fi
done <<< "$FOUND"

[[ -z "$UNTRACKED" ]] && exit 0

{
  echo "BLOCKED: Committing incomplete code without tracking."
  echo "Found: $COUNT incompleteness markers in staged changes:"
  echo -e "$UNTRACKED"
  echo ""
  echo "For each, either:"
  echo "  1. Fix it now (remove the marker by completing the work)"
  echo "  2. Create a follow-up: bd create -t task \"Complete {description}\" -p P2"
  echo "Then retry the commit."
} >&2
exit 2
