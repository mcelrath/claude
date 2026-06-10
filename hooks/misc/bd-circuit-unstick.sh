#!/bin/bash
# PreToolUse(Bash): clear bd's STALE-OPEN circuit-breaker so bd reconnects when
# the shared dolt server is actually reachable (kb-7g9.10 "self-defeating loop").
#
# bd persists breaker state in /tmp/beads-dolt-circuit-<port>.json. A transient
# query-probe timeout (dolt slow under tardis load) flips it to "open"; bd then
# "fails fast" and only re-probes on its own cooldown — which under SUSTAINED
# load keeps timing out, so bd stays wedged for a long time even though dolt is
# healthy (serves queries, accepts connections). The breaker is compiled into the
# @beads/bd Go binary (no env/flag to tune), and a dolt restart does NOT reset it
# (it's client-side state). Manually deleting the file fixes it (user-confirmed).
#
# This hook automates that safely: before a bd command, if the breaker file says
# "open" AND the server's port is reachable, delete the stale file so bd re-probes
# immediately. If the server is genuinely DOWN (port unreachable), the open
# breaker is LEFT INTACT (fail-fast is correct then). Never starts a local server.
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c "import sys,json;print((json.load(sys.stdin).get('tool_input') or {}).get('command','') or '')" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Act only on bd invocations (bd as a command word, optionally path-prefixed).
printf '%s' "$CMD" | python3 -c "
import sys, re
c = sys.stdin.read()
sys.exit(0 if re.search(r'(^|[\s;&|\`(])([^\s;&|]*/)?bd(\s|\$)', c) else 1)
" 2>/dev/null || exit 0

host="${BEADS_DOLT_SERVER_HOST:-tardis}"
port="${BEADS_DOLT_SERVER_PORT:-3308}"
cf="/tmp/beads-dolt-circuit-${port}.json"
[ -f "$cf" ] || exit 0

state=$(python3 -c "
import json
try:
    print(json.load(open('$cf')).get('state', ''))
except Exception:
    print('')
" 2>/dev/null)
[ "$state" = "open" ] || exit 0

# Breaker is OPEN. Only clear it if the server is actually reachable — else the
# open state is correct (server down) and must stay.
if timeout 3 nc -z -w2 "$host" "$port" 2>/dev/null; then
    rm -f "$cf"
    echo "[bd-circuit-unstick] cleared STALE-OPEN bd breaker ($cf): $host:$port reachable — bd will re-probe instead of failing fast (kb-7g9.10)." >&2
fi
exit 0
