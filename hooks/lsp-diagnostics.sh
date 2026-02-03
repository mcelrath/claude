#!/bin/bash
# PostToolUse hook: Run LSP diagnostics after Edit/Write
# Returns errors via additionalContext so Claude sees them immediately

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

# Exit silently if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# Make path absolute
[[ "$FILE_PATH" != /* ]] && FILE_PATH="$CWD/$FILE_PATH"

# Exit if file doesn't exist
[[ ! -f "$FILE_PATH" ]] && exit 0

# Determine language from extension
EXT="${FILE_PATH##*.}"
DIAGNOSTICS=""

case "$EXT" in
    py)
        # Python: use pyright for diagnostics, fallback to py_compile for syntax
        if command -v pyright &>/dev/null; then
            RESULT=$(pyright --outputjson "$FILE_PATH" 2>/dev/null || true)
            if [[ -n "$RESULT" ]]; then
                # Only show errors, limit to 10, truncate long messages
                ERRORS=$(echo "$RESULT" | jq -r '
                    [.generalDiagnostics[]? | select(.severity == "error")] | .[0:10][] |
                    "\(.file | split("/") | .[-1]):\(.range.start.line + 1): \(.message[0:100])"
                ' 2>/dev/null || true)
                [[ -n "$ERRORS" ]] && DIAGNOSTICS="$ERRORS"
            fi
        else
            # Fallback: py_compile for basic syntax checking
            ERRORS=$(python3 -m py_compile "$FILE_PATH" 2>&1 || true)
            [[ -n "$ERRORS" ]] && DIAGNOSTICS="$ERRORS"
        fi
        ;;

    cpp|hpp|c|h|cc|cxx|hxx|cu|hip)
        # C++: use compile_commands.json to get flags, then run clang -fsyntax-only
        # Find compile_commands.json by walking up directories
        DIR=$(dirname "$FILE_PATH")
        COMPILE_DB=""
        while [[ "$DIR" != "/" ]]; do
            if [[ -f "$DIR/compile_commands.json" ]]; then
                COMPILE_DB="$DIR/compile_commands.json"
                break
            fi
            DIR=$(dirname "$DIR")
        done

        if [[ -n "$COMPILE_DB" ]]; then
            # Extract compile command for this file
            BASENAME=$(basename "$FILE_PATH")
            COMPILE_CMD=$(jq -r --arg file "$FILE_PATH" --arg basename "$BASENAME" '
                .[] | select(.file == $file or (.file | endswith($basename))) | .command // .arguments
            ' "$COMPILE_DB" 2>/dev/null | head -1)

            if [[ -n "$COMPILE_CMD" && "$COMPILE_CMD" != "null" ]]; then
                # Get directory for the compile command
                COMPILE_DIR=$(jq -r --arg file "$FILE_PATH" --arg basename "$BASENAME" '
                    .[] | select(.file == $file or (.file | endswith($basename))) | .directory
                ' "$COMPILE_DB" 2>/dev/null | head -1)

                # Convert command to syntax-only check
                if [[ "$COMPILE_CMD" == "["* ]]; then
                    COMPILE_CMD=$(echo "$COMPILE_CMD" | jq -r '. | join(" ")' 2>/dev/null)
                fi

                # Replace the output file option and add -fsyntax-only
                SYNTAX_CMD=$(echo "$COMPILE_CMD" | sed 's/-o [^ ]*/-fsyntax-only/' | sed 's/-c /-fsyntax-only /')

                # Run syntax check (timeout after 10 seconds)
                if [[ -n "$COMPILE_DIR" && -d "$COMPILE_DIR" ]]; then
                    ERRORS=$(cd "$COMPILE_DIR" && timeout 10 bash -c "$SYNTAX_CMD" 2>&1 | grep -E "error:|warning:" | head -20 || true)
                else
                    ERRORS=$(timeout 10 bash -c "$SYNTAX_CMD" 2>&1 | grep -E "error:|warning:" | head -20 || true)
                fi
                [[ -n "$ERRORS" ]] && DIAGNOSTICS="$ERRORS"
            fi
        fi

        # Fallback: basic clang/g++ syntax check if no compile_commands.json or file not found in it
        if [[ -z "$DIAGNOSTICS" ]]; then
            COMPILER=""
            if command -v clang++ &>/dev/null; then
                COMPILER="clang++"
            elif command -v g++ &>/dev/null; then
                COMPILER="g++"
            fi
            if [[ -n "$COMPILER" ]]; then
                # Basic syntax check - won't catch project-specific include errors
                ERRORS=$(timeout 5 $COMPILER -fsyntax-only -x c++ "$FILE_PATH" 2>&1 | grep -E "error:|warning:" | head -10 || true)
                [[ -n "$ERRORS" ]] && DIAGNOSTICS="$ERRORS"
            fi
        fi
        ;;

    rs)
        # Rust: use cargo check for the workspace
        # Find Cargo.toml by walking up directories
        DIR=$(dirname "$FILE_PATH")
        CARGO_DIR=""
        while [[ "$DIR" != "/" ]]; do
            if [[ -f "$DIR/Cargo.toml" ]]; then
                CARGO_DIR="$DIR"
                break
            fi
            DIR=$(dirname "$DIR")
        done

        if [[ -n "$CARGO_DIR" ]]; then
            # Run cargo check with JSON output (timeout after 30 seconds for incremental)
            RESULT=$(cd "$CARGO_DIR" && timeout 30 cargo check --message-format=json 2>/dev/null || true)
            if [[ -n "$RESULT" ]]; then
                # Extract errors from JSON output
                ERRORS=$(echo "$RESULT" | jq -r '
                    select(.reason == "compiler-message") |
                    .message | select(.level == "error" or .level == "warning") |
                    "\(.spans[0]?.file_name // "unknown"):\(.spans[0]?.line_start // 0): \(.level): \(.message)"
                ' 2>/dev/null | head -20 || true)
                [[ -n "$ERRORS" ]] && DIAGNOSTICS="$ERRORS"
            fi
        fi
        ;;
esac

# Output result
if [[ -n "$DIAGNOSTICS" ]]; then
    # Return diagnostics as additionalContext
    jq -n --arg diag "$DIAGNOSTICS" '{
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": ("LSP Diagnostics:\n" + $diag)
        }
    }'
else
    # No errors - return empty JSON
    echo '{}'
fi

exit 0
