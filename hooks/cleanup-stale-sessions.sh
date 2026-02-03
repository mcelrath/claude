#!/bin/bash
# cleanup-stale-sessions.sh - Warn about multiple Claude sessions
# Runs as SessionStart hook - WARNING ONLY, does not kill anything

set -euo pipefail

# Count Claude processes (excluding grep itself)
SESSION_COUNT=$(pgrep -c -f "^claude " 2>/dev/null || echo "0")

# Warn if multiple sessions detected
if [[ "$SESSION_COUNT" -gt 1 ]]; then
    echo "WARNING: $SESSION_COUNT Claude sessions running (may cause lock contention)"
fi

exit 0
