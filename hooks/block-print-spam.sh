#!/bin/bash
# PreToolUse hook for Bash
# Blocks heredocs that are too long or mostly print statements

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null) || true

if [[ "$TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null) || true

# If we couldn't parse the command, allow it through
if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Check for any heredoc (python, bash, etc) - match ANY delimiter
# Skip git commit commands (heredocs are the recommended way to pass commit messages)
if echo "$COMMAND" | grep -qE "git\s+(-[A-Za-z]+\s+\S+\s+)*commit" 2>/dev/null; then
    exit 0
fi
if echo "$COMMAND" | grep -qE "<<\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?" 2>/dev/null; then
    # Extract the delimiter
    DELIM=$(echo "$COMMAND" | grep -oE "<<\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?" 2>/dev/null | head -1 | sed "s/<<\s*['\"]*//" | sed "s/['\"]$//") || true

    # If we got a valid delimiter, count lines
    if [[ -n "$DELIM" ]]; then
        # Count lines in heredoc (use fixed string matching to avoid regex issues)
        HEREDOC_LINES=$(echo "$COMMAND" | sed -n "/<<.*${DELIM}/,/^${DELIM}\$/p" 2>/dev/null | wc -l) || true

        if [[ "$HEREDOC_LINES" -gt 5 ]]; then
            echo "WARNING: Heredoc is $HEREDOC_LINES lines. Use Jupyter MCP or Write a script file instead. Commentary belongs in your text response." >&2
            exit 2
        fi
    fi
fi

# Check if this is python code (heredoc OR -c) with mostly print statements
if echo "$COMMAND" | grep -qE "python3?\s+(-c|<<)" 2>/dev/null; then
    PRINT_COUNT=$(echo "$COMMAND" | grep -c "print(" 2>/dev/null) || PRINT_COUNT=0
    # Exclude common non-logic lines (comments, prints, imports, docstrings, whitespace, delimiters, f-strings of literals)
    # Actual computation: assignments with expressions, function calls that aren't print, loops, conditionals
    CODE_LINES=$(echo "$COMMAND" | grep -vE '^\s*(#|print\(|import |from |"""|'"'"''"'"''"'"'|\s*$|[A-Z]+$)' 2>/dev/null | wc -l) || CODE_LINES=0

    # Warn (not block) if prints dominate - avoids sibling tool call cascades
    if [[ "$PRINT_COUNT" -gt 5 ]] && [[ "$CODE_LINES" -lt 10 ]]; then
        echo "WARNING: Python script has $PRINT_COUNT print() calls but only $CODE_LINES lines of logic. Put formatted output in your text response."
        exit 0
    fi

    if [[ "$PRINT_COUNT" -gt 2 ]] && [[ "$PRINT_COUNT" -gt "$CODE_LINES" ]]; then
        echo "WARNING: Python script has $PRINT_COUNT print() calls but only $CODE_LINES lines of actual code. Output text belongs in your response."
        exit 0
    fi
fi

exit 0
