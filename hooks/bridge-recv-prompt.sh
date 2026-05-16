#!/bin/bash
# UserPromptSubmit hook: drain pending bridge messages before each prompt.
# Keeps the agent current without relying solely on the background watcher.

BRIDGE="$HOME/.agent-bridge/bridge"
[[ ! -x "$BRIDGE" ]] && exit 0

AGENT_ID=$("$BRIDGE" whoami 2>/dev/null | grep "^Effective identity:" | awk '{print $3}')
[[ -z "$AGENT_ID" ]] && exit 0

PENDING=$("$BRIDGE" recv "$AGENT_ID" 2>/dev/null)
[[ -n "$PENDING" ]] && echo "BRIDGE [$AGENT_ID]: new messages:" && echo "$PENDING"
exit 0
