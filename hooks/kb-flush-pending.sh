#!/bin/bash
# SessionStart + UserPromptSubmit hook. Drains the kb-down fallback queue
# at ~/.claude/pending-kb-adds/*.txt when the embedding server is reachable.
#
# Lightweight by design:
#   1. Stamp-file rate limit (don't run more than once per 5 min).
#   2. Fast health probe of http://ash:8081/ with 1s timeout; silent exit if
#      not HTTP 200 (model down/loading/network down).
#   3. Only call `kb flush-pending` if (1) and (2) pass.
#   4. Background the flush so the hook returns immediately to the harness.
#
# Why a queue: when ash:8081 is unreachable, agents must persist findings
# somewhere durable. Falling back to .md files would re-create the orphan-
# document problem the user wants to kill. The queue is .txt files in a
# designated dir, drained by this hook + `kb flush-pending` CLI.

QUEUE_DIR="$HOME/.claude/pending-kb-adds"
STAMP="/tmp/claude-kb-flush-last"
# Derive the embedding-server base from its configured URL (default: ash:8081).
HEALTH_URL=$(printf '%s' "${KB_EMBEDDING_URL:-http://ash:8081/embedding}" | sed -E 's|(https?://[^/]+).*|\1/|')
RATE_LIMIT_SEC=300

[ ! -d "$QUEUE_DIR" ] && exit 0

# Are there pending files? Cheapest check.
shopt -s nullglob
queued=("$QUEUE_DIR"/*.txt)
shopt -u nullglob
[ "${#queued[@]}" -eq 0 ] && exit 0

# Rate-limit: only one flush per RATE_LIMIT_SEC seconds across the host.
if [ -e "$STAMP" ]; then
    now=$(date +%s)
    last=$(stat -c %Y "$STAMP" 2>/dev/null || echo 0)
    age=$((now - last))
    [ "$age" -lt "$RATE_LIMIT_SEC" ] && exit 0
fi
: > "$STAMP"

# Fast health probe. 1s timeout. Quiet.
code=$(curl -sS -m 1 -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null)
[ "$code" != "200" ] && exit 0

# Background the flush so the hook returns immediately. Output goes to a
# log; if anything important goes wrong, user can inspect it.
LOG="$HOME/.claude/pending-kb-adds.log"
( ~/.local/bin/kb flush-pending --quiet >> "$LOG" 2>&1 ) &
disown
exit 0
