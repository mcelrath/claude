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
if echo "$COMMAND" | grep -qE "<<\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?" 2>/dev/null; then
    # Extract the delimiter
    DELIM=$(echo "$COMMAND" | grep -oE "<<\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?" 2>/dev/null | head -1 | sed "s/<<\s*['\"]*//" | sed "s/['\"]$//") || true

    # If we got a valid delimiter, count lines
    if [[ -n "$DELIM" ]]; then
        # Count lines in heredoc (use fixed string matching to avoid regex issues)
        HEREDOC_LINES=$(echo "$COMMAND" | sed -n "/<<.*${DELIM}/,/^${DELIM}\$/p" 2>/dev/null | wc -l) || true

        if [[ "$HEREDOC_LINES" -gt 5 ]]; then
            echo "BLOCKED: Heredoc is $HEREDOC_LINES lines." >&2
            echo "For quick calculations: use Jupyter MCP (setup_notebook, query_notebook, modify_notebook_cells)." >&2
            echo "For permanent code: Write a script in lib/ or exploration/." >&2
            echo "If Jupyter server not running: Write a script file instead." >&2
            echo "Import existing lib/ functions - don't reimplement." >&2
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

    # Block if: (>5 prints with <10 logic) OR (prints dominate: >2 prints and prints > code)
    if [[ "$PRINT_COUNT" -gt 5 ]] && [[ "$CODE_LINES" -lt 10 ]]; then
        echo "BLOCKED: Python script has $PRINT_COUNT print() calls but only $CODE_LINES lines of logic." >&2
        echo "This is formatted output, not computation. Write it directly in your response text." >&2
        exit 2
    fi

    if [[ "$PRINT_COUNT" -gt 2 ]] && [[ "$PRINT_COUNT" -gt "$CODE_LINES" ]]; then
        echo "BLOCKED: Python script has $PRINT_COUNT print() calls but only $CODE_LINES lines of actual code." >&2
        echo "Output text belongs in your response, not in a script. Just write the table/text directly." >&2
        exit 2
    fi
fi

exit 0
