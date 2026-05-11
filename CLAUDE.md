# Global Development Rules

---

# Planning and Review (Beads-Based)

All plans live in `~/.claude/plans/PLAN-<slug>.md` files AND are referenced from beads epics via `--design-file`. No ExitPlanMode. No `Mode:` fields.

## Planning Workflow

```
1. Plan:    Write plan file: ~/.claude/plans/PLAN-<slug>.md
2. Epic:    bd create --type=epic --title="Plan: X" --design-file=~/.claude/plans/PLAN-<slug>.md
3. Review:  Task(subagent_type="expert-review", prompt="FULL REVIEW: epic=<id> plan=<path> project_root=<path>")  -- non-persistent
4. Verdict: APPROVED → proceed; REJECTED → revise plan, re-run review
5. Claim:   bd update <epic-id> --status=in_progress
6. Work:    bd create --type=task --parent=<epic-id> --title="Phase N: ..."; bd update <task-id> --claim
7. Verify:  Task(subagent_type="implementation-review", prompt="epic=<epic-id> project_root=<path>")  -- non-persistent
8. Close:   bd close <epic-id> <task-ids...>
9. Commit:  git add <files> && git commit --no-gpg-sign
```

## Epic Trigger (MANDATORY)

Create a beads epic with child tasks if ANY of these are true:
- 3+ implementation phases; 5+ files modified; work cannot complete before context compaction; multi-session coordination.

Use an agent team when 2+ phases are independent and touch different code sections.

## Tiered Review

"The first principle is that you must not fool yourself—and you are the easiest person to fool." (Feynman).

| Tier | When | Invocation |
|------|------|------------|
| **Full** | Plans/epics, architectural decisions | `Task(subagent_type="expert-review", prompt="FULL REVIEW: epic=<id> plan=<path> project_root=<path>")` |
| **Light** | Issue triage, priority changes, closing issues | `Task(subagent_type="expert-review", model="haiku", prompt="LIGHT REVIEW: epic=<id> project_root=<path>")` |
| **None** | Creating issues, recording KB, reading/searching | Just do it |

**Reviews are ALWAYS non-persistent.** Use `Task(subagent_type="expert-review", ...)` directly — NEVER `bd mol wisp mol-expert-review` (creates 6+ wisp-* tasks per review that never auto-close and pollute `bd ready` / `bd list`). Review verdicts return inline to the dispatching session; persistence is unwanted. Applies to all review types: full, light, implementation-review.

**Escalation chain** (bounded depth): Depth 0: propose. Depth 1: light review. Depth 2: full review. Depth 3: STOP, escalate to user.

**Do NOT use**: ExitPlanMode, EnterPlanMode, `.approved` marker files, `Mode: PLANNING/IMPLEMENTATION`, `bd mol wisp mol-expert-review`, `bd mol wisp mol-implementation-review`.

## Session Management

**State lives in beads.** No handoff.md, no work_context.json.

**Resume**: `bd list --status=in_progress` → `bd show <epic-id>` → `kb_list(project)`.

**Before context loss**: `kb_add(content="SESSION CHECKPOINT: ...", tags="session-checkpoint")`

**Persistent memory**: `bd remember "insight"`. Retrieve with `bd memories <keyword>`. NOT MEMORY.md files.

## Agent Dispatch

**Default: answer yourself.** Agents parallelize, not outsource.

| Task Type | How to Handle |
|-----------|---------------|
| Reasoning / structural | Answer yourself |
| Symbolic algebra | Jupyter SageMath/SymPy |
| Numerical | Agent + scripts (Jupyter only if iterating) |
| KB / literature search | Haiku kb-research agent (5 rounds) |
| 3+ parallel streams | Agent Team |

