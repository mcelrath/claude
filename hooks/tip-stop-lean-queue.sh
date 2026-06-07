#!/bin/bash
# Stop hook: block tip from ending a session while lean_work_queue has undeferred rows.
#
# Fires ONLY for tip's registered bridge session (same guard as
# block-stop-without-bridge-watcher.sh). Never blocks non-tip sessions.
#
# Rules (per archie #4518 + tip counter-proposal #4523):
#   EXECUTE-READY, no defer  → BLOCK: launch lean-prover agent or set defer reason
#   DESIGN-NEEDED, no defer  → BLOCK: do design work inline or set design-pending
#   divergence_flag=1        → BLOCK with DIVERGED marker, report to archie first
#   all rows deferred        → ALLOW stop
#
# Valid defer reasons (closed list):
#   data_blocked_on:<bd-id>  design-pending:<decision>  file-conflict:<agent-id>
#   agent-cap                user-gate:<adjudication>   verify-first:<row-id>
# Invalid: low-priority  busy  next-session
#
# Set defer: bd update <bd_id> --notes "defer:<reason>:<detail>"
#   (the stop hook reads lean_work_queue.defer_reason set via kb CLI or ingest)

[ -x "$HOME/.agent-bridge/bridge" ] || exit 0

INPUT=$(cat 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

AGENTS_FILE="$HOME/.agent-bridge/agents.json"
[ -f "$AGENTS_FILE" ] || exit 0

# Only fire for tip's bridge session
ID=""
if [ -n "$SESSION_ID" ]; then
    ID=$(jq -r --arg sid "$SESSION_ID" '.agents[] | select(.session_id == $sid) | .id' "$AGENTS_FILE" 2>/dev/null | head -n1)
fi
if [ "$ID" != "tip" ]; then
    exit 0
fi

DB="$HOME/.cache/kb/knowledge.db"
[ -f "$DB" ] || exit 0

# Block counter (scoped per session_id, like bridge-watcher hook)
CTR="/tmp/claude-lean-queue-stopblock-${SESSION_ID}"
N=0
[ -f "$CTR" ] && N=$(cat "$CTR" 2>/dev/null || echo 0)
case "$N" in (*[!0-9]*) N=0 ;; esac
N=$((N + 1))
echo "$N" > "$CTR"
if [ "$N" -gt 3 ]; then
    echo "LEAN_QUEUE_BLOCK (stop allowed after 3 blocks): undeferred proof work remains. Recheck lean_work_queue." >&2
    rm -f "$CTR" 2>/dev/null
    exit 0
fi

# Query undeferred rows
RESULT=$(python3 - <<'PYEOF'
import sqlite3, os, sys

db = os.path.expanduser('~/.cache/kb/knowledge.db')
conn = sqlite3.connect(db, timeout=5)

rows = conn.execute("""
    SELECT id, file, decl_name, class, readiness, bd_id, defer_reason, divergence_flag
    FROM lean_work_queue
    WHERE project = 'algebraic-genesis'
      AND (defer_reason IS NULL OR defer_reason = '')
    ORDER BY divergence_flag DESC, readiness DESC, created_at ASC
    LIMIT 5
""").fetchall()
conn.close()

if not rows:
    print("CLEAR")
    sys.exit(0)

import os.path
lines = []
for rid, file, decl, cls, readiness, bd_id, defer_reason, div_flag in rows:
    fname = os.path.basename(file or '?')
    label = f'[DIVERGED] ' if div_flag else ''
    bd_ref = f' bd={bd_id}' if bd_id else ''
    lines.append(f'  {label}{readiness} {cls}: {fname}::{decl or "(file-level)"}{bd_ref}')
print('\n'.join(lines))
PYEOF
)

if [ "$RESULT" = "CLEAR" ]; then
    rm -f "$CTR" 2>/dev/null
    exit 0
fi

cat >&2 <<EOF
LEAN_QUEUE_BLOCKED: lean_work_queue has undeferred proof work. tip cannot stop silently.

Top undeferred rows:
$RESULT

For each row, EITHER:
  1. Launch a lean-prover agent NOW (claim the bd item first):
       Task(subagent_type='lean-prover', prompt='...', model='sonnet')
     Note: lake-check needs committed files. For NEW (untracked) files, use lake-locked.
     Cap: max 3 lean-prover agents in flight.
  2. Set a valid defer reason (closes this stop-block for that row):
       ~/.local/bin/kb queue-defer <row-id> <reason> [detail]
     Valid reasons: data_blocked_on:<bd-id>  design-pending:<decision>
                    file-conflict:<agent-id>  agent-cap  user-gate:<adj>  verify-first:<row-id>
     NOT valid: low-priority  busy  next-session
  3. [DIVERGED] rows: report the divergence to archie BEFORE launching any agent.
     bridge send archie "diverged row: <file>::<decl> — <what contradicts current state>"
EOF
exit 2
