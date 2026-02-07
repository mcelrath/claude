#!/bin/bash
# SessionStart hook: Clean up old plan files
# SAFE: Only archives plans NOT referenced by any active session

PLANS_DIR="$HOME/.claude/plans"
ARCHIVE_DIR="$PLANS_DIR/archive"
SESSIONS_DIR="$HOME/.claude/sessions"
mkdir -p "$ARCHIVE_DIR"

# Build list of plans referenced by active sessions
ACTIVE_PLANS=$(mktemp)
for session_dir in "$SESSIONS_DIR"/*/; do
    if [[ -f "${session_dir}current_plan" ]]; then
        cat "${session_dir}current_plan" >> "$ACTIVE_PLANS"
    fi
done

# Also protect plans referenced in recent handoffs (for PLAN_MIGRATION)
for session_dir in "$SESSIONS_DIR"/*/; do
    if [[ -f "${session_dir}handoff.md" ]]; then
        grep -oE 'plans/[a-z0-9][-a-z0-9_]+\.md' "${session_dir}handoff.md" \
            | sed "s|^|$HOME/.claude/|" >> "$ACTIVE_PLANS" 2>/dev/null
    fi
done

# Archive main plan files older than 24h ONLY if not referenced by any session
# NOTE: 2h aggressive archiving was removed - implementation-review ARCHIVE state handles archiving
for plan in $(find "$PLANS_DIR" -maxdepth 1 -name "*.md" ! -name "*-agent-*" -mtime +1 2>/dev/null); do
    if ! grep -qF "$plan" "$ACTIVE_PLANS" 2>/dev/null; then
        mv "$plan" "$ARCHIVE_DIR/" 2>/dev/null
    fi
done

rm -f "$ACTIVE_PLANS"

# Archive orphan plans (not referenced by any active session)
# Safeguards:
# - Skip if no session directories exist (avoid archiving everything)
# - Don't archive plans modified in last 5 minutes (race condition protection)
# - Use realpath for reliable path comparison
session_dirs=("$SESSIONS_DIR"/*/)
if [[ ${#session_dirs[@]} -gt 0 && -d "${session_dirs[0]}" ]]; then
    for plan in $(find "$PLANS_DIR" -maxdepth 1 -name "*.md" ! -name "*-agent-*" -mmin +5 2>/dev/null); do
        plan_realpath=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$plan" 2>/dev/null)
        plan_referenced=false

        for session_dir in "${session_dirs[@]}"; do
            if [[ -f "${session_dir}current_plan" ]]; then
                current_plan_path=$(cat "${session_dir}current_plan" 2>/dev/null)
                current_plan_realpath=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$current_plan_path" 2>/dev/null)

                if [[ "$plan_realpath" == "$current_plan_realpath" ]]; then
                    # Check if session is recent (modified in last 24h)
                    if [[ $(find "$session_dir" -maxdepth 0 -mtime -1 2>/dev/null) ]]; then
                        plan_referenced=true
                        break
                    fi
                fi
            fi
        done

        if [[ "$plan_referenced" != "true" ]]; then
            mv "$plan" "$ARCHIVE_DIR/" 2>/dev/null
        fi
    done
fi

# Move agent output files to subdirectory immediately (keeps main dir clean)
AGENT_DIR="$PLANS_DIR/agent-output"
mkdir -p "$AGENT_DIR"
find "$PLANS_DIR" -maxdepth 1 -name "*-agent-*.md" -exec mv {} "$AGENT_DIR/" \; 2>/dev/null

# Remove agent output files older than 2 days (they're just review logs)
find "$AGENT_DIR" -name "*-agent-*.md" -mtime +2 -delete 2>/dev/null

# Remove stale marker files older than 7 days
find "$PLANS_DIR" -maxdepth 1 -name "expert-review-*" -mtime +7 -delete 2>/dev/null

# Clean up old session directories (not just empty ones)
# Sessions older than 2 days are stale - new sessions create new directories
find "$SESSIONS_DIR" -maxdepth 1 -type d -mtime +2 -exec rm -rf {} \; 2>/dev/null

# Clean up stale task output files (reduces fuser polling overhead)
find /tmp/claude/ -name "*.output" -mmin +120 -delete 2>/dev/null

exit 0
