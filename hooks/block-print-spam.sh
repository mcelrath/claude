#!/bin/bash
# PreToolUse hook for Bash. Blocks decorative output in scripts (echo banners,
# narrative print() calls). The rationale: such output belongs in Claude's
# conversation response, not in script stdout. There is no allow flag — this
# is a code-quality rule, not a permission rule.
#
# Detection looks at the Bash command string and any inline python/bash
# heredoc bodies for these patterns:
#   - echo "=== ... ===", echo "---", echo "Step N", echo "Done!", echo "Successfully ..."
#   - print("=== ... ==="), print("Step N"), print(f"step {i} of N"), print("Done"), print("Loading...")
# A pattern fires if at least 3 decorative lines are found.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Skip git commit (heredoc-style commit messages are recommended)
echo "$CMD" | grep -qE "git\s+(-[A-Za-z]+\s+\S+\s+)*commit" 2>/dev/null && exit 0
# Skip bridge send/announce/user-direction (heredoc message bodies)
echo "$CMD" | grep -qE "bridge\s+(send|announce|user-direction)" 2>/dev/null && exit 0

# Decorative-output detector. Counts narrative/banner lines.
export _SPAM_CMD="$CMD"
python3 - <<'PY'
import os, sys, re
cmd = os.environ.get('_SPAM_CMD', '')

# Strip f-string braces for matching purposes (so f"step {i}" matches "step ?")
def normalize(s):
    return re.sub(r'\{[^}]*\}', '?', s)

# Patterns that indicate decorative output. Each is a regex on a single line.
patterns = [
    # banners and separators
    r'^\s*(echo|print)\s*\(?\s*["\']\s*[=\-*#_]{3,}',
    r'^\s*(echo|print)\s*\(?\s*[fr]?["\'][^"\']*[=\-*#_]{3,}[^"\']*["\']',
    # step/phase narration
    r'^\s*(echo|print)\s*\(?\s*[fr]?["\']\s*(step|phase|stage|part|section)\s+\d',
    # progress narration
    r'^\s*(echo|print)\s*\(?\s*[fr]?["\']\s*(loading|running|starting|finished|complete|completed|processing|building|compiling|installing|preparing|generating|computing|launching)\b',
    # status announcements
    r'^\s*(echo|print)\s*\(?\s*[fr]?["\']\s*(done|ok|success|successfully|pass|passed|fail|failed|warning|error)\b[^"\']*["\']?\s*\)?\s*$',
    # result labels with trivial f-string
    r'^\s*(echo|print)\s*\(?\s*[fr]["\'](result|value|answer|output|total)\s*[:=]\s*\?["\']\s*\)?',
    # bare heredoc echo with === or --- separators
    r'^\s*echo\s+["\']\s*[=\-*#_]{3,}',
]

# Count matches across all lines of the command (heredoc bodies included).
matches = []
for line in cmd.splitlines():
    n = normalize(line)
    for p in patterns:
        if re.search(p, n, re.IGNORECASE):
            matches.append(line.strip())
            break

if len(matches) >= 3:
    sys.stderr.write("BLOCKED: Decorative output detected ({} narrative/banner lines).\n".format(len(matches)))
    sys.stderr.write("Sample:\n")
    for m in matches[:5]:
        sys.stderr.write("  " + m[:120] + "\n")
    sys.stderr.write("\n")
    sys.stderr.write("These belong in your conversation response, not in script stdout. Strip every banner / step-narration / status print and re-run. Numeric results, tables, and structured data are fine; commentary about what the script is doing is not.\n")
    sys.stderr.write("\nDo NOT retry with fewer banners — strip them all. Do NOT split into multiple Bash calls to dodge the count.\n")
    sys.exit(2)

sys.exit(0)
PY
exit $?
