#!/bin/bash
# PreToolUse hook for Bash. Blocks LARGE heredocs piped to an interpreter
# (python, bash, node, ruby, perl), where errors require a full re-paste.
# Rationale: Write a script file and execute it. A typo then needs a one-line
# Edit instead of a re-pasted heredoc. There is no allow flag.
#
# Length policy by destination (decided by sniffing the line that opens the
# heredoc):
#   - Interpreter pipe (python3 <<, bash <<, node <<, ruby <<, perl <<):
#       warn at 30 lines, BLOCK at 60 lines.
#   - File redirect (cat > FILE <<, tee FILE <<, > FILE <<):
#       always allowed (it IS file creation; no retry-cost asymmetry).
#   - Network / external tool (ssh, mail, sendmail, msmtp, gh pr|issue create,
#     kubectl apply -f -, docker exec -i, podman exec -i, sudo tee):
#       always allowed (heredoc IS the canonical body mechanism).
#   - CLI structured arg (bd create|update --description|--notes, git commit,
#     bridge send|user-direction|announce):
#       always allowed.
#   - Anything else: warn at 30 lines, BLOCK at 60 lines.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Cheap early-out: no heredoc at all?
echo "$CMD" | grep -qE "<<[-]?[[:space:]]*['\"]?[A-Za-z_][A-Za-z0-9_]*" || exit 0

export _HD_CMD="$CMD"
python3 - <<'PY'
import os, re, sys
cmd = os.environ.get('_HD_CMD', '')

# Find each heredoc: line containing <<DELIM, then body until line == DELIM.
# Handles <<EOF, <<'EOF', <<"EOF", <<-EOF (tab-stripped form).
heredoc_open = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")

lines = cmd.splitlines()
i = 0
heredocs = []  # list of (open_line_str, body_line_count, delim)
while i < len(lines):
    m = heredoc_open.search(lines[i])
    if m:
        delim = m.group(1)
        open_line = lines[i]
        body = 0
        j = i + 1
        while j < len(lines):
            if lines[j].strip() == delim:
                break
            body += 1
            j += 1
        heredocs.append((open_line, body, delim))
        i = j + 1
    else:
        i += 1

if not heredocs:
    sys.exit(0)

# Classify each heredoc's destination from its open line.
ALWAYS_ALLOW_RX = [
    r'(^|[\s\|;&])cat\s+>\s*\S+\s*<<',                 # cat > file <<
    r'(^|[\s\|;&])tee(\s+-[a-zA-Z]+)*\s+\S+\s*<<',     # tee file <<
    r'(^|[\s\|;&])\S+\s*>>?\s*\S+\s*<<',               # any > FILE <<
    r'(^|[\s\|;&])ssh\b',
    r'(^|[\s\|;&])(mail|sendmail|msmtp|mutt)\b',
    r'(^|[\s\|;&])gh\s+(pr|issue|release)\s+(create|edit|comment)\b',
    r'(^|[\s\|;&])kubectl\s+(apply|create|replace|patch)\b.*-f\s+-',
    r'(^|[\s\|;&])(docker|podman)\s+exec\s+-i\b',
    r'(^|[\s\|;&])sudo\s+tee\b',
    r'(^|[\s\|;&])bd\s+(create|update)\b',
    r'(^|[\s\|;&])git\b[^|;&]*\s+commit\b',
    r'(^|[\s\|;&])\S*bridge\s+(send|user-direction|announce)\b',
]
INTERPRETER_RX = [
    r'(^|[\s\|;&])python3?\s*<<',
    r'(^|[\s\|;&])python3?\s+-\s*<<',
    r'(^|[\s\|;&])(bash|sh|zsh)\s*<<',
    r'(^|[\s\|;&])node\s*<<',
    r'(^|[\s\|;&])ruby\s*<<',
    r'(^|[\s\|;&])perl\s*<<',
]

def classify(open_line):
    for p in ALWAYS_ALLOW_RX:
        if re.search(p, open_line):
            return 'allow'
    for p in INTERPRETER_RX:
        if re.search(p, open_line):
            return 'interp'
    return 'other'

WARN_LINES  = 30
BLOCK_LINES = 60

blocks = []
warns = []
for open_line, body, delim in heredocs:
    kind = classify(open_line)
    if kind == 'allow':
        continue
    if body >= BLOCK_LINES:
        blocks.append((open_line, body, delim, kind))
    elif body >= WARN_LINES:
        warns.append((open_line, body, delim, kind))

if blocks:
    sys.stderr.write("BLOCKED: heredoc body too large for retry-cheap workflow.\n\n")
    for open_line, body, delim, kind in blocks:
        sys.stderr.write("  {} lines, delim={}, dest={}\n".format(body, delim, kind))
        sys.stderr.write("  opens with: {}\n".format(open_line.strip()[:140]))
    sys.stderr.write("\nWrite the body to a script file and execute the file:\n")
    sys.stderr.write("  1. Write tool: create /tmp/<name>.{py,sh,js,rb,pl}\n")
    sys.stderr.write("  2. Bash tool:  execute the file\n")
    sys.stderr.write("If you typo, you Edit one line instead of re-pasting the whole heredoc.\n")
    sys.stderr.write("\nDo NOT retry with a shorter heredoc; the body content stays the same and the same retry-asymmetry applies. Do NOT split into multiple Bash heredocs.\n")
    sys.stderr.write("\nExempted destinations (heredoc always allowed regardless of length):\n")
    sys.stderr.write("  cat > FILE, tee FILE, > FILE, ssh, mail, gh {pr,issue} create, kubectl apply -f -, docker exec -i, sudo tee, bd create|update, git commit, bridge send|user-direction|announce\n")
    sys.exit(2)

if warns:
    for open_line, body, delim, kind in warns:
        sys.stderr.write("WARN: heredoc body is {} lines (>= {}). Consider writing to a script file; one-line Edits beat re-pasted heredocs when you have typos.\n".format(body, WARN_LINES))
    sys.exit(0)

sys.exit(0)
PY
exit $?
