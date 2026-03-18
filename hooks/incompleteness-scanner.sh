#!/bin/bash
# PostToolUse hook for Edit/Write — warns on incompleteness markers in new content
# Non-blocking (exit 0): stubs are legitimate during implementation
source "$(dirname "$0")/lib/claude-env.sh"

STATE_DIR="/tmp/claude-kb-state"
mkdir -p "$STATE_DIR"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

[[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]] && exit 0

# Extract only the NEW content being written (not pre-existing file content)
NEW_CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
tn = d.get('tool_name', '')
if tn == 'Edit':
    print(ti.get('new_string', ''))
elif tn == 'Write':
    print(ti.get('content', ''))
" 2>/dev/null)

[[ -z "$NEW_CONTENT" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Skip hook config files
[[ "$FILE_PATH" == *"/hooks/"* ]] && exit 0
[[ "$FILE_PATH" == *"/CLAUDE.md" ]] && exit 0
[[ "$FILE_PATH" == *"/memory/"* ]] && exit 0
[[ "$FILE_PATH" == *"/MEMORY.md" ]] && exit 0

# Session ID for state tracking
SESSION_ID="${CLAUDE_SESSION_ID:-$(cat /tmp/claude-kb-state/session-$PPID 2>/dev/null || echo unknown)}"
MARKER_FILE="$STATE_DIR/${SESSION_ID}-incomplete-markers"

# Scan for incompleteness markers
MARKERS=$(echo "$NEW_CONTENT" | python3 -c "
import sys, re

lines = sys.stdin.readlines()
markers = []

code_patterns = [
    (r'\bTODO\b', 'TODO'),
    (r'\bFIXME\b', 'FIXME'),
    (r'\bXXX\b', 'XXX'),
    (r'\bHACK\b', 'HACK'),
    (r'\bSTUB\b', 'STUB'),
    (r'assert\s*\(\s*false\s*\)', 'assert(false)'),
    (r'raise\s+NotImplementedError', 'NotImplementedError'),
    (r'unimplemented!\s*\(\s*\)', 'unimplemented!()'),
    (r'panic!\s*\(\s*\"not implemented', 'panic-not-implemented'),
    (r'pass\s+#', 'python-stub'),
]

lean_patterns = [
    (r'\bsorry\b', 'sorry'),
    (r'\badmit\b', 'admit'),
    (r'\bplaceholder\b', 'placeholder'),
    (r'\bnative_decide\b', 'native_decide'),
    (r'\bdbg_trace\b', 'dbg_trace'),
    (r'decreasing_by\s+sorry', 'decreasing_by-sorry'),
    (r'\baxiom\b', 'axiom'),
]

for i, line in enumerate(lines, 1):
    for pat, name in code_patterns + lean_patterns:
        if re.search(pat, line):
            markers.append(f'{i}:{name}:{line.rstrip()}')

for m in markers:
    print(m)
" 2>/dev/null)

[[ -z "$MARKERS" ]] && exit 0

# Record markers and warn
WARNINGS=""
while IFS= read -r marker; do
    LINENO_M="${marker%%:*}"
    REST="${marker#*:}"
    TYPE="${REST%%:*}"
    CONTENT="${REST#*:}"
    echo "$FILE_PATH:$LINENO_M:$TYPE:$CONTENT" >> "$MARKER_FILE"
    WARNINGS="${WARNINGS}INCOMPLETENESS: $TYPE at $FILE_PATH:$LINENO_M — $CONTENT\n"
done <<< "$MARKERS"

echo -e "$WARNINGS"
echo "Create follow-up issues for any intentional stubs: bd create -t task '{description}'"
exit 0
