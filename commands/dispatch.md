Execute a beads epic by dispatching agents in waves, verifying their work, and looping until done.

Usage: /dispatch <epic-id>

## Protocol

You are the dispatch coordinator. Your job is to keep agents spinning on the epic until every task is complete. You do NOT delegate judgment — you verify everything yourself.

### Phase 1: Survey

1. `bd show $ARGUMENTS` — read the epic, its design file, and all child tasks
2. `bd list --status=open --parent=$ARGUMENTS` — identify ready (unblocked) tasks
3. Read every file the epic's design references. You need the full context to judge agent work.

### Phase 2: Dispatch Loop

```
while unfinished tasks remain:
  1. IDENTIFY ready tasks (no unresolved blockers)
  2. DISPATCH up to 3 agents in parallel (background):
     - One Agent() call per task, run_in_background=True
     - Prompt MUST include:
       * "Read ~/.claude/agents/preamble.md FIRST"
       * The task description from bd
       * "STOPPING CONDITIONS: <what done looks like>"
       * "~/.local/bin/kb add before returning"
     - bd update <task-id> --claim before dispatching
     - NEVER use isolation:"worktree" — changes are LOST
  3. WAIT for agent completion notifications
  4. When an agent returns:
     a. READ EVERY FILE IT TOUCHED — in full, not summaries
        git diff HEAD~1 -- to see what changed
     b. Run tests if they exist (pytest, python3 -m pytest)
     c. If work is WRONG: fix it yourself or dispatch a new agent
     d. If work is GOOD: bd close <task-id>
     e. git add <changed files> && git commit --no-gpg-sign
  5. After closing tasks, re-check: are new tasks now unblocked?
     If yes: dispatch them immediately (next wave)
  6. If an agent runs >10 min: kill it, attempt the task yourself or re-dispatch
```

### Phase 3: Completion

1. Verify all tasks closed: `bd list --status=open --parent=$ARGUMENTS`
2. Run full test suite if one exists
3. `bd close $ARGUMENTS`
4. Report: what was done, what was committed, any issues found during verification

## Critical Rules

- **YOU verify, not the agent.** Agent summaries describe intent, not reality. READ the files.
- **Commit after each verified task**, not in one batch at the end. This prevents lost work.
- **Keep the loop tight.** Don't pause to ask the user between waves. The whole point is autonomous execution of an already-approved plan.
- **Fix small problems yourself** rather than dispatching another agent for a 5-line fix.
- **Never dispatch >3 agents simultaneously** (memory/cost constraint).
- **If a task fails twice**, stop and report to the user rather than retrying indefinitely.
- **Subagent model defaults**: Sonnet for implementation, Haiku for pure lookups only. Never Opus for subagents.