**Subagent rules (MANDATORY)**:
- Review agents: `run_in_background=True`
- Never pass `max_turns`; use STOPPING CONDITIONS in prompt instead
- Every prompt: start with `Read ~/.claude/agents/preamble.md FIRST`
- Include `kb_add before returning` in every agent prompt
- Structured JSON output with schema
- Model defaults: Haiku for lookups, Sonnet for implementation, Opus lead only (max 1/batch)
- **VERIFY AGENT WORK (MANDATORY)**: when an agent writes or modifies a script, proof, or production code, the dispatching Claude process MUST Read the artifact and verify it implements what was requested BEFORE accepting the result. Agent summaries describe intent, not what landed. Read scripts before reporting their findings; read Lean proofs before claiming sorrys are discharged; read tests before claiming they pass. Negative results from agents in particular must be re-checked against the prompt — a "negative" often means the agent computed the wrong object.
- **AGENTS MUST READ, NOT GREP (MANDATORY)**: when dispatching audit/inventory tasks (sorry counts, theorem inventories, file-content claims), the prompt MUST instruct the agent to **Read each required file in full** rather than `grep` for keywords. `grep sorry` matches comments, docstrings, and TODO notes — not actual proof obligations. Same for `grep axiom`, `grep TODO`, etc. The Lean attribute that matters is the proof body of `theorem`/`lemma` declarations, which only Read can disambiguate. Apply this whenever an agent's output is a count or list extracted from source files.

**Agent preamble**: `"CRITICAL: the naive implementation would be X — do NOT do that. Required: Y."` (agents have no conversation history)

### Worktree Isolation Rules (MANDATORY)

`isolation: "worktree"` is AUTO-DELETED when agent completes. Changes are LOST.

| Use case | Correct approach |
|----------|-----------------|
| Implement a feature | Work directly in main tree |
| Implement on a branch | `git checkout -b`, work in main tree |
| Parallel implementation | `git worktree add .worktrees/<name>`, no isolation param |
| Read-only exploration | `isolation: "worktree"` is OK |

**Cost of getting this wrong:** Agent work is lost. This has happened.

### Scope and Timeout Rules

| Rule | Action |
|------|--------|
| 3+ parallel Opus agents | FORBIDDEN |
| Agent running >10 min | Likely stuck. Kill. |
| Agent reads >10 files without KB entry | Scope too broad. Kill and answer yourself. |
| Mixed compute+theory prompt | SPLIT |
| No STOPPING CONDITIONS section | Add it |

## Concurrent Edit Detection (MANDATORY)

**Before every Edit/Write**: `git diff -- path/to/file.ext`. If changes you didn't make: **STOP**.

> **CONCURRENT EDIT DETECTED**: `path/to/file.ext` modified by another session. Do NOT silently overwrite.

**After every git commit**: `git status --short`. Warn if unexpected files are modified.

---

# Rules

**Hook blocks are FINAL.** If a hook blocks your tool call (exit 2), STOP. Do not rephrase, restructure, or use a different tool to do the same thing. Tell the user what was blocked and why.

kb-research agent before implementation. Enforced by hook.

Before implementing ANY new function/struct/algorithm: `rg "similar_name"` across codebase; read *.md docs in directory; use Task/Explore agent if uncertain. USE existing code instead of reimplementing. This is your #1 failure mode.

No mocks, stubs, or fake data.

No backwards compatibility. No wrappers. No forwarding functions. No aliases. No dead code. DELETE wrong/superseded code — git history preserves it.

Inline scripts: computation only. No comments, no docstrings, no print labels.

No `git add -A`, `git add .`, `git reset --hard`, `git push --force`.

## Decision Authority

**Level 1 — Light review decides**: closing issues, reprioritizing, declaring done/failed.

**Level 2 — You decide, then do it**: writing code, running tests, searching, recording KB. No "Should I proceed?" Scale detection: if >1 context window, create epic + team first.

**Level 3 — User decides**: claiming tasks, choosing research direction, architectural decisions with multiple valid options. Use `AskUserQuestion`. Never open-ended prompts.

NEVER: "What would you like...", "Would you like me to...", "Should I..."

# Anti-Patterns (key entries; hook-enforced entries removed)

