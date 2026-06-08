---
description: List the available session personas, or select/activate one for this agent. Personas are the agents' binding roles; the global session-persona.sh SessionStart hook re-injects the active persona on every start/compact (so it survives compaction). `/persona` lists; `/persona <name>` selects.
argument-hint: "[<persona-name> | <persona-name>-<suffix>]"
---

# /persona — list or select your session persona

Personas live at `<project>/.claude/agents/personas/<name>.md` (a project supplies
its own set), with `~/.claude/agents/personas/` as a cross-project fallback. The
**bridge ID IS the persona name** — no mapping layer. Append a suffix to run
multiple instances of one persona (`tip-mathlib`, `archie-backup`); the base name
(before the first `-`) selects which persona file loads. The SessionStart hook
`session-persona.sh` auto-loads the active persona on every start/compact.

**`$ARGUMENTS`**

## What to do

1. **Resolve the persona directory** (first that exists):
   - `$(git rev-parse --show-toplevel)/.claude/agents/personas`
   - `$PWD/.claude/agents/personas`
   - `~/.claude/agents/personas`

2. **If `$ARGUMENTS` is empty — LIST.** Show every `*.md` in the persona dir as
   `name — <first non-empty line of the file's description/frontmatter>`. Tell the
   user they can run `/persona <name>` or `/persona <name>-<suffix>` to select one.
   Do nothing else. If the dir is empty or absent, say this project defines no
   personas.

3. **If `$ARGUMENTS` names a persona** (or `<base>-<suffix>`; normalize to
   lower-case; the base is the part before the first `-`):
   1. Confirm `<base>.md` exists in the resolved persona dir; if not, say so and
      list the valid names.
   2. Pin the full given id (including any suffix) as the session's bridge id —
      run this Bash (substitute `<full-id>`):
      ```bash
      FULL_ID="<full-id>"
      D="$(git -C . rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/.persona"
      SID="${CLAUDE_SESSION_ID:-unknown}"
      mkdir -p "$D"
      echo "$FULL_ID" > "$D/session-${SID}"
      echo "pinned persona '$FULL_ID' for session $SID"
      ```
   3. **Read `<base>.md` IN FULL** and **adopt it as your binding operating role
      for the session.** Read in full any files it references.
   4. Confirm to the user: which persona is active, the bridge id (with any
      suffix), and that it re-loads automatically after compaction.
