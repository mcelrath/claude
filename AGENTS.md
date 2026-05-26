# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Version-controlled: Built on Dolt with cell-level merge
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs with git:

- Exports to `.beads/issues.jsonl` after changes (5s debounce)
- Imports from JSONL when newer (e.g., after `git pull`)
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

## Landing the Plane (Session Completion)

**Applies ONLY when the user explicitly says they are stopping** (e.g. "good night", "let's call it", "I'm done for today"). Do NOT trigger this workflow because context is low, because compaction is approaching, or because you sense a "natural stopping point." Compaction is handled by the harness; it is not session completion. See CLAUDE.md "Don't propose pauses".

When user has explicitly ended the session, complete the steps below.

**MANDATORY WORKFLOW (user-initiated only):**

1. **File issues for remaining work** - Create issues for anything that needs follow-up (use `discovered-from:<epic>` per CLAUDE.md "Follow-up Discipline")
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Commit** (push is project-dependent):
   ```bash
   git add <files>
   git commit --no-gpg-sign -m "..."
   ```
   **Push only if the project's CLAUDE.md authorises it.** llama.cpp / braidinfer / exterior_algebra explicitly forbid `git push` — the user syncs from tardis at their own cadence. For those projects: commit, do NOT push. For other projects: follow that project's CLAUDE.md.
5. **Clean up** - Clear stashes (only those you created), prune your own remote branches
6. **Verify** - All work is in `bd` issues or commits; nothing is in plan text only
7. **Hand off** - kb add a session-checkpoint with the in-flight state (project tag + `session-checkpoint` tag). Do NOT write a handoff.md — the harness manages handoff state.

**CRITICAL RULES:**
- This workflow is gated on USER stopping, not Claude proposing to stop
- Commit before saying done. Push only if the project authorises it.
- NEVER say "ready to push when you are" — if push is authorised, YOU do it
- If push fails (when authorised), resolve and retry until it succeeds
- Compaction at 90%+ context is NOT session completion. See `~/.claude/hooks/context-monitor.sh` and CLAUDE.md "Don't propose pauses".

<!-- END BEADS INTEGRATION -->
