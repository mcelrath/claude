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
# *_INVESTIGATION.md is hard-blocked: investigation reports must return inline
# to the dispatching agent or land in kb, NEVER in a file. See CLAUDE.md
# "Why .md creation is blocked" for the routing matrix.
REFLEX_RX='^(summary|sprint_|progress_|plan_|analysis_|findings_|review_|investigation_|implementation_|notes_|results_|breakthrough|decisions_|todo|status_|update_|report_|recap|session_|completion|completed_|done_|observations_|changes|worklog|session_log).*\.md$|.*(_complete|_review|_summary|_notes|_status|_results|_progress|_recap|_findings|_analysis|_investigation|_log)\.md$|.*_(v[0-9]+|old|draft|bak|backup)\.md$'
if [[ "$BASENAME" =~ $REFLEX_RX ]]; then
    cat >&2 <<EOF
BLOCKED: '$BASENAME' matches a reflex-pattern filename. These are never genuinely requested by users.

Route content by type — see CLAUDE.md "Why .md creation is blocked":
  finding / verification / measurement   ->  ~/.local/bin/kb add "..." -t discovery -p <PROJ> --tags ...
  plan (multi-phase)                     ->  ~/.claude/plans/PLAN-<slug>.md (allowlisted, use Write)
  cross-session checkpoint               ->  ~/.local/bin/kb add ... --tags session-checkpoint
  task note                              ->  bd update <issue-id> --notes "..."
  agent's investigation report           ->  return INLINE to dispatcher (and/or kb add)
  short summary for the user             ->  just write it in your reply

This block is unconditional — even AskUserQuestion confirmation will not unblock a
reflex-pattern name. If the content is legitimate, route it per the table above.
EOF
    exit 2
fi
shopt -u nocasematch

# --- 4. AskUserQuestion gate (per-session, 1-hour timestamp window) ---
# md-asked-gate.sh sets /tmp/claude-md-allow-${SESSION_ID} on AskUserQuestion.
# Within 1 hour of that timestamp, .md creation is allowed.
# The session-agnostic /tmp/claude-md-allow-any flag has been RETIRED (leaked
# across worktree agents; produced false "agent escape" suspicions).
FLAG="/tmp/claude-md-allow-${SESSION_ID}"
if [ -e "$FLAG" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$FLAG" 2>/dev/null || echo 0)
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt 3600 ]; then
        exit 0
    fi
fi

cat >&2 <<EOF
BLOCKED: creating a new markdown file '$FILE_PATH'. The user doesn't want you polluting his filesystem with random markdown files that need to be triaged later. Acceptable operations are:

  finding / verification / measurement   ->  ~/.local/bin/kb add "..." -t discovery --tags ...
  plan (multi-phase)                     ->  ~/.claude/plans/PLAN-<slug>.md (allowlisted, use Write)
  cross-session checkpoint               ->  ~/.local/bin/kb add ... --tags session-checkpoint
  task note                              ->  bd update <issue-id> --notes "..."
  agent's investigation report           ->  return INLINE to dispatcher (and/or kb add)
  short summary for the user             ->  just write it in your reply

If you have weighed all of the above and a NEW .md is genuinely required:
  1. AskUserQuestion to confirm the exact path and filename with the user.
  2. After the user answers, retry the Write within 1 hour.

Existing .md files can be Edit'd freely (the novelty filter only blocks NEW files).
EOF
exit 2
