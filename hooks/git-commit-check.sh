#!/bin/bash
# Enforce git commit flags
# PostToolUse hook for Bash commands containing "git commit"

TOOL_INPUT="$CLAUDE_TOOL_INPUT"

# Only check git commit commands
if [[ "$TOOL_INPUT" != *"git commit"* ]]; then
    exit 0
fi

# Check for forbidden patterns
if [[ "$TOOL_INPUT" == *"git commit"* && "$TOOL_INPUT" != *"--no-gpg-sign"* ]]; then
    echo "WARNING: git commit should use --no-gpg-sign"
fi

exit 0
