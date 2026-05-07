#!/bin/bash
# PreToolUse hook: require annotation on trace / einsum contractions.
# Positive framing: state which subspace the trace is over, then compute.
#
# Fires on: Edit, Write, NotebookEdit, mcp__jupyter__modify_notebook_cells, Bash (heredocs)
# Warns (exit 0) — does not block. The prompt surfaces it for the agent.

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
    Bash)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null) || true
        FILE=""
        echo "$CODE" | grep -qE "python|heredoc|EOF" || exit 0
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

# Skip non-physics files
if [[ -n "$FILE" ]]; then
    case "$FILE" in
        */.claude/*|*/hooks/*|*/settings.json|*.md|*.txt|*.yaml|*.yml|*.toml|*.cfg|*.ini)
            exit 0 ;;
        */test_*|*_test.py|*/tests/*)
            exit 0 ;;
    esac
fi

# Look for trace / einsum contraction patterns
TRACE_PATTERNS=(
    'np\.trace\('
    'mpmath\.?\.trace\('
    'Matrix\.trace'
    '\.trace\(\)'
    'einsum\s*\(\s*[\047"][^\047"]*([a-z])[^\047"]*\1[^\047"]*[\047"]'
)

TRACE_FOUND=""
for pat in "${TRACE_PATTERNS[@]}"; do
    if echo "$CODE" | grep -qE "$pat" 2>/dev/null; then
        TRACE_FOUND="yes"
        break
    fi
done

[[ -z "$TRACE_FOUND" ]] && exit 0

# Check for annotation: '# trace over: {subspace}' near the trace call.
# We look for the phrase anywhere in the new content (being lenient).
if echo "$CODE" | grep -qE '#\s*trace\s+over\s*:' 2>/dev/null; then
    exit 0
fi

# No annotation — print a soft warning
cat >&2 <<EOF
TRACE ANNOTATION RECOMMENDED:
Detected np.trace / Matrix.trace / einsum contraction without a '# trace over: {subspace}' comment.

Positive-framing discipline: before computing, state which subspace the trace is over.
Example:
    # trace over: Q=-1 fermion sector (sector-restricted, 3-dim)
    m_sq = np.trace(sector_block @ sector_block.T)

Global traces over the full 48x48 space are almost always the wrong object in Cl(4,4).
The physical scalar mass / fermion hierarchy structure lives in sector-restricted blocks.

If this trace IS over a full-dim space for a specific reason, state it explicitly:
    # trace over: full 48-dim (Casimir invariant, sector-independent)
EOF

exit 0
