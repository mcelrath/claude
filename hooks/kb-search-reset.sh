#!/bin/bash
# SessionStart hook
# Cleans up stale session state files

STATE_DIR="/tmp/claude-kb-state"
mkdir -p "$STATE_DIR"

# Clean old files (older than 4 hours)
find "$STATE_DIR" -name "*-searched" -mmin +240 -delete 2>/dev/null
find "$STATE_DIR" -name "session-*" -mmin +240 -delete 2>/dev/null

# Clean session files for PIDs that no longer exist
for f in "$STATE_DIR"/session-*; do
    [[ -f "$f" ]] || continue
    pid="${f##*-}"
    if ! kill -0 "$pid" 2>/dev/null; then
        old_session_id=$(cat "$f" 2>/dev/null)
        rm -f "$f"
        [[ -n "$old_session_id" ]] && rm -f "$STATE_DIR/${old_session_id}-searched"
    fi
done

# Note: PPID mapping created by history-isolation.sh (runs after this hook)
exit 0
