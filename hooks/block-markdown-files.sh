#!/bin/bash
# PreToolUse hook for Write. Blocks .md creation. Three gates, in order:
#   1. Structural allowlist (CLAUDE.md, plans, agents, ...). Always allowed.
#   2. Editing an EXISTING md file (path already exists). Always allowed —
#      the novelty filter only blocks new files.
#   3. Reflex-pattern basename → blocked unconditionally (cannot escape with
#      AskUserQuestion; these names are never genuinely requested).
#   4. New ad-hoc md → blocked unless per-turn flag is set. The flag is set
#      by md-asked-gate.sh whenever Claude calls AskUserQuestion (the
#      canonical user-intent capture mechanism).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

[ "$TOOL_NAME" != "Write" ] && exit 0

FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[[ "$FILE_PATH" != *.md ]] && exit 0

BASENAME=$(basename "$FILE_PATH")

# --- 1. Structural allowlist ---
case "$FILE_PATH" in
    */.claude*/plans/*.md)            exit 0 ;;
    */.claude*/agents/*.md)           exit 0 ;;
    */.claude*/commands/*.md)         exit 0 ;;
    */.claude*/rules/*.md)            exit 0 ;;
    */.claude*/docs/*.md|*/.claude*/docs/**/*.md) exit 0 ;;
    */docs/reference/*.md)            exit 0 ;;
    */CLAUDE.md|*/.claude*/CLAUDE.md) exit 0 ;;
    */.claude*/*/memory/*.md|*/.claude*/memory/*.md) exit 0 ;;
    */agent-preamble.md)              exit 0 ;;
esac

# --- 2. Editing existing file: always allowed (novelty filter applies only to NEW files) ---
if [ -f "$FILE_PATH" ]; then
    exit 0
fi

# --- 3. Reflex-pattern hard block (basename) — cannot escape via AskUserQuestion ---
shopt -s nocasematch
REFLEX_RX='^(summary|sprint_|progress_|plan_|analysis_|findings_|review_|investigation_|implementation_|notes_|results_|breakthrough|decisions_|todo|status_|update_|report_|recap|session_|completion|completed_|done_|observations_|changes|worklog|session_log).*\.md$|.*(_complete|_review|_summary|_notes|_status|_results|_progress|_recap|_findings|_analysis|_log)\.md$|.*_(v[0-9]+|old|draft|bak|backup)\.md$'
if [[ "$BASENAME" =~ $REFLEX_RX ]]; then
    cat >&2 <<EOF
BLOCKED: '$BASENAME' matches a reflex-pattern filename. These are never genuinely requested by users.

Status updates, summaries, reviews, plans, analyses, recaps, notes, observations belong in:
  - your conversation response (the user reads it)
  - a beads issue: bd create --title "..." --description "..."
  - kb: kb_add(content="...", tags="...")

Markdown files are NOT a scratch pad. This block is unconditional — even AskUserQuestion confirmation will not unblock a reflex-pattern name. If the content is legitimate, rename to a non-reflex filename.
EOF
    exit 2
fi
shopt -u nocasematch

# --- 4. AskUserQuestion gate (per-session AND session-agnostic) ---
# Per-session flag set by md-asked-gate.sh
FLAG="/tmp/claude-md-allow-${SESSION_ID}"
if [ -e "$FLAG" ]; then
    exit 0
fi

# Session-agnostic flag: accepted within 15 min of the last AskUserQuestion.
# Handles two cases: (a) session_id propagation to PreToolUse differs from
# PostToolUse in this harness build, (b) a single AskUserQuestion covers a
# batch of related .md writes (user explicitly requested multiple files).
ANY_FLAG=/tmp/claude-md-allow-any
if [ -e "$ANY_FLAG" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$ANY_FLAG" 2>/dev/null || echo 0)
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt 900 ]; then
        exit 0
    fi
fi

cat >&2 <<EOF
BLOCKED: creating a new markdown file '$FILE_PATH'.

Before creating any new markdown file, use AskUserQuestion to confirm with the user that they want it. AskUserQuestion is the canonical mechanism for capturing user intent; once you have called it this turn, the hook will allow the Write (for any number of .md files within the next 15 minutes).

If the content is a status update, summary, review, analysis, plan, or recap: it does not belong in a markdown file at all. Put it in your conversation response (the user reads it), or in a beads issue (bd create), or in kb (kb_add).
EOF
exit 2
