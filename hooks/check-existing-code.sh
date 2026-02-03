#!/bin/bash
# PreToolUse hook for Edit/Write
# Searches codebase for similar implementations before allowing edits

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
NEW_CONTENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('new_string','') or json.load(sys.stdin).get('tool_input',{}).get('content',''))" 2>/dev/null)

# Extract function/class/struct names being created
NAMES=$(echo "$NEW_CONTENT" | grep -oE "(def |fn |func |function |class |struct |impl )[a-zA-Z_][a-zA-Z0-9_]*" | sed 's/^def //;s/^fn //;s/^func //;s/^function //;s/^class //;s/^struct //;s/^impl //' | head -5)

if [[ -z "$NAMES" ]]; then
    exit 0
fi

# Get project root
if git rev-parse --show-toplevel &>/dev/null; then
    ROOT=$(git rev-parse --show-toplevel)
else
    ROOT=$(pwd)
fi

# Search for existing implementations
FOUND=""
for NAME in $NAMES; do
    # Skip very short names
    if [[ ${#NAME} -lt 4 ]]; then
        continue
    fi

    MATCHES=$(rg -l "(def |fn |func |function |class |struct |impl )$NAME" "$ROOT" --type py --type rust --type js --type ts 2>/dev/null | grep -v "$FILE_PATH" | head -3)
    if [[ -n "$MATCHES" ]]; then
        FOUND="$FOUND\n$NAME already exists in:\n$MATCHES"
    fi
done

if [[ -n "$FOUND" ]]; then
    echo "WARNING: Similar code may already exist in codebase:"
    echo -e "$FOUND"
    echo ""
    echo "Check these files before reimplementing. If this is intentional, proceed."
fi

exit 0
