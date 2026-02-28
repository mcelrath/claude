#!/bin/bash
# PreToolUse hook for NotebookEdit and mcp__jupyter__modify_notebook_cells
# BLOCKS cells that are presentation-only (mostly print/show statements)
# Forces Claude to ask for clarification instead of making display cells

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Handle both native NotebookEdit and MCP jupyter tool
if [[ "$TOOL_NAME" != "NotebookEdit" ]] && [[ "$TOOL_NAME" != "mcp__jupyter__modify_notebook_cells" ]]; then
    exit 0
fi

# Save input to temp file to pass to Python
TMPFILE=$(mktemp)
printf '%s' "$INPUT" > "$TMPFILE"

# Do the full analysis in Python
ANALYSIS=$(python3 - "$TMPFILE" "$TOOL_NAME" << 'PYEOF'
import sys
import json
import re

tmpfile = sys.argv[1]
tool_name = sys.argv[2]

with open(tmpfile, 'r') as f:
    try:
        data = json.load(f)
    except Exception as e:
        print("PARSE_ERROR")
        sys.exit(0)

tool_input = data.get('tool_input', {})

# Handle different tool input structures
if tool_name == 'mcp__jupyter__modify_notebook_cells':
    operation = tool_input.get('operation', '')
    # Only analyze code operations (markdown cells are allowed)
    if operation not in ('add_code', 'edit_code'):
        print("OK")
        sys.exit(0)
    source = tool_input.get('cell_content', '')
    cell_type = 'code'
else:
    # Native NotebookEdit
    cell_type = tool_input.get('cell_type', 'code')
    source = tool_input.get('new_source', '')

# Markdown cells are allowed (for math communication notebooks)

if not source.strip():
    print("EMPTY")
    sys.exit(0)

def collapse_multiline_strings(src):
    raw_lines = src.split('\n')
    result = []
    acc = None
    for ln in raw_lines:
        if acc is not None:
            acc.append(ln)
            if '"""' in ln or "'''" in ln:
                result.append('\n'.join(acc))
                acc = None
            continue
        s = ln.strip()
        if s.startswith('print') and ('"""' in s or "'''" in s):
            q = '"""' if '"""' in s else "'''"
            after = s.split(q, 1)[1]
            if q not in after:
                acc = [ln]
                continue
        result.append(ln)
    if acc:
        result.append('\n'.join(acc))
    return result

logical = collapse_multiline_strings(source)
lines = [l.strip() for l in logical if l.strip() and not l.strip().startswith('#')]

if not lines:
    print("COMMENTS_ONLY")
    sys.exit(0)

# Count different types of statements
presentation_patterns = [
    r'^print\s*\(',
    r'^show\s*\(',
    r'^display\s*\(',
    r'^LatexExpr\s*\(',
    r'print\s*\(\s*["\']={10,}',  # separator lines
    r'print\s*\(\s*["\'][A-Z][A-Z\s:]+["\']',  # HEADERS IN CAPS
    r'print\s*\(\s*f?["\'].*:\s*\{',  # f-string labels
    r'print\s*\(\s*["\'][-=]{10,}',  # separator dashes
]

computation_patterns = [
    r'^\w+\s*=(?!=)',  # assignment (not ==)
    r'^for\s+',
    r'^while\s+',
    r'^if\s+',
    r'^def\s+',
    r'^class\s+',
    r'^return\s+',
    r'\.solve\(',
    r'\.eigenvalues\(',
    r'\.eigenvectors\(',
    r'\.simplify\(',
    r'\.expand\(',
    r'np\.\w+',
    r'scipy\.',
    r'sympy\.',
    r'sage\.',
    r'\*\s*\w+',  # matrix multiplication
    r'commutator\s*\(',
    r'Sigma\s*\(',
    r'\.dot\(',
    r'\.cross\(',
    r'\.inv\(',
    r'\.det\(',
    r'\.trace\(',
    r'sqrt\s*\(',
    r'exp\s*\(',
    r'log\s*\(',
    r'integrate\s*\(',
    r'diff\s*\(',
    r'sum\s*\(',
    r'prod\s*\(',
    # Matplotlib plotting - valid computation activity
    r'plt\.\w+',
    r'\.plot\(',
    r'\.scatter\(',
    r'\.contour',
    r'\.imshow\(',
    r'\.savefig\(',
    r'\.subplots\(',
    r'ax\.\w+',
    r'fig\.\w+',
]

presentation_count = 0
computation_count = 0

for line in lines:
    is_presentation = any(re.search(p, line) for p in presentation_patterns)
    is_computation = any(re.search(p, line) for p in computation_patterns)

    if is_presentation and not is_computation:
        presentation_count += 1
    elif is_computation:
        computation_count += 1

total_meaningful = presentation_count + computation_count

if total_meaningful == 0:
    print("UNCLEAR")
    sys.exit(0)

presentation_ratio = presentation_count / total_meaningful

# Block if >70% presentation with at least 3 presentation lines
if presentation_ratio > 0.7 and presentation_count >= 3:
    print(f"BLOCK:{presentation_count}:{computation_count}")
    sys.exit(0)

# Block if cell is ONLY print/show with no computation
if computation_count == 0 and presentation_count > 0:
    print(f"BLOCK:{presentation_count}:0")
    sys.exit(0)

print("OK")
PYEOF
)

rm -f "$TMPFILE"

case "$ANALYSIS" in
    BLOCK:*)
        PRES_COUNT=$(echo "$ANALYSIS" | cut -d: -f2)
        COMP_COUNT=$(echo "$ANALYSIS" | cut -d: -f3)
        echo "WARNING: Presentation-heavy cell ($PRES_COUNT presentation, $COMP_COUNT computation). Put commentary in your text response, not in notebook cells."
        exit 0
        ;;
    BLOCK_MARKDOWN)
        echo "WARNING: Markdown cells not allowed. Notebooks are for computation only. Put commentary in your text response."
        exit 0
        ;;
    COMMENTS_ONLY)
        echo "WARNING: Cell contains only comments. No comments in notebooks. Put code or nothing."
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
