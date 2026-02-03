#!/bin/bash
# KB Pre-Compact Hook
# Extracts findings and context from conversation before /compact
# Uses local LLM at tardis:9510

LOG_FILE="$HOME/.cache/kb/precompact.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Get project name
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

log "PreCompact hook started for project: $PROJECT"

# Read conversation from stdin
CONVERSATION=$(cat)
CONV_LEN=${#CONVERSATION}

if [[ $CONV_LEN -lt 1000 ]]; then
    log "Conversation too short ($CONV_LEN chars), skipping"
    exit 0
fi

log "Processing conversation ($CONV_LEN chars)"

# Truncate to last 80k chars for LLM context
if [[ $CONV_LEN -gt 80000 ]]; then
    CONVERSATION="${CONVERSATION: -80000}"
    log "Truncated to 80k chars"
fi

# Set KB environment
export KB_EMBEDDING_URL="http://ash:8080/embedding"
export KB_EMBEDDING_DIM=4096
export KB_LLM_URL="http://tardis:9510/completion"

KB_VENV="$HOME/Projects/ai/kb/.venv/bin/python"
KB_SCRIPT="$HOME/Projects/ai/kb/kb.py"

# Use Python for the LLM call and KB insertion
"$KB_VENV" - "$PROJECT" "$CONVERSATION" << 'PYTHON_SCRIPT'
import sys
import json
import subprocess
import os
from urllib.request import urlopen, Request
from urllib.error import URLError

PROJECT = sys.argv[1]
CONVERSATION = sys.argv[2]

LLM_URL = os.environ.get("KB_LLM_URL", "http://tardis:9510/completion")
KB_VENV = os.environ.get("HOME") + "/Projects/ai/kb/.venv/bin/python"
KB_SCRIPT = os.environ.get("HOME") + "/Projects/ai/kb/kb.py"

def llm_complete(prompt: str, max_tokens: int = 2000) -> str | None:
    """Call local LLM for completion using chat API."""
    # Use chat completion endpoint for better format adherence
    chat_url = LLM_URL.replace("/completion", "/v1/chat/completions")
    try:
        req = Request(
            chat_url,
            data=json.dumps({
                "messages": [
                    {"role": "system", "content": "You extract findings from conversations and return ONLY valid JSON. No explanations, no markdown fences, just the JSON object."},
                    {"role": "user", "content": prompt}
                ],
                "max_tokens": max_tokens,
                "temperature": 0.3,
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"LLM error: {e}", file=sys.stderr)
        return None

def add_to_kb(content: str, finding_type: str, tags: list[str], evidence: str = "") -> bool:
    """Add a finding to the KB."""
    cmd = [KB_VENV, KB_SCRIPT, "add",
           "-t", finding_type,
           "-p", PROJECT,
           "--force",  # Skip duplicate check - LLM judged significance
           content]

    if tags:
        cmd.extend(["--tags", ",".join(tags)])
    if evidence:
        cmd.extend(["-e", evidence[:500]])  # Truncate evidence

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return result.returncode == 0
    except Exception:
        return False

# Extract findings using LLM
EXTRACT_PROMPT = f'''Extract significant technical findings from this conversation.

CONVERSATION:
{CONVERSATION[-60000:]}

Return JSON in exactly this format:
{{"work_context": "one sentence summary", "findings": [{{"type": "success", "content": "what worked", "tags": ["tag1"], "evidence": "quote"}}]}}

Finding types: success (verified working), failure (confirmed broken with reason), discovery (new insight)
Tags: lowercase-hyphenated (gpu-memory, build-error, dim-8)
Maximum 5 findings. Empty array if nothing significant.'''

result = llm_complete(EXTRACT_PROMPT)

if not result:
    print("KB: No LLM response", file=sys.stderr)
    sys.exit(0)

# Debug: log raw LLM response
debug_file = os.environ.get("HOME") + "/.cache/kb/llm_response.txt"
with open(debug_file, "w") as f:
    f.write(result)

# Parse JSON from response
try:
    # Find JSON in response
    json_start = result.find("{")
    json_end = result.rfind("}") + 1
    if json_start == -1 or json_end == 0:
        print("KB: No JSON found in response", file=sys.stderr)
        sys.exit(0)

    json_text = result[json_start:json_end]
    data = json.loads(json_text)
except json.JSONDecodeError as e:
    print(f"KB: JSON parse error: {e}", file=sys.stderr)
    print(f"KB: Raw JSON: {json_text[:500]}", file=sys.stderr)
    sys.exit(0)

# Save work context for post-compact reference
work_context = data.get("work_context", "")
if work_context:
    context_file = os.environ.get("HOME") + "/.cache/kb/last_work_context.txt"
    with open(context_file, "w") as f:
        f.write(f"Project: {PROJECT}\n")
        f.write(f"Context: {work_context}\n")
    print(f"KB: Work context saved: {work_context[:80]}...", file=sys.stderr)

# Process findings
findings = data.get("findings", [])
if not findings:
    print("KB: No significant findings extracted", file=sys.stderr)
    sys.exit(0)

added = 0
for f in findings:
    ftype = f.get("type", "discovery")
    content = f.get("content", "")
    tags = f.get("tags", [])
    evidence = f.get("evidence", "")

    if not content or len(content) < 20:
        continue

    # Validate type
    if ftype not in ("success", "failure", "discovery", "experiment"):
        ftype = "discovery"

    # Ensure tags are strings
    tags = [str(t).lower().replace(" ", "-") for t in tags if t]

    if add_to_kb(content, ftype, tags, evidence):
        added += 1
        print(f"KB: [{ftype.upper()}] {content[:70]}...", file=sys.stderr)

if added > 0:
    print(f"\nKB: Extracted {added} finding(s) before compact", file=sys.stderr)
PYTHON_SCRIPT

EXIT_CODE=$?
log "PreCompact hook completed with exit code $EXIT_CODE"
exit 0  # Always exit 0 to not block compact
