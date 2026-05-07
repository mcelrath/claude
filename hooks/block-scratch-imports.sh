#!/bin/bash
# PreToolUse hook: block edits that import from scratch/ or archive/ in production code.
# Scratch/archive are quarantined historical artifacts. If a result matters, promote
# it to cl44/, scripts/, or proofs/ first.
#
# Fires on: Edit, Write, NotebookEdit, mcp__jupyter__modify_notebook_cells
# Exit 2 = BLOCK the tool call.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null) || true

case "$TOOL_NAME" in
    Edit)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('new_string',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null) || true
        ;;
    Write)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('content',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null) || true
        ;;
    NotebookEdit)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('new_source',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('notebook_path',''))" 2>/dev/null) || true
        ;;
    mcp__jupyter__modify_notebook_cells)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('cell_content',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('notebook_path',''))" 2>/dev/null) || true
        ;;
    *) exit 0 ;;
esac

[[ -z "$CODE" ]] && exit 0
[[ -z "$FILE" ]] && exit 0

# If the target file is IN scratch/ or archive/, allow imports (they're peers)
case "$FILE" in
    */scratch/*|*/archive/*) exit 0 ;;
esac

# Check for imports from scratch/ or archive/ in the new content
if echo "$CODE" | grep -qE '^\s*(import\s+scratch|from\s+scratch|import\s+archive|from\s+archive)' 2>/dev/null; then
    cat >&2 <<EOF
BLOCKED: production file '$FILE' imports from scratch/ or archive/.

scratch/ and archive/ are QUARANTINED historical experiments. Production code must not
depend on them.

If the scratch/archive code contains a result worth keeping:
  1. Review the code carefully (it may contain wrong reasoning)
  2. Rewrite it correctly in cl44/, scripts/, or proofs/
  3. Let the scratch/archive file stand as a historical record
  4. Import from the new authoritative location

Or if this import is scaffolding for an active promotion: first move the file to its
final location (git mv), then edit to match.
EOF
    exit 2
fi

# Also check for sys.path manipulations that would allow scratch imports
if echo "$CODE" | grep -qE "sys\.path.*(scratch|archive)" 2>/dev/null; then
    cat >&2 <<EOF
BLOCKED: production file '$FILE' modifies sys.path to include scratch/ or archive/.

These directories are QUARANTINED. Adding them to sys.path in production code allows
quarantined modules to be imported — defeats the isolation.
EOF
    exit 2
fi

exit 0
