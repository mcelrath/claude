#!/bin/bash
# PreToolUse hook for Write
# Blocks creation of .md files unless explicitly in filename from user

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if [[ "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [[ "$FILE_PATH" == *.md ]]; then
    # Allow plan files in .claude/plans directory
    if [[ "$FILE_PATH" == */.claude/plans/*.md ]]; then
        exit 0
    fi
    # Allow agent and command definitions, and rules
    if [[ "$FILE_PATH" == */.claude/agents/*.md ]] || [[ "$FILE_PATH" == */.claude/commands/*.md ]] || [[ "$FILE_PATH" == */.claude/rules/*.md ]]; then
        exit 0
    fi
    # Allow docs/reference for relocated CLAUDE.md content
    if [[ "$FILE_PATH" == */docs/reference/*.md ]]; then
        exit 0
    fi
    # Allow CLAUDE.md files (project configuration)
    if [[ "$FILE_PATH" == */CLAUDE.md ]] || [[ "$FILE_PATH" == */.claude/CLAUDE.md ]]; then
        exit 0
    fi
    echo "BLOCKED: Creating markdown file '$FILE_PATH'."
    echo "Write the content directly in your response instead."
    echo "Only create .md files if user explicitly requested one."
    exit 2
fi

exit 0
