#!/bin/bash
# KB Error Extract Hook
# Extracts error signatures from failed commands and searches for solutions
# Uses local LLM at tardis:9510 for error extraction

set -e

KB_SCRIPT="$HOME/Projects/ai/kb/kb.py"
KB_VENV="$HOME/Projects/ai/kb/.venv/bin/python"
KB_LLM_JUDGE="$HOME/.local/bin/kb-llm-judge"

# Read hook input from stdin
INPUT=$(cat)

# Extract tool result and exit code from JSON
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null) || exit 0
EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('tool_result',{}); print(r.get('exitCode', r.get('exit_code', 0)))" 2>/dev/null) || exit 0

# Only process failed Bash commands
if [[ "$TOOL_NAME" != "Bash" ]] || [[ "$EXIT_CODE" == "0" ]]; then
    exit 0
fi

# Get the output from the failed command
OUTPUT=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('tool_result', {})
stdout = r.get('stdout', '') or ''
stderr = r.get('stderr', '') or ''
print(stdout[-5000:] + stderr[-5000:])
" 2>/dev/null) || exit 0

# Skip if output too short
if [[ ${#OUTPUT} -lt 50 ]]; then
    exit 0
fi

# Get project name from git root
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

# Set KB environment
export KB_EMBEDDING_URL="http://ash:8080/embedding"
export KB_EMBEDDING_DIM=4096

# Ask LLM to extract error signatures
SYSTEM_PROMPT='Extract distinct error signatures from this build/command output.
Output JSON: {"errors": [{"signature": "unique error message/pattern", "type": "build|runtime|test|link"}]}
Rules:
- Extract the core error message, not full paths or line numbers
- Combine related errors into one signature
- Max 5 most important errors
- If no clear errors, return: {"errors": []}'

RESULT=$("$KB_LLM_JUDGE" "$SYSTEM_PROMPT" "$OUTPUT" 2>/dev/null) || exit 0

# Process extracted errors
echo "$RESULT" | python3 -c "
import sys
import json
import subprocess

try:
    data = json.load(sys.stdin)
    errors = data.get('errors', [])

    if not errors:
        sys.exit(0)

    project = '$PROJECT'
    kb_venv = '$KB_VENV'
    kb_script = '$KB_SCRIPT'

    for err in errors[:5]:
        sig = err.get('signature', '')
        etype = err.get('type', 'build')

        if not sig or len(sig) < 10:
            continue

        # Record the error
        cmd = [kb_venv, kb_script, 'error', 'add', sig, '-p', project]
        if etype:
            cmd.extend(['-t', etype])

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                error_id = result.stdout.strip().split()[-1]
                print(f'KB: Recorded error [{etype}] {sig[:60]}...', file=sys.stderr)

                # Search for existing solutions
                search_cmd = [kb_venv, kb_script, 'search', sig[:100], '-n', '3']
                search_result = subprocess.run(search_cmd, capture_output=True, text=True, timeout=15)
                if search_result.returncode == 0 and 'SUCCESS' in search_result.stdout:
                    print(f'KB: Found potential solutions - run kb error get {error_id}', file=sys.stderr)
        except Exception:
            pass

except Exception as e:
    pass
"
