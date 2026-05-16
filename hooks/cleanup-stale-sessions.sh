#!/bin/bash
# cleanup-stale-sessions.sh - Warn about multiple Claude sessions
# Runs as SessionStart hook - WARNING ONLY, does not kill anything

set -euo pipefail

# Count Claude processes (excluding grep itself)
SESSION_COUNT=$(pgrep -c -f "^claude " 2>/dev/null || echo "0")

# Warn if multiple sessions detected. Point to the agent-bridge as the
# coordination mechanism so the sessions can discover each other's focus and
# collaborate, rather than working in isolation or stepping on each other.
if [[ "$SESSION_COUNT" -gt 1 ]]; then
    echo "NOTE: $SESSION_COUNT Claude sessions running on this machine."
    if [ -x "$HOME/.agent-bridge/bridge" ]; then
        echo "  Use the agent-bridge to coordinate. Quick start:"
        echo "    $HOME/.agent-bridge/bridge agents        # see who's registered"
        echo "    $HOME/.agent-bridge/bridge announce ...  # join the bridge"
        echo "    $HOME/.agent-bridge/bridge tail          # read recent traffic"
        echo "  Protocol: $HOME/.agent-bridge/AGENTS.md (or 'bridge onboard')."
    fi
fi

exit 0
