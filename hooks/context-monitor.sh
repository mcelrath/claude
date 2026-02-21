#!/bin/bash
# PreToolUse hook - monitors context usage from real API token counts
# Warns at 85%, blocks at 95% (except for checkpoint-essential tools)
source "$(dirname "$0")/lib/claude-env.sh"

WARN_THRESHOLD=85
BLOCK_THRESHOLD=95

# Tools allowed through even at block threshold (essential for session continuity)
ALLOWED_AT_BLOCK="mcp__knowledge-base__kb_add|mcp__knowledge-base__kb_search|Read|TaskOutput"

# Read hook input JSON
HOOK_INPUT=$(cat)

# PreToolUse provides session_id and transcript_path
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null)
JSONL=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# Fallback: construct path from session_id and cwd
if [[ ! -f "$JSONL" && -n "$SESSION_ID" ]]; then
    PROJECT_PATH=$(pwd | sed 's|/|-|g; s|^-||')
    JSONL="$CLAUDE_DIR/projects/-${PROJECT_PATH}/${SESSION_ID}.jsonl"
fi

if [[ ! -f "$JSONL" ]]; then
    exit 0  # Can't find session, don't block
fi

# Get usage from last line containing "usage" (most recent API call)
USAGE_LINE=$(grep '"usage"' "$JSONL" 2>/dev/null | tail -1)

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

# Read context_window_size written by statusline (session-isolated)
CONTEXT_FILE="/tmp/claude-kb-state/${SESSION_ID}-context"
if [[ -n "$SESSION_ID" && -f "$CONTEXT_FILE" ]]; then
    LIMIT=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('context_window_size', 200000))" 2>/dev/null)
fi
LIMIT=${LIMIT:-200000}

PERCENT=$((CONTEXT * 100 / LIMIT))

# Debug: log to file
echo "$(date): JSONL=$JSONL CTX=$CONTEXT PCT=$PERCENT" >> ~/.cache/context-monitor-debug.log

if [[ $PERCENT -ge $BLOCK_THRESHOLD ]]; then
    # Extract tool name from hook input
    TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

    # Allow checkpoint-essential tools through
    if [[ "$TOOL_NAME" =~ ^($ALLOWED_AT_BLOCK)$ ]]; then
        echo "CONTEXT CRITICAL: ${PERCENT}% but allowing ${TOOL_NAME} for checkpoint."
        exit 0  # Allow through
    fi

    # Run auto-checkpoint before blocking
    "$CLAUDE_DIR/hooks/precompact-save-state.sh" >/dev/null 2>&1

    echo "BLOCKED: Context at ${PERCENT}% (${CONTEXT}/${LIMIT} tokens). Model window: ${LIMIT}." >&2
    echo "Auto-checkpoint saved. Run /clear to continue from checkpoint." >&2
    exit 2  # Block tool use

elif [[ $PERCENT -ge $WARN_THRESHOLD ]]; then
    echo "CONTEXT: ${PERCENT}% used (${CONTEXT}/${LIMIT} tokens). Consider /save-state soon."
fi

exit 0
