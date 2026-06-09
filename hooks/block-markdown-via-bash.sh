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

CMD=$(CLAUDE_MD_HOOK_INPUT="$INPUT" python3 <<'PYEOF' 2>/dev/null
import os, json, re
cmd = (json.loads(os.environ.get('CLAUDE_MD_HOOK_INPUT') or '{}').get('tool_input') or {}).get('command', '') or ''
# Blank git-commit message bodies (-m / --message "..."/'...', incl. multi-line)
# BEFORE .md-creation detection: a commit MESSAGE that cites a .md path or
# describes a redirect/tee/arrow is prose, not a file operation, and must not
# false-trigger the block (this bug blocked legit `git commit -m "...->X.md..."`).
cmd = re.sub(r'(-m|--message)\s+"(?:[^"\\]|\\.)*"', r'\1 MSG', cmd, flags=re.S)
cmd = re.sub(r"(-m|--message)\s+'(?:[^'\\]|\\.)*'", r'\1 MSG', cmd, flags=re.S)
print(cmd, end='')
PYEOF
)

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

# Honor the per-session AskUserQuestion allow-flag (shared helper — kb-bp4 P9).
. "$HOME/.claude/hooks/lib/md_policy.sh" 2>/dev/null
md_asked_flag_fresh "$SESSION_ID" && exit 0

# Detection patterns that indicate .md CREATION (not edit of existing).
SUSPECT=0
SUSPECT_PATH=""

# (a) Redirect creation: `> x.md`, `>> x.md`. The `>` must be a REAL redirect —
# require the char before it is start/space/digit(fd)/&, NOT `-` or `=` (so an
# arrow `->`/`=>` in a commit message or prose, e.g. `foo -> bar/X.md`, does NOT
# false-match as a redirect; that bug blocked legit `git commit -m "...->...md"`).
if [[ "$CMD" =~ (^|[[:space:]]|[0-9]|\&)\>\>?[[:space:]]*([^|\&\;\<\> ]+\.md)([[:space:]]|$|\;|\&|\|) ]]; then
    SUSPECT=1
    SUSPECT_PATH="${BASH_REMATCH[2]}"
fi
# (b) tee creation.
if [ "$SUSPECT" = "0" ] && [[ "$CMD" =~ (^|[[:space:]\;\&\|])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+([^[:space:]]+\.md)([[:space:]]|$|\;|\&|\|) ]]; then
    SUSPECT=1
    SUSPECT_PATH="${BASH_REMATCH[3]}"
fi
# (c) mv/cp/git-mv to a .md target — but only block if SOURCE doesn't exist
# (i.e. genuinely creating a new .md), or if source exists and dest doesn't
# match the source pattern (renaming non-.md content to .md).
if [[ "$CMD" =~ (^|[[:space:]\;\&\|])(git[[:space:]]+mv|mv|cp)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+\.md)[[:space:]]*($|[\;\&\|]) ]]; then
    # The .md must be the FINAL token (the destination). This excludes
    # `cp X.md Y.txt` and `cp -f X.md Y.txt` (reading a .md, writing a .txt),
    # which previously mis-parsed the .md SOURCE as a .md DEST.
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
# (d) python -c / python3 -c that mentions .md AND a file-write API.
# Two-pass: (i) command contains `python -c` with a .md path AND a write API,
# anywhere in the command. (ii) detect Path(...).write_text /
# pathlib.write_text with a .md path.
if [ "$SUSPECT" = "0" ]; then
    # Only a WRITE indicator counts: write_text/write_bytes/writelines, or
    # open(..., 'w'|'a'|'x'...). A bare open('x.md') / open('x.md','r') / .read()
    # is a READ and is ALLOWED (reading markdown is fine, including archive/).
    PY_WRITE_RE="(write_text|write_bytes|writelines|open\([^)]*,[[:space:]]*['\"][wax])"
    if [[ "$CMD" =~ python3?[[:space:]]+-c[[:space:]] ]] \
       && [[ "$CMD" == *.md* ]] \
       && [[ "$CMD" =~ $PY_WRITE_RE ]]; then
        SUSPECT=1
        # Extract first .md path token for diagnostic.
        SUSPECT_PATH=$(echo "$CMD" | grep -oE "[^'\"[:space:]]+\.md" | head -1)
        [ -z "$SUSPECT_PATH" ] && SUSPECT_PATH="<python-detected .md>"
    fi
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
