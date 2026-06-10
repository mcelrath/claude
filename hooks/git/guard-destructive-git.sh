#!/bin/bash
# PreToolUse hook for Bash. Guards git operations that can ERASE uncommitted or
# stashed work. On detection it BLOCKS (exit 2) and instructs the agent to confirm
# with the HUMAN via AskUserQuestion, which arms a short-lived per-session bypass
# flag (set by git-asked-gate.sh). Fail-closed: no fresh flag => blocked.
#
# Born from a real incident (2026-03-27, braidinfer): a `git stash pop` conflicted,
# the agent "cleaned up" with `git checkout HEAD -- <files> && git stash drop`,
# destroying the ONLY copy of uncommitted Phase-3 work (recovered only via
# `git fsck --dangling`). Forensic audit of 1721 transcripts found this as the
# dominant data-loss mechanism. See ~/.claude/CLAUDE.md "Destructive git operations".
#
# Detection is per-command-SEGMENT (split on && || ; | newlines) and token-based,
# so `git checkout -- foo.cu && rm -f bar` does NOT false-trip on the `rm -f`.
#
# GUARDED (inherently destructive; ask-bypass required):
#   git stash drop / git stash clear        — stash content is INVISIBLE to git status
#   git reset --hard / --merge              — discards tracked-file modifications
#   git clean -f[..] / --force              — deletes untracked (authored) files
#   git checkout -f / --force               — force branch-switch discarding dirty tree
#   git switch -f / --force / --discard-changes
#   git worktree remove ... -f / --force    — removes a dirty or detached worktree
#   whole-tree discard: checkout/restore of '.' or ':/'  (mass revert)
# NOT guarded (would cause alarm fatigue; the routine A/B experiment-revert):
#   named-path `git checkout -- <file>` / `git restore <file>`
#   `git restore --staged .` (safe unstage), `git reset --soft` (sanctioned squash)

INPUT=$(cat)

read -r TOOL_NAME SESSION_ID MATCH <<<"$(printf '%s' "$INPUT" | python3 -c '
import sys, json, re, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    print("  "); sys.exit(0)
tool = d.get("tool_name", "")
sid  = d.get("session_id", "") or "-"
cmd  = d.get("tool_input", {}).get("command", "") or ""
if tool != "Bash" or "git" not in cmd:
    print(f"{tool} {sid} "); sys.exit(0)

def toks(s):
    try: return shlex.split(s)
    except Exception: return s.split()

match = ""
for seg in re.split(r"&&|\|\||;|\n|\|", cmd):
    t = toks(seg)
    if "git" not in t:
        continue
    sub = t[t.index("git") + 1:]
    if not sub:
        continue
    verb, rest = sub[0], sub[1:]
    flags = set(rest)
    if verb == "stash" and len(sub) >= 2 and sub[1] in ("drop", "clear"):
        match = f"git stash {sub[1]}"; break
    if verb == "reset" and ("--hard" in flags or "--merge" in flags):
        match = "git reset --hard/--merge"; break
    if verb == "clean" and ("--force" in flags or any(
            f.startswith("-") and not f.startswith("--") and "f" in f for f in rest)):
        match = "git clean -f"; break
    if verb == "checkout" and ("-f" in flags or "--force" in flags):
        match = "git checkout --force"; break
    if verb == "switch" and ("-f" in flags or "--force" in flags or "--discard-changes" in flags):
        match = "git switch --force/--discard-changes"; break
    if verb == "worktree" and len(sub) >= 2 and sub[1] == "remove" and (
            "-f" in flags or "--force" in flags):
        match = "git worktree remove --force"; break
    if verb in ("checkout", "restore") and "--staged" not in flags and "--cached" not in flags:
        paths = [x for x in rest if not x.startswith("-")]
        if "." in paths or ":/" in paths:
            match = f"git {verb} (whole-tree discard)"; break
print(f"{tool} {sid} {match}")
')"

# No destructive match => allow.
[ -z "$MATCH" ] && exit 0

# Honor the per-session bypass flag armed by git-asked-gate.sh on AskUserQuestion.
# 10-minute window. Fail-closed otherwise.
FLAG="/tmp/claude-gitdestruct-allow-${SESSION_ID}"
if [ "$SESSION_ID" != "-" ] && [ -e "$FLAG" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$FLAG" 2>/dev/null || echo 0)
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt 600 ]; then
        exit 0
    fi
fi

cat >&2 <<EOF
BLOCKED: destructive git operation that can ERASE uncommitted or stashed work:
    $MATCH

This class of command has caused near-unrecoverable data loss here before: a
conflicted 'git stash pop' followed by 'git stash drop' destroyed the only copy
of uncommitted work. Uncommitted/stashed/untracked content is INVISIBLE to most
checks and is unrecoverable once gone (beyond the gc grace window).

Before this can run, CONFIRM WITH THE HUMAN:
  1. Run 'git status' (and 'git stash list' for stash ops) and state EXACTLY what
     will be discarded, and whether any of it is the ONLY copy.
  2. AskUserQuestion to get explicit human approval for THIS destructive command.
  3. Within 10 minutes of that approval, retry the command — it will be allowed.

Safer alternatives (usually what you actually want):
  - Preserve instead of discard: 'git switch -c wip/<name> && git commit -am wip'
    parks the work on a branch — recoverable, costs nothing, then proceed clean.
  - Conflicted 'git stash pop'? Do NOT 'stash drop'. Resolve the conflict, or
    'git stash branch <name>' to materialize the stash safely on a new branch.
  - 'reset --hard' is forbidden by CLAUDE.md: use 'git reset --soft <ref>' (keeps
    your files) or 'git restore --staged <path>' to unstage without losing edits.
  - Recover an already-lost tip/stash within the gc window:
    'git reflog' / 'git fsck --lost-found' / 'git fsck --dangling'.
EOF
exit 2
