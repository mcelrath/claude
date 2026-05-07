#!/bin/bash
# PreToolUse hook: quarantine scratch/ and archive/ paths from Read/Grep/Glob.
# These are historical artifacts, not authoritative sources. Solid results live in
# cl44/, proofs/, scripts/, sections/, or docs/.
#
# Fires on: Read, Grep, Glob
# Exit 2 = BLOCK the tool call with a message directing to authoritative sources.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null) || true

case "$TOOL_NAME" in
    Read)
        PATH_ARG=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null) || true
        ;;
    Grep)
        PATH_ARG=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null) || true
        ;;
    Glob)
        PATH_ARG=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('pattern','') or json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null) || true
        ;;
    *) exit 0 ;;
esac

[[ -z "$PATH_ARG" ]] && exit 0

# Quarantine: paths matching scratch/ or archive/ (case-insensitive).
# Allow explicit opt-in via the word "HISTORY" in a nearby comment — not easily detectable
# here, so instead allow explicit Bash invocation (which bypasses this hook anyway).
if echo "$PATH_ARG" | grep -qiE '(^|/)(scratch|archive)(/|$|\*)'; then
    cat >&2 <<EOF
QUARANTINED: path '$PATH_ARG' matches scratch/ or archive/.

These directories hold historical experiments. They are NOT authoritative sources.
Solid results live in:
  - cl44/          production Python modules
  - proofs/        Lean theorems (0 sorry = trusted)
  - scripts/       verified production scripts
  - sections/      LaTeX drafts
  - docs/          reference documentation

If the user explicitly asked you to read historical content, use Bash 'cat'/'ls' with
an explicit path to bypass this gate — but prefer to find the corresponding result in
an authoritative location first.
EOF
    exit 2
fi

exit 0
