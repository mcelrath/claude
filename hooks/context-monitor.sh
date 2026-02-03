#!/bin/bash
# PreToolUse hook - monitors context usage from real API token counts
# Warns at 70%, blocks at 85%

WARN_THRESHOLD=85
BLOCK_THRESHOLD=95

# Read hook input JSON
HOOK_INPUT=$(cat)

# PreToolUse provides session_id and transcript_path
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null)
JSONL=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# Fallback: construct path from session_id and cwd
if [[ ! -f "$JSONL" && -n "$SESSION_ID" ]]; then
    PROJECT_PATH=$(pwd | sed 's|/|-|g; s|^-||')
    JSONL="$HOME/.claude/projects/-${PROJECT_PATH}/${SESSION_ID}.jsonl"
fi

if [[ ! -f "$JSONL" ]]; then
    exit 0  # Can't find session, don't block
fi

# Get usage from last line containing "usage" (most recent API call)
USAGE_LINE=$(tac "$JSONL" | grep -m1 '"usage"' 2>/dev/null)

if [[ -z "$USAGE_LINE" ]]; then
    exit 0
fi

# Extract input_tokens + cache_read_input_tokens = current context
CONTEXT=$(echo "$USAGE_LINE" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    usage = data.get('message', {}).get('usage', {})
    print(usage.get('input_tokens', 0) + usage.get('cache_read_input_tokens', 0))
except:
    print(0)
" 2>/dev/null)

CONTEXT=${CONTEXT:-0}
LIMIT=200000
PERCENT=$((CONTEXT * 100 / LIMIT))

# Debug: log to file
echo "$(date): JSONL=$JSONL CTX=$CONTEXT PCT=$PERCENT" >> ~/.cache/context-monitor-debug.log

if [[ $PERCENT -ge $BLOCK_THRESHOLD ]]; then
    # Run auto-checkpoint before blocking
    "$HOME/.claude/hooks/precompact-save-state.sh" >/dev/null 2>&1

    echo "BLOCKED: Context at ${PERCENT}% (${CONTEXT}/${LIMIT} tokens)." >&2
    echo "Auto-checkpoint saved. Run /clear to continue from checkpoint." >&2
    exit 2  # Block tool use

elif [[ $PERCENT -ge $WARN_THRESHOLD ]]; then
    echo "⚠️  CONTEXT: ${PERCENT}% used (${CONTEXT}/${LIMIT} tokens). Consider /save-state soon." >&2
fi

exit 0
