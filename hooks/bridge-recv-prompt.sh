#!/bin/bash
# UserPromptSubmit hook: drain pending bridge messages before each prompt.
# Keeps the agent current without relying solely on the background watcher.
# Also runs kb search on received message content and emits [ARCHIE-KB] entries
# so the archie persona sees relevant prior art alongside each bridge message.

BRIDGE="$HOME/.agent-bridge/bridge"
KB="$HOME/.local/bin/kb"
[[ ! -x "$BRIDGE" ]] && exit 0

AGENT_ID=$("$BRIDGE" whoami 2>/dev/null | grep "^Effective identity:" | awk '{print $3}')
[[ -z "$AGENT_ID" ]] && exit 0

PENDING=$("$BRIDGE" recv "$AGENT_ID" 2>/dev/null)
[[ -z "$PENDING" ]] && exit 0

echo "BRIDGE [$AGENT_ID]: new messages:"
echo "$PENDING"

# KB context: only run for archie persona (check session pin)
SID="${CLAUDE_SESSION_ID:-}"
PERSONA_BASE=""
if [[ -n "$SID" ]]; then
    for d in \
        "$(pwd -P)/.claude/.persona" \
        "$HOME/Physics/secular-constraints/.claude/.persona" \
        "$HOME/Physics/claude/.claude/.persona"; do
        pin="$d/session-$SID"
        if [[ -f "$pin" ]]; then
            full_id=$(tr -d '[:space:]' < "$pin")
            PERSONA_BASE="${full_id%%-*}"
            break
        fi
    done
fi

if [[ "$PERSONA_BASE" == "archie" && -x "$KB" ]]; then
    KB_RESULTS=$(timeout 12s "$KB" search "$PENDING" 2>/dev/null)
    if [[ -n "$KB_RESULTS" ]]; then
        echo ""
        echo "[ARCHIE-KB] Related kb entries:"
        echo "$KB_RESULTS"
    fi
fi

exit 0
