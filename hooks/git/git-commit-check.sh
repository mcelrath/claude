#!/bin/bash
# Enforce git commit flags
# PostToolUse hook for Bash commands containing "git commit"

# Read the command from stdin JSON (the current hook API). The old
# $CLAUDE_TOOL_INPUT env var is no longer populated by the harness, so this
# hook was a no-op until fixed (wired by kb-bp4 P1).
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print((json.load(sys.stdin).get('tool_input') or {}).get('command',''))" 2>/dev/null)

# Only check git commit commands
[[ "$CMD" != *"git commit"* ]] && exit 0

if [[ "$CMD" != *"--no-gpg-sign"* ]]; then
    echo "WARNING: git commit should use --no-gpg-sign"
fi

exit 0
