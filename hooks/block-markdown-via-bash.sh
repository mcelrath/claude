#!/bin/bash
# PreToolUse hook for Bash. Blocks Bash commands that CREATE a new .md file.
# Existing-file renames (git mv of an existing .md) are ALLOWED.
#
# Detection covers:
#   > x.md / >> x.md             — redirect output (heredoc creation)
#   tee x.md                     — tee
#   mv|cp NONEXISTENT.X y.md     — create-by-rename to a new .md
#   git mv NONEXISTENT.X y.md    — same via git
#   python -c "open('y.md','w')..." — python file creation
#   pathlib write_text on a .md path  — python file creation
#   echo ... > / printf ... >    — caught by the redirect rule
#
# NOT blocked:
#   git mv EXISTING.md other.md  — moving an existing file (allowed)
#   bridge send / kb add ... / bd update ... — CLI args citing .md paths

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# Quick pre-check: does the command mention .md at all?
if [[ "$CMD" != *.md* ]]; then
    exit 0
fi

# Exempt CLI tools where .md filenames appear as args, not as files-to-create.
# Anchored to leading segment of the command (split on ; && || |) so that
# `kb add stub; python -c "open('x.md','w')..."` is NOT exempted.
LEADING=$(echo "$CMD" | awk -F'[;&|]' '{print $1}' | sed -E 's/^[[:space:]]*//')
if [[ "$LEADING" =~ ^(bridge|~/\.agent-bridge/bridge|/home/mcelrath/\.agent-bridge/bridge)[[:space:]]+send([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^(kb|~/\.local/bin/kb|/home/mcelrath/\.local/bin/kb)[[:space:]]+(add|correct|update|get|search|list|stats|reembed|delete|check|bulk-tag|bulk-consolidate|flush-pending)([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^bd[[:space:]]+(create|update|remember|show|close|note|memories|recall)([[:space:]]|$) ]]; then
    exit 0
fi

# Honor the per-session timestamp flag (set by md-asked-gate.sh on
# AskUserQuestion). 1-hour window. The session-agnostic /tmp/claude-md-allow-any
# flag has been RETIRED.
FLAG="/tmp/claude-md-allow-${SESSION_ID}"
if [ -e "$FLAG" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$FLAG" 2>/dev/null || echo 0)
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt 3600 ]; then
        exit 0
    fi
fi

# Detection patterns that indicate .md CREATION (not edit of existing).
SUSPECT=0
SUSPECT_PATH=""

# (a) Redirect creation: `> x.md`, `>> x.md`.
if [[ "$CMD" =~ \>\>?[[:space:]]*([^|\&\;\<\> ]+\.md)([[:space:]]|$|\;|\&|\|) ]]; then
    SUSPECT=1
    SUSPECT_PATH="${BASH_REMATCH[1]}"
fi
# (b) tee creation.
if [ "$SUSPECT" = "0" ] && [[ "$CMD" =~ (^|[[:space:]\;\&\|])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+([^[:space:]]+\.md)([[:space:]]|$|\;|\&|\|) ]]; then
    SUSPECT=1
    SUSPECT_PATH="${BASH_REMATCH[3]}"
fi
# (c) mv/cp/git-mv to a .md target — but only block if SOURCE doesn't exist
# (i.e. genuinely creating a new .md), or if source exists and dest doesn't
# match the source pattern (renaming non-.md content to .md).
if [[ "$CMD" =~ (^|[[:space:]\;\&\|])(git[[:space:]]+mv|mv|cp)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+\.md)([[:space:]]|$|\;|\&|\|) ]]; then
    SRC="${BASH_REMATCH[3]}"
    DST="${BASH_REMATCH[4]}"
    # Existing-file move (the user wants this allowed): if SRC is an existing
    # file, skip the block.
    if [ -f "$SRC" ] || [ -f "${SRC#./}" ]; then
        :
    else
        SUSPECT=1
        SUSPECT_PATH="$DST"
    fi
fi
# (d) python -c / python3 -c with 'open(.., w)' or write_text on a .md path.
if [ "$SUSPECT" = "0" ] && [[ "$CMD" =~ python3?[[:space:]]+-c[[:space:]]+[\'\"].*([\'\"][^\'\"]*\.md[\'\"]).*\b(open|write_text|write_bytes)\b ]]; then
    SUSPECT=1
    SUSPECT_PATH="${BASH_REMATCH[1]}"
fi
# Same pattern but with the operation BEFORE the filename (e.g. `open("x.md","w")`).
if [ "$SUSPECT" = "0" ] && [[ "$CMD" =~ python3?[[:space:]]+-c[[:space:]]+[\'\"].*\b(open|write_text|write_bytes)\b.*([\'\"][^\'\"]*\.md[\'\"]) ]]; then
    SUSPECT=1
    SUSPECT_PATH="${BASH_REMATCH[2]}"
fi

[ "$SUSPECT" = "0" ] && exit 0

cat >&2 <<EOF
BLOCKED: this Bash command would create a new markdown file (detected target: $SUSPECT_PATH).

Route content by type — see CLAUDE.md "Why .md creation is blocked":
  finding / verification / measurement   ->  ~/.local/bin/kb add "..." -t discovery -p <PROJ> --tags ...
  plan (multi-phase)                     ->  ~/.claude/plans/PLAN-<slug>.md (allowlisted, use Write)
  cross-session checkpoint               ->  ~/.local/bin/kb add ... --tags session-checkpoint
  task note                              ->  bd update <issue-id> --notes "..."
  architecture / reference fact          ->  Edit an EXISTING doc under docs/reference/
  agent's investigation report           ->  return INLINE to dispatcher (and/or kb add)
  short summary for the user             ->  just write it in your reply

If kb is unreachable (ash:8081 down): use ~/.claude/pending-kb-adds/<UTC>-<session>.txt
queue file; SessionStart + UserPromptSubmit hooks drain it via 'kb flush-pending'.
DO NOT fall back to .md creation when kb is down.

Existing .md files can be renamed/moved freely (git mv of EXISTING.md is allowed).
This block fires only on NEW .md file creation.

If a NEW .md is genuinely required:
  1. AskUserQuestion to confirm exact path and filename.
  2. Within 1 hour, retry the command.
EOF
exit 2
