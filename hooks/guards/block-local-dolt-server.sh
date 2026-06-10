#!/bin/bash
# PreToolUse hook for Bash. Blocks commands that spawn a LOCAL dolt sql-server,
# so agents stop creating redundant local dolt servers that shadow the shared
# remote at tardis:3308 (and cause split-brain bd state).
#
# Policy (user-directed): ALL bd in ALL directories uses the ONE shared dolt
# server at tardis:3308 (BEADS_DOLT_SERVER_HOST=tardis, AUTO_START=false). No
# agent should ever start a local server. If bd can't reach tardis, the answer
# is to check/wait for tardis or report it — NEVER `bd dolt start` locally.
#
# BLOCKED:  bd dolt start   |   dolt sql-server
# ALLOWED:  bd dolt stop/status/test, all normal bd ops, dolt sql / dolt query

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print((json.load(sys.stdin).get('tool_input') or {}).get('command','') or '')" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Match per command-segment (split on && || ; | newlines) to avoid false trips.
HIT=$(printf '%s' "$CMD" | python3 -c '
import sys, re
cmd = sys.stdin.read()
for seg in re.split(r"&&|\|\||;|\n|\|", cmd):
    s = seg.strip()
    # "dolt sql-server ..." (direct local server launch)
    if re.search(r"(^|[\s/])dolt\s+sql-server\b", s):
        print("dolt sql-server"); break
    # "bd dolt start" (bd-managed local server launch)
    if re.search(r"(^|[\s/])bd\s+dolt\s+start\b", s):
        print("bd dolt start"); break
' 2>/dev/null)

[ -z "$HIT" ] && exit 0

cat >&2 <<EOF
BLOCKED: '$HIT' would start a LOCAL dolt server — agents must NOT do this.

All bd, in every directory, uses the ONE shared dolt server at tardis:3308
(BEADS_DOLT_SERVER_HOST=tardis, BEADS_DOLT_AUTO_START=false). A local server on
127.0.0.1:3308 shadows tardis on the same port and SPLITS bd state (this exact
mistake created a split-brain this session).

If bd is failing to reach the database:
  1. Check the shared server:  bd dolt status   (host should be tardis)
                               bd dolt test
  2. Verify tardis is up:      nc -z tardis 3308   (or ping tardis)
  3. If tardis is DOWN: report it and wait / do non-bd work — do NOT start a
     local server. The remote is the single source of truth.
  4. If bd's circuit breaker is wedged open after tardis recovered, that's the
     known breaker-blocks-reconnect bug (kb-7g9.10) — fix the breaker / retry,
     do NOT paper over it with a local server.

This block is final. A local dolt server is never the right fix.
EOF
exit 2
