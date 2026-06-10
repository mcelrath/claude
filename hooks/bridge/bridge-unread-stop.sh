#!/bin/sh
# Stop hook: surface unread bridge messages and unanswered --needs-reply messages.
# Advisory only (exit 0 always — never blocks stop).

BRIDGE="$HOME/.agent-bridge/bridge"
[ -x "$BRIDGE" ] || exit 0

# Resolve identity
AGENT_ID="${AGENT_ID:-}"
if [ -z "$AGENT_ID" ]; then
    AGENT_ID=$("$BRIDGE" whoami 2>/dev/null | awk '/^Effective identity:/{print $3}')
fi
[ -z "$AGENT_ID" ] && exit 0

OUTPUT=""

# 1. Unread messages (peek without advancing cursor)
UNREAD=$("$BRIDGE" peek "$AGENT_ID" 2>/dev/null \
    | grep -v '^NOTE: a watcher recently delivered')
if [ -n "$UNREAD" ]; then
    COUNT=$(printf '%s\n' "$UNREAD" | grep -c '^\[#' || true)
    if [ "$COUNT" -gt 0 ]; then
        OUTPUT="BRIDGE_UNREAD (${COUNT} unread to ${AGENT_ID}):
${UNREAD}"
    fi
fi

# 2. Unanswered --needs-reply messages sent by me
PENDING=$("$BRIDGE" pending-replies "$AGENT_ID" 2>/dev/null)
# Guard: bridge builds lacking the `pending-replies` subcommand print the help
# text to stdout (exit 0). That non-empty output was being reported as a phantom
# BRIDGE_PENDING_REPLIES on every Stop. Treat any help-banner output as "none".
case "$PENDING" in
    *"bridge — message channel"*|*"LIFECYCLE"*|*"Usage:"*|*"usage:"*) PENDING="" ;;
esac
if [ -n "$PENDING" ]; then
    if [ -n "$OUTPUT" ]; then OUTPUT="${OUTPUT}
"; fi
    OUTPUT="${OUTPUT}BRIDGE_PENDING_REPLIES (no reply received yet):
${PENDING}"
fi

[ -z "$OUTPUT" ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' \
    "$(printf '%s' "$OUTPUT" | sed 's/"/\\"/g; s/$/\\n/' | tr -d '\n')"

exit 0
