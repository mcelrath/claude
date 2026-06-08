#!/bin/bash
# Shared markdown-policy helpers (kb-bp4 P9), sourced by the two markdown-block
# hooks (block-markdown-files.sh on Write, block-markdown-via-bash.sh on Bash)
# so the AskUserQuestion allow-flag logic lives in ONE place.
#
# md_asked_flag_fresh <session_id>: return 0 (success) iff the per-session flag
# /tmp/claude-md-allow-<sid> (set by md-asked-gate.sh on AskUserQuestion) exists
# and was set within the last hour. The session-agnostic *-any flag is RETIRED
# (it leaked across worktree agents).
md_asked_flag_fresh() {
    local sid="$1"
    local flag="/tmp/claude-md-allow-${sid}"
    [ -e "$flag" ] || return 1
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -c %Y "$flag" 2>/dev/null || echo 0)
    age=$((now - mtime))
    [ "$age" -lt 3600 ]
}