| If you write... | STOP because... |
|-----------------|-----------------|
| `I believe` / `This likely` / `This probably` | Speculation. Run code, verify from data. |
| Box-drawing table (┌┬┐├┼┤└┴┘│─) | NEVER. Use dashes + spaces only. |
| "promising" / "straightforward" / "just needs" without reading implementation | SHALLOW ASSESSMENT. |
| "pending" / "untested" / "open question" without 3+ search strategies | "Not Found" ≠ "Open". Cite searches. |
| kb_search with project filter only | CROSS-PROJECT BLINDNESS. First query must be unfiltered. |
| Agent prompt without `Read preamble.md` | PREAMBLE MISSING. |
| `old_name = new_name` / RuntimeError stub | NO BACKWARDS COMPATIBILITY. Delete the old function. |
| Starting epic without expert-review | ALL epics get expert-review first. No exceptions. |
| `Task(..., max_turns=N, ...)` | Use STOPPING CONDITIONS instead. |
| Dispatching agents to implement from long conversation | State key constraint first: "naive impl = X, DO NOT do that." |
| Hook blocks tool call, then rephrasing/splitting | Hook blocks are FINAL. STOP. |
| Blending two contradictory patterns to satisfy both | CONFLICT AVERAGING. Pick one (newer/more tested), justify it, flag the other for cleanup. Don't satisfy both. |
| Test asserts function returned *something* (truthy, non-null, has key) | INTENT-FREE TEST. Assert the *correct* value for a *stated reason*. A test that can't fail when business logic changes is wrong. |

# Background Bash Output — NEVER PIPE

`run_in_background=true` writes stdout to a file. Shell pipes (`| tail`, `| head`) consume output BEFORE it reaches the file.

**Rule**: NEVER use `| tail` / `| head` in a Bash call with `run_in_background=true`. Run without pipe; read file afterward.

# Build Waiting Protocol

Short builds (< 10 min): `build-manager start --sync . "ninja ..."` with `timeout=600000`.

Long builds (≥ 10 min): `build-manager start . "ninja ..."` then spawn `build-monitor` agent with `run_in_background=True`. Stop and wait for agent message.

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

# Task Tracking (bd/Beads)

Use `bd` for ALL task and plan tracking. Never use markdown TODOs.

**Session start**: if `.beads/` doesn't exist, run `bd init` then `bd setup claude`.

```
bd ready                    # Show work with no blockers
bd create --title="..." --type=task
bd update <id> --claim
bd close <id>
bd prime                    # Load full workflow context
```

**bd failure recovery**: `bd doctor` → check `ps aux | grep bd` → restore from `.beads/backup/`.

**bd notes/description format**: use a single-line `--notes "..."` or `--description "..."` argument with plain text. **Hooks block** long heredocs (`<<EOF` > ~30 lines) AND writing `.md` files in `.beads/` or anywhere unrequested. For long content: keep notes concise (1-2 paragraphs of plain prose, no markdown tables, no bullet lists across many lines), or split into multiple `bd update --notes` calls (note: each replaces the prior — last one wins), or store the long content as a `kb_add` entry and put the kb-id in the bd note. Don't write to `.md` files; don't try heredocs >30 lines.

# KB Access

| Operation | Direct Call? |
|-----------|--------------|
| kb_search | NO — spawn kb-research agent |
| kb_add | YES |
| kb_correct | YES |
| kb_get | YES |
| kb_list | YES |

**Template**: `Task(subagent_type="kb-research", model="haiku", prompt="TOPIC: {x}")`

Tags: proven|heuristic|open-problem, core-result|technique|detail

# Jupyter Notebooks (Computation Only)

No markdown cells, no `# comments`, no docstrings, no print labels.

Check server: `query_notebook("test", "check_server", server_url="http://localhost:8888")`.

**When to use**: numeric checks, hypothesis exploration, SageMath/Maple algebra, plots. Scripts for reusable computation and CI tests.

# Output Discipline

**Truncation parameters**: Grep `head_limit=20`; Read `limit=100`; Glob `**/*.py` not `**/*`.

**Terseness**: Tables > prose. Bullets > paragraphs. No "I'll now..." / "Let me..." / "Successfully".

**Table format**: dashes + spaces only. NEVER box-drawing characters. Measure all content before rendering.

# "Not Found" Is Not "Open"

Before declaring something "open": use kb-research (5 rounds); `rg "relevant_term" lib/`; trust code over comments.

# Truth Hierarchy: Code > Comments > KB

Test assertions > code > recent KB > comments > old KB.
