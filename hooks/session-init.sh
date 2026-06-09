#!/bin/bash
# SessionStart hook: combined session initialization
# Merges: history-isolation.sh, kb-search-reset.sh, build-status.sh
source "$(dirname "$0")/lib/claude-env.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
source_type=$(echo "$input" | jq -r '.source // ""' 2>/dev/null)

source "$(dirname "$0")/lib/state.sh"

# --- History isolation (was history-isolation.sh) ---
if [[ -n "$session_id" ]]; then
    if [[ -n "$CLAUDE_ENV_FILE" ]]; then
        mkdir -p "$CLAUDE_DIR/history"
        echo "export HISTFILE=\"\$CLAUDE_DIR/history/${session_id}\"" >> "$CLAUDE_ENV_FILE"
        echo "export CLAUDE_SESSION_ID=\"${session_id}\"" >> "$CLAUDE_ENV_FILE"
    fi
    echo "$session_id" > "$STATE_DIR/session-$PPID"
    mkdir -p "$CLAUDE_DIR/sessions/$session_id"
fi

# --- KB state cleanup (was kb-search-reset.sh) ---
find "$STATE_DIR" -name "*-searched" -mmin +240 -delete 2>/dev/null
find "$STATE_DIR" -name "*-hook-seen" -mmin +240 -delete 2>/dev/null
find "$STATE_DIR" -name "session-*" -mmin +240 -delete 2>/dev/null
for f in "$STATE_DIR"/session-*; do
    [[ -f "$f" ]] || continue
    pid="${f##*-}"
    if ! kill -0 "$pid" 2>/dev/null; then
        old_sid=$(cat "$f" 2>/dev/null)
        rm -f "$f"
        [[ -n "$old_sid" ]] && rm -f "$STATE_DIR/${old_sid}-searched" "$STATE_DIR/${old_sid}-hook-seen"
    fi
done

# --- Build status on resume (was build-status.sh) ---
if [[ "$source_type" == "resume" ]]; then
    build-manager brief 2>/dev/null
fi

exit 0
