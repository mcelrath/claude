#!/bin/bash
# SessionStart hook: combined session initialization
# Merges: history-isolation.sh, kb-search-reset.sh, build-status.sh
source "$HOME/.claude/hooks/lib/claude-env.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
source_type=$(echo "$input" | jq -r '.source // ""' 2>/dev/null)

source "$HOME/.claude/hooks/lib/state.sh"

# --- History isolation (was history-isolation.sh) ---
if [[ -n "$session_id" ]]; then
    if [[ -n "$CLAUDE_ENV_FILE" ]]; then
        mkdir -p "$CLAUDE_DIR/history"
        echo "export HISTFILE=\"\$CLAUDE_DIR/history/${session_id}\"" >> "$CLAUDE_ENV_FILE"
        echo "export CLAUDE_SESSION_ID=\"${session_id}\"" >> "$CLAUDE_ENV_FILE"
    fi
    echo "$session_id" > "$STATE_DIR/session-$PPID"
    mkdir -p "$CLAUDE_DIR/sessions/$session_id"
fi

# --- KB state cleanup (was kb-search-reset.sh) ---
# Time-based, so it BOUNDS the persistent ~/.claude/state root that no longer
# gets a reboot-wipe (kb-h3b). Every churning file class must be swept here or it
# accumulates one stale file per dead session forever.
for pat in "*-searched" "*-hook-seen" "*-kb-seen" "*-incomplete-markers" \
           "*-context" "session-*" "provider-context-window*"; do
    find "$STATE_DIR" -maxdepth 1 -name "$pat" -mmin +240 -delete 2>/dev/null
done
# readcov is a per-session SUBDIR; -maxdepth 1 + rm -rf avoids find descending
# into a dir it is deleting. read_coverage_gate.py is fail-open, so a racing rm
# only forces a recompute, never a block (review finding 5: safe vs live writer).
find "$STATE_DIR" -maxdepth 1 -name "*-readcov" -type d -mmin +240 -exec rm -rf {} + 2>/dev/null
# Dead-session sweep: drop ALL derived files the moment the owning PID is gone.
for f in "$STATE_DIR"/session-*; do
    [[ -f "$f" ]] || continue
    pid="${f##*-}"
    if ! kill -0 "$pid" 2>/dev/null; then
        old_sid=$(cat "$f" 2>/dev/null)
        rm -f "$f"
        [[ -n "$old_sid" ]] && rm -rf \
            "$STATE_DIR/${old_sid}-searched" "$STATE_DIR/${old_sid}-hook-seen" \
            "$STATE_DIR/${old_sid}-kb-seen" "$STATE_DIR/${old_sid}-incomplete-markers" \
            "$STATE_DIR/${old_sid}-context" "$STATE_DIR/${old_sid}-readcov"
    fi
done
# owed-deferred (host-global): trim lines older than 6h (DEFER_TTL) via atomic
# write-rename so the appending bridge-owed-reply hook is never corrupted
# (review finding 4). Mirrors the python reader's "now - epoch < TTL" semantics.
DEFER="$STATE_DIR/owed-deferred"
if [[ -f "$DEFER" ]]; then
    _now=$(date +%s)
    if awk -v now="$_now" -v ttl=21600 '($1+0) > (now-ttl)' "$DEFER" > "$DEFER.tmp.$$" 2>/dev/null; then
        mv "$DEFER.tmp.$$" "$DEFER" 2>/dev/null || rm -f "$DEFER.tmp.$$"
    else
        rm -f "$DEFER.tmp.$$"
    fi
fi

# --- Build status on resume (was build-status.sh) ---
if [[ "$source_type" == "resume" ]]; then
    build-manager brief 2>/dev/null
fi

exit 0
