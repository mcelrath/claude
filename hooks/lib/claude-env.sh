#!/bin/bash
# Derive CLAUDE_DIR from the hook's own location
# Hooks live in $CLAUDE_DIR/hooks/, so go up one level
# Source this at the top of any hook that needs CLAUDE_DIR
#
# Usage: source "$(dirname "$0")/lib/claude-env.sh"
# Then use $CLAUDE_DIR instead of $HOME/.claude

if [[ -z "$CLAUDE_DIR" ]]; then
    CLAUDE_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." 2>/dev/null && pwd)"
fi

# Fallback if sourced in unexpected context
if [[ ! -d "$CLAUDE_DIR/hooks" ]]; then
    CLAUDE_DIR="$HOME/.claude"
fi

# Local LLM server (llama.cpp / vLLM)
# Override with LLM_HOST env var if server is on a different machine
LLM_HOST="${LLM_HOST:-tardis}"
LLM_PORT="${LLM_PORT:-9510}"
LLM_URL="${LLM_URL:-http://${LLM_HOST}:${LLM_PORT}/v1/chat/completions}"
KB_LLM_URL="${KB_LLM_URL:-http://${LLM_HOST}:${LLM_PORT}/completion}"
