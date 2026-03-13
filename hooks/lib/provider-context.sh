#!/bin/bash
# Resolve the provider's context window size
# Priority: 1) Claude Code's reported value (from statusline JSON)
#           2) Cached provider query result (< 1 hour old)
#           3) Live query to provider API
#           4) CLAUDE_CONTEXT_OVERRIDE env var
#           5) Hardcoded 200000

PROVIDER_CACHE="/tmp/claude-kb-state/provider-context-window"
PROVIDER_CACHE_TTL=3600  # 1 hour

# Get context window from provider API (llama.cpp, vLLM, etc.)
# Queries /v1/models then /props as fallback
# Writes result to cache file
_query_provider_context() {
    local provider_url="${1:-}"
    [[ -z "$provider_url" ]] && return 1

    # Strip path, keep base URL
    local base_url=$(echo "$provider_url" | sed 's|/v1/.*||; s|/completion.*||; s|/$||')
    [[ -z "$base_url" ]] && return 1

    local ctx=0

    # Try /v1/models first (OpenAI-compatible)
    ctx=$(curl -s --connect-timeout 2 --max-time 5 "${base_url}/v1/models" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for model in d.get('data', []):
        meta = model.get('meta', {})
        n_ctx = meta.get('n_ctx_train', 0)
        if n_ctx > 0:
            print(n_ctx)
            break
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)

    # Try /props if /v1/models didn't have it
    if [[ "${ctx:-0}" == "0" ]]; then
        ctx=$(curl -s --connect-timeout 2 --max-time 5 "${base_url}/props" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    n_ctx = d.get('default_generation_settings', {}).get('n_ctx', 0)
    print(n_ctx if n_ctx > 0 else 0)
except:
    print(0)
" 2>/dev/null)
    fi

    if [[ "${ctx:-0}" != "0" && "$ctx" -gt 0 ]] 2>/dev/null; then
        mkdir -p /tmp/claude-kb-state
        echo "$ctx" > "$PROVIDER_CACHE"
        echo "$ctx"
        return 0
    fi
    return 1
}

# Get context window size, using cache when possible
# Usage: ctx=$(get_provider_context_window [claude_reported_size])
#   claude_reported_size: value from Claude Code's statusline JSON (0 if not available)
get_provider_context_window() {
    local claude_reported="${1:-0}"

    # 1) If Claude Code reported a real value, trust it
    if [[ "$claude_reported" -gt 0 ]] 2>/dev/null; then
        echo "$claude_reported"
        return 0
    fi

    # 2) Check cache (avoid network call if recent)
    if [[ -f "$PROVIDER_CACHE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$PROVIDER_CACHE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt $PROVIDER_CACHE_TTL ]]; then
            local cached=$(cat "$PROVIDER_CACHE")
            if [[ "$cached" -gt 0 ]] 2>/dev/null; then
                echo "$cached"
                return 0
            fi
        fi
    fi

    # 3) Query provider API
    # Try LLM_URL from claude-env.sh (the local llama.cpp server)
    local provider_url="${LLM_URL:-}"
    if [[ -n "$provider_url" ]]; then
        local result
        result=$(_query_provider_context "$provider_url")
        if [[ "$result" -gt 0 ]] 2>/dev/null; then
            echo "$result"
            return 0
        fi
    fi

    # 4) Env var override
    if [[ -n "${CLAUDE_CONTEXT_OVERRIDE:-}" && "${CLAUDE_CONTEXT_OVERRIDE}" -gt 0 ]] 2>/dev/null; then
        echo "$CLAUDE_CONTEXT_OVERRIDE"
        return 0
    fi

    # 5) Fallback
    echo "200000"
}
