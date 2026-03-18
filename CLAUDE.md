# Global Development Rules

---

# Planning and Review (Beads-Based)

All plans live in beads epics. No `~/.claude/plans/` files. No ExitPlanMode. No `Mode:` fields.

## Planning Workflow

```
1. Plan:    bd create --type=epic --title="Plan: X" --design-file=<file>
            (plan text goes in epic's design field)
2. Review:  Task(subagent_type="expert-review", run_in_background=True,
              prompt="Review: epic=<epic-id> project_root=<path>")
            (single agent adopts reviewer personas from reviewers.yaml sequentially)
3. Verdict: Agent returns JSON with verdict: APPROVED/REJECTED/INCOMPLETE
            APPROVED → proceed to implementation
            REJECTED → revise design, re-run review
4. Claim:   bd update <epic-id> --status=in_progress
5. Work:    Create child tasks: bd create --type=task --parent=<epic-id> --title="Phase N: ..."
            Claim tasks: bd update <task-id> --claim
6. Verify:  Run implementation-review on completed work
7. Close:   bd close <epic-id> <task-ids...>
8. Commit:  git add <files> && git commit --no-gpg-sign
```

## Review Triggers

| When | Action |
|------|--------|
| Plan ready | `Task(subagent_type="expert-review", ...)` |
| Plan substantively edited | Re-run expert-review |
| Implementation complete | Run implementation-review |
| Expert review REJECTED | Revise epic design, re-run expert-review |

**Do NOT use**: ExitPlanMode, EnterPlanMode, `~/.claude/plans/`, `.approved` marker files, `Mode: PLANNING/IMPLEMENTATION`.

## Tiered Review

Not every decision needs a full review. Match review weight to action risk:

| Tier | When | Invocation |
|------|------|------------|
| **Full** | Plans/epics, architectural decisions | `Task(subagent_type="expert-review", run_in_background=True, prompt="Review: epic=<id> project_root=<path>")` |
| **Light** | Issue triage, priority changes, closing issues | `Task(subagent_type="expert-review", model="haiku", prompt="LIGHT REVIEW: <question>. Read {project_root}/reviewers.yaml, pick 1-2 relevant personas. Return APPROVED/REJECTED/UNCERTAIN.")` |
| **None** | Creating issues, recording KB, reading/searching | Just do it |

**Escalation chain** (bounded depth):
- Depth 0: Propose action
- Depth 1: Light review → APPROVED (execute) / REJECTED (revise) / UNCERTAIN (escalate)
- Depth 2: Full review if light was uncertain
- Depth 3: STOP. Escalate to user. Never recurse further.

## Plan Modification Rule

After ANY substantive edit to an epic's design field, re-run expert-review.
"Substantive" = new sections, changed approaches, modified checklists. NOT typos or formatting.

If the epic already has an APPROVED verdict from expert-review, the review is DONE.
Do not re-run unless the design was substantively changed after that verdict.

## Lean Plan Format

**Max 50 lines**. Plans: Objective → Phases (with `AGENT(model): task → JSON:{schema}`) → Success criterion.
**Checkpoint rule**: Every 3-5 tasks: `CHECKPOINT: kb_add, report to user, await "continue"`.

## Agent Dispatch

**Default: answer yourself.** Agents parallelize, not outsource.
- Reasoning/structural → answer yourself
- Symbolic algebra → Jupyter SageMath/SymPy
- Numerical → computational agent (Haiku/Sonnet + scripts, Jupyter only if iterating)
- Literature/KB/web search → Haiku sub-agent (10x cheaper, saves parent turns)
- Many unfamiliar files → Explore agent (Sonnet, read-only)
- 3+ parallel independent streams → Agent Team

### Reviewer Personas & Review Panel

Personas in project-specific `{project_root}/reviewers.yaml`. Invoke by name: "Review as Peskin", "use the skeptic panel".

**Auto-select triggers** (case-insensitive): "critically review", "review this", "sanity check", "verify this", "is this correct", "does this make sense", "what do you think" (about correctness).

On trigger: spawn Haiku to read `{project_root}/reviewers.yaml` and select 2-3 experts (always include Claude for anti-pattern detection). Adopt each reviewer's voice. Report as `## Review Panel: [names]` with `### [Name] ([domain]):` subsections. Skip auto-select if user specifies reviewers by name.

### Subagent Rules (MANDATORY)

- **Review agents**: always `run_in_background=True` (prevents 34GB+ memory growth)
- **Never pass `max_turns`**: omit it entirely. Use STOPPING CONDITIONS in prompt instead.
- **All agents**: kb_add before returning; parent verifies KB entry exists
- **Physics project agents only**: Include "Read docs/reference/api_signatures.md BEFORE importing from lib/" in prompt
- **All agents**: Include "For literature/KB/web search, use kb-research agent (5 rounds)" in prompt
- **All agents**: Prefer scripts over Jupyter for computation (fewer turn-wasting API errors)
- **All agents**: Include STOPPING CONDITIONS section in prompt. kb_add every 10 tool uses.
- **Output**: structured JSON with schema; caller formats for user
- **Model selection**: If `{project_root}/reviewers.yaml` has `model_calibration:`, use calibrated assignments. Otherwise default: Haiku for lookups, Sonnet for implementation, Opus for lead only (max 1 per batch). Never use a model rated WRONG for a domain in calibration.
- **KB search**: use kb-research agent (see `~/.claude/agents/kb-research.md`)
- **Agent preamble (MANDATORY)**: Every agent prompt must start with: `Read ~/.claude/agents/preamble.md FIRST, then proceed.` This file contains epistemological rules that prevent shallow search, "Not Found" = "Open", and inference-instead-of-verification failures.

**Before writing any agent prompt from a long conversation:** State the key constraint first: `"CRITICAL: the naive implementation would be X — do NOT do that. Required: Y."` Agents have no conversation history.

### Agent Task Classification

| Task Type | Signs | How to Handle |
|-----------|-------|---------------|
| **Reasoning** | "Does X connect to Y?", structural questions | Answer YOURSELF. If delegating: Sonnet with bounded scope (5 min phases). |
| **Symbolic algebra** | "Compute integral", "Factor polynomial" | Jupyter with SageMath/SymPy |
| **Numerical computation** | "Verify numerically", "Plot X" | Agent with Jupyter/numpy |
| **Hybrid** | "Compute X, then assess Y" | SPLIT: compute first, then YOU reason about result |

### Agent Teams

Use when: 3+ independent parallel streams. NOT for sequential/same-file/under-15-min work.
Rules: Max 3-4 teammates (Sonnet), Opus lead only. Assign file ownership (no concurrent edits). Lead delegates, teammates kb_add before completing.

### Scope and Timeout Rules

| Rule | Action |
|------|--------|
| **3+ parallel Opus agents** | FORBIDDEN. Use Haiku/Sonnet for at least 2. |
| **Agent running >10 min** | Likely stuck. Check output, consider killing. |
| **Agent reads >10 files without KB entry** | Scope too broad. Kill and answer yourself. |
| **Numerical Jupyter for structural theory** | Wrong tool. Use reasoning or symbolic algebra. |
| **Mixed compute+theory prompt** | SPLIT into separate agents or answer theory yourself. |
| **Agent prompt without STOPPING CONDITIONS section** | Add it. Include kb_add checkpoint every 10 tool uses. |

## Git Commit After Implementation (MANDATORY)

**After implementation-review returns APPROVED, commit your changes immediately.**

Rules:
1. **Commit ONLY files you touched** — use `git add <file1> <file2> ...` with explicit paths
2. **Never use `git add .` or `git add -A`** — other Claude sessions may be working on other files
3. **Check what's staged** — run `git status --short` before committing
4. **Use `--no-gpg-sign`** — GPG signing doesn't work in non-interactive sessions

**When NOT to commit:**
- If implementation-review returns INCOMPLETE or REJECTED
- If there are test failures
- If the user asks you to hold off on committing

## Session Management

**State lives in beads, not files.** No handoff.md, no current_plan, no work_context.json.

**Resume**: `bd list --status=in_progress` shows your active work. `bd show <epic-id>` reads the plan. `kb_list(project)` for recent findings.

**Crash recovery**: Beads state survives crashes, /clear, and compaction. Re-read the epic.

**Before context loss**: `kb_add(content="SESSION CHECKPOINT: ...\nCOMPLETED:\n- ...\nRESUME FROM: ...", tags="session-checkpoint")`

**Multi-session coordination**: Each session claims tasks with `bd update <task-id> --claim`. Two sessions cannot claim the same task. Check `bd list --assignee=<you>` for your work.

## Concurrent Edit Detection (MANDATORY)

**Problem**: Multiple Claude sessions editing the same files causes silent overwrites and wasted work.

**Before every Edit/Write**: If you have previously read the file in this session, check whether it has changed since your last read:
```bash
git diff -- path/to/file.ext
```
If the diff shows changes YOU did not make → **STOP immediately** and tell the user:

> **CONCURRENT EDIT DETECTED**: `path/to/file.ext` was modified by another session since I last read it. My planned edit may conflict. Please check which session should own this file.

Do NOT silently overwrite. Do NOT re-read and merge. STOP and inform.

**After every git commit**: Run `git status --short`. If you see modified/untracked files you didn't touch → warn the user:

> **WARNING**: Files modified by another session detected: `<list>`. Not staging these.

**During long implementations**: Periodically run `git status --short` (every 5-10 edits). If unexpected changes appear, STOP.

**Symptoms that indicate another agent is active on your files**:
- Edit tool fails because `old_string` no longer matches (file changed under you)
- `git diff` shows changes in files you haven't edited yet
- `git status` shows modifications to files outside your task scope
- Build failures from incompatible changes you didn't make

**On any of these symptoms**: STOP. Do not try to "fix" the conflict yourself. Inform the user which files are affected and what you were trying to do.

---

# Rules

**Hook blocks are FINAL.** If a hook blocks your tool call (exit 2), STOP. Do not rephrase, restructure, split into smaller pieces, use a different tool, or find any other way to achieve the same blocked action. Tell the user what was blocked and why. The hook exists because the user wants that action prevented — working around it is a direct violation of user intent.

kb-research agent before implementation. Enforced by hook.

Before implementing ANY new function/struct/algorithm:
1. `rg "similar_name\|related_term"` across codebase
2. Read *.md docs in the directory
3. If uncertain, use Task/Explore agent to find related code
4. If you find existing code, USE IT instead of reimplementing

This is your #1 failure mode (135 complaints in history). Warned by hook, but you must actually check.

No mocks, stubs, or fake data. Use real hardware/files. If demo data needed, user will say so.

Inline scripts (heredocs, python -c): computation only.
- No comments, no docstrings
- print() only for computation results (variables, expressions)
- Never print explanatory text, headers, separators, or labels
- Explanations go in conversation text, not in scripts

Any code worth keeping is worth saving as a file.

No `git add -A`, `git add .`, `git reset --hard`, `git push --force`.

No markdown file creation unless requested. Enforced by hook.

## Decision Authority (resolves apparent contradictions)

Three levels of decision-making. Apply the FIRST matching level:

**Level 1 — Light review decides** (state-changing assessments):
Closing issues, reprioritizing, ranking research, declaring something "done" or "failed".
→ Gather evidence → light review (see Tiered Review) → execute if APPROVED → report to user.

**Level 2 — You decide, then do it** (implementation & execution):
Writing code, running tests, searching, reading, creating issues, recording KB.
→ No "Should I proceed?" — just do it. Don't ask the user for permission on execution steps.
→ **Record rejected alternatives**: When choosing between approaches, create `idea` type bd issues for the paths not taken, so they survive context compaction and can be revisited if the chosen path fails.

**Level 3 — User decides** (resource allocation & preference):
Claiming tasks for implementation, choosing which research direction to pursue next, architectural decisions with multiple valid options.
→ Use `AskUserQuestion` tool. Never open-ended prompts ("What would you like..."). Present concrete options.

NEVER: "What would you like...", "Would you like me to...", "Should I...", numbered option lists in prose.

**Goal Transformation**: Transform vague tasks to verifiable form:
- "Fix the bug" → "Write test that reproduces it, make it pass"
- "Add validation" → "Write tests for invalid inputs, make them pass"
- "Refactor X" → "Ensure tests pass before AND after"

# Anti-Patterns

| If you write... | STOP because... |
|-----------------|-----------------|
| Print-heavy scripts / notebook presentation | Blocked by hooks (block-print-spam.sh, block-presentation-cells.sh). See Jupyter section for rules. |
| Any comment in notebook | No comments of any kind. Not `# Setup`, not `# TODO`, nothing. Just code. |
| `I believe` / `This likely` / `This probably` | Speculation without verification. Run code, verify from data. |
| `Should I proceed?` / `What would you like...` / `What should I...` | Just do it. Options → `AskUserQuestion` tool. Never open-ended prompts. |
| Reading parent directory for subdirectory work | Check pwd. Read requested files. Stay where told. |
| `DEBUG` / `Status:` / extra labels in output | Output only what was asked. Minimal, clean, relevant. |
| Columns don't line up / inconsistent spacing | Test output visually. Fixed-width fields. Verify alignment. See "Table Formatting" section. |
| Box-drawing table (┌┬┐├┼┤└┴┘│─) | NEVER. Use: `Header  Col2\n-------  ----\nval1     val2` (dashes + spaces only) |
| "Extracted 50,000" when expecting ~10 | Sanity check results. If output seems wrong, it is. |
| `Should I use X or Y?` / `What is the correct approach?` | You're the expert. Figure it out yourself. |
| "promising" / "straightforward" / "just needs" without reading implementation | **SHALLOW ASSESSMENT**. Read actual code, check FAILURES.md, run full 5-round kb search. Stopping at round 2 because you "have enough" is the #1 research failure mode. |
| "pending" / "untested" / "open question" without 3+ search strategies | **"Not Found" ≠ "Open"**. Cite the searches that returned no results. Check KB (with project=None), tex drafts, code, and other worktrees. If you searched once, you haven't searched. |
| kb_search with project filter only, no project=None query | **CROSS-PROJECT BLINDNESS**. 150+ findings exist under variant project names. First query must be unfiltered. |
| kb-research returns `files_to_read`, parent doesn't read them | **INCOMPLETE RESEARCH**. The kb-research agent's `files_to_read` and `conflicts` fields exist because the agent found leads it couldn't fully resolve. YOU must read them. |
| Agent prompt without `Read preamble.md` instruction | **PREAMBLE MISSING**. Every agent prompt must start with preamble. Without it, agents make shallow-search and inference-over-verification mistakes. |
| Discovery without `kb_add` | kb_add immediately after any finding. |
| Research agent returns without KB entry | Agent prompts MUST include KB recording instruction. Parent verifies. |
| Calling `kb_search()` directly (main agent) | Spawn kb-research agent instead. See `~/.claude/agents/kb-research.md`. |
| Haiku search with single round of queries | **SHALLOW SEARCH**. Use iterative template (5 rounds, 12 turns): seed → follow-up → cross-ref → tex/code → contradiction check. |
| Search returns results, agent doesn't follow up | **Each round's queries must come from PREVIOUS round's results.** Extract terms, chase kb_get cross-refs, form new queries. |
| Mixing conventions (bit-pattern vs gamma, two definitions of same thing) | One codebase = one convention. Check existing code first. |
| Creating duplicate section/KB entry | Search before writing. Consolidate, don't duplicate. |
| "Let me fix this" without identifying root cause | State the bug first. "The bug is X because Y. Fixing by Z." |
| Starting implementation without expert-review APPROVED | Run `Task(subagent_type="expert-review", ...)` first for epics. Light review or none for tasks. |
| `TaskUpdate(status="completed")` then summarizing to user | Run implementation-review BEFORE reporting results. Task completion ≠ review complete. |
| "Let me take a simpler approach" / "Given the complexity" | Problem has grown beyond initial plan. STOP. Create a new epic: `bd create --type=epic --title="Revised: X"`. |
| Adding notebook cell to fix syntax error in previous cell | Use `modify_notebook_cells` with `operation="edit_code"` and `position_index=N` to fix the broken cell in place. |
| ExitPlanMode / EnterPlanMode / `~/.claude/plans/` | DEPRECATED. Use beads epics for all plans. |
| `Task(..., max_turns=N, ...)` | Hard turn limits cut agents off mid-tool-call. Omit max_turns entirely. Use STOPPING CONDITIONS in prompt. |
| Agent misuse (3+ Opus, >10min stuck, 10+ files w/o KB, mixed compute+theory) | See Scope and Timeout Rules. Split compute from theory, kill stuck agents. |
| Dispatching agents to implement X from a long conversation | Agents have NO conversation history. State the key constraint first: "The naive implementation would be Y — DO NOT do that." |
| Agent returns result, accepting without checking key constraint | Before summarizing agent output to user, explicitly verify: does this satisfy the non-obvious constraint stated in the prompt? |
| Hook blocks tool call, then rephrasing/splitting/using different tool to do same thing | Hook blocks are FINAL. STOP and tell the user what was blocked. Do not work around hooks. |
| Edit fails with "old_string not found" unexpectedly | Another session may have modified the file. Run `git diff -- file` and STOP if changes aren't yours. See "Concurrent Edit Detection". |
| `git status` shows files you didn't touch as modified | Another session is active. STOP, warn user, do not stage those files. |
| Silently re-reading and continuing after unexpected file change | NEVER. If a file changed under you, STOP and inform the user. Do not auto-merge or silently adapt. |

# Build Waiting Protocol

**Never poll `build-manager status` in a loop** — busy-loop anti-pattern.

**Short builds (< 10 min expected):**
```bash
build-manager start --sync . "ninja -C build -j32"   # Bash timeout=600000
```
Returns directly with success/failure. No waiting needed.

**Long builds (≥ 10 min expected):**
```bash
# 1. Start async
build-manager start . "ninja -C build -j32"

# 2. Create team + spawn monitor (Haiku, run_in_background=True)
TeamCreate(team_name="build-watch-<project>")
Task(subagent_type="build-monitor", team_name="...",
     prompt="Monitor build at /abs/path/to/project. I am [your-name].",
     run_in_background=True)

# 3. Stop. Agent wakes you when done via SendMessage.
```

| Pattern | Anti-pattern |
|---------|-------------|
| `--sync` + timeout=600000 for short builds | `build-manager status` in a loop |
| Team + build-monitor for long builds | `build-manager wait` without team |
| Stop and wait for agent message | Repeated TaskOutput polling |

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

# Task Tracking (bd/Beads)

Use `bd` for ALL task and plan tracking. Never use markdown TODOs, comment-based task lists, or `~/.claude/plans/`.

**On session start in any project**: If `.beads/` directory doesn't exist, run `bd init` to initialize, then `bd setup claude` to install hooks.

**Workflow**:
```
bd ready                    # Show work with no blockers
bd create --title="..." --type=task  # Create issue
bd update <id> --claim      # Claim work
bd close <id>               # Mark complete
bd prime                    # Load full workflow context (auto-runs via hooks)
```

**Planning**:
```
bd create --type=epic --title="Plan: X" --design-file=plan.md   # Create plan epic
bd show <epic-id>           # Read plan (design field)
Task(subagent_type="expert-review", prompt="Review: epic=<id> project_root=<path>")  # Review
bd update <epic-id> --status=in_progress                        # Start implementation
bd close <epic-id>          # Complete
```

**Issue types**: bug, feature, task, epic, chore, decision. **Priorities**: 0 (critical) to 4 (backlog).

# KB Access

| Operation | Direct Call? | Notes |
|-----------|--------------|-------|
| kb_search | NO | Spawn kb-research agent — its internal calls satisfy the Edit/Write gate |
| kb_add | YES | Recording findings |
| kb_correct | YES | Fixing findings |
| kb_get | YES | Reading known ID |
| kb_list | YES | Session resume |

**Before Edit/Write**: Spawn `kb-research` agent. Hook enforces this.

**Base case**: Spawning kb-research does NOT require pre-search.
The agent's internal kb_search calls satisfy the gate for you.

**Template**: `Task(subagent_type="kb-research", model="haiku", prompt="TOPIC: {x}")`
Full template: See `~/.claude/agents/kb-research.md`

Tags: proven|heuristic|open-problem, core-result|technique|detail

# Jupyter Notebooks (Computation Only)

Jupyter is for **computation only** — no markdown cells, no comments of any kind, no print() labels. The notebook is a calculator; you explain results in your response.

**Rules:**
- No markdown cells, no `# comments`, no docstrings, no print labels
- Before importing from lib/: `Read` the module to verify signatures (rg-before-new-code applies)
- Check server: `query_notebook("test", "check_server", server_url="http://localhost:8888")` — fall back to script if not running
- Reusable cells (called 2+ times or worth testing) → extract to `lib/`
- SageMath requires SageMath kernel; Maple use `maple_proxy` kernel with `%maple` prefix and semicolons

**When to use:** numeric checks, hypothesis exploration, SageMath/Maple algebra, plots. Use scripts for reusable computation and CI tests. Create notebooks in project's `notebooks/` directory.

**Full usage examples, token optimization, kernel setup:** See `~/.claude/docs/reference/agent-prompts.md §Jupyter`.

# Tool Output Truncation

**Always use truncation parameters** to limit tool output tokens:

| Tool | Parameter | Usage |
|------|-----------|-------|
| Grep | `head_limit=20` | First 20 matches (default unlimited) |
| Grep | `output_mode="files_with_matches"` | Just paths, no content |
| Read | `limit=100` | First 100 lines of large files |
| Read | `offset=50, limit=50` | Lines 50-100 only |
| Glob | Pattern specificity | `**/*.py` not `**/*` |

**Decision tree**:
1. Need file existence? → `Grep output_mode="files_with_matches" head_limit=5`
2. Need line numbers? → `Grep output_mode="content" head_limit=20`
3. Need file structure? → `Read limit=50` (imports/class defs at top)
4. Need specific section? → `Read offset=X limit=Y` after finding line with Grep

**Anti-patterns**:
- `Read` entire 1000-line file when only checking imports
- `Grep` without `head_limit` on broad patterns
- `Glob **/*` instead of `Glob **/*.specific_ext`

# Response Terseness

**Minimize output tokens** in responses:

| Instead of | Write |
|------------|-------|
| "I'll now read the file to understand..." | "Reading file." |
| "Let me search for..." | (just do it, no announcement) |
| "Based on my analysis, I found that..." | "Found:" |
| "The error occurs because..." | "Error: X. Fix: Y." |
| Repeating user's question back | (skip, go straight to answer) |
| "I've successfully completed..." | "Done." |

**Structure rules**:
- Tables over prose for comparisons
- Bullets over paragraphs for lists
- Code over description when showing syntax
- One sentence max for simple confirmations

**Anti-patterns**:
- "I'll now..." / "Let me..." / "I'm going to..." (just do it)
- "As you requested..." / "As mentioned..." (redundant)
- "Successfully" / "I was able to" (implied by result)
- Explaining what tool you're about to use (just use it)

# Table Formatting

**NEVER use box-drawing characters** (┌ ─ ┬ │ etc.) for tables. They truncate unpredictably.

**Required format**: Pre-measured fixed-width with dashes:
```
Casimir  Mult  Composition
-------  ----  ---------------------
0        1     (1,0,0,0)
1/6      1     (0,1,0,0)
7/24     4     Mixed superpositions
```

**Rules**:
1. Measure ALL content before rendering (find longest item per column)
2. Set column width = max(header_len, max_content_len) + 2 padding
3. Use spaces for alignment, dashes for header separator only
4. No vertical bars, no box corners, no grid lines

**Anti-pattern**: Deciding column width from header, then truncating content to fit.

# "Not Found" Is Not "Open"

**CRITICAL DISTINCTION**: When you can't find something, that means YOU haven't found it, not that it doesn't exist.

**Before declaring something "open", "incomplete", or "unresolved"**:

1. **Use kb-research agent** (5 rounds, tries multiple phrasings)
2. **Search code for implementations**: `rg "relevant_term" lib/`
3. **Cross-check comments vs implementations**: Trust code over comments

**Phrasing rules**:

| Wrong | Right |
|-------|-------|
| "This is an open question" | "I found no KB finding or implementation for this" |
| "No KB finding exists for X" | "kb-research agent returned no results for X (tried: [queries])" |
| Trusting a "TODO" comment | Search for implementations that may have been added after comment |

# Truth Hierarchy: Code > Comments > KB

When sources disagree, follow this precedence:

1. **Test assertions** — ground truth
2. **Code implementations** — what actually happens
3. **Recent KB findings** — documented understanding
4. **Code comments** — often stale
5. **Old KB findings** — may be superseded

**When you find inconsistency**: Note conflict, determine which is correct (run code, check tests), file `kb_correct()` or suggest code edit.

**Stale comment detection**: When reading a comment claiming something is "open" or "TODO" — IMMEDIATELY search for implementations that contradict it.

# KB Guidelines

**Recording Findings**: After ANY discovery, failure, or verification:
`kb_add(content, finding_type, project="PROJECT", tags)` — this call is OK to do directly

Finding types: `success`, `failure`, `discovery`, `experiment`
Tags: `proven`/`heuristic`/`open-problem`, domain-specific

**Good Finding Structure**: Title = direct fact statement. Content = self-contained. Code ref = file:function.

**Maintenance** (requires `knowledge-base-advanced` server): `kb_review_queue`, `kb_suggest_consolidation`, `kb_validate`

# Incompleteness Tracking

**Invariant**: Every incompleteness marker in committed code has a corresponding bd issue.

## Markers scanned (all domains)

| Domain | Markers | Severity |
|--------|---------|----------|
| Code | TODO, FIXME, XXX, HACK, STUB | Must have bd issue before commit |
| Code | assert(false), NotImplementedError, unimplemented!() | Must have bd issue before commit |
| Lean | sorry, admit | CRITICAL — proof incomplete, must track |
| Lean | trivial on complex goals | WARNING — may hide proof gap |
| Lean | axiom (non-axiomatic) | WARNING — should be theorem/lemma |
| Lean | native_decide, Decidable.decide | WARNING — bypasses kernel |
| Lean | decreasing_by sorry | CRITICAL — well-foundedness unproven |
| Lean | placeholder | CRITICAL — incomplete tactic |
| Lean | dbg_trace | WARNING — debug output, never commit |
| Coq | Admitted, admit | CRITICAL — proof incomplete |

## Workflow

1. During implementation: markers generate warnings (not blocks)
2. At commit time: markers without bd issues → BLOCKED
3. At review time: implementation-review checks marker↔issue linkage
4. Resolution: either complete the work or create `bd create -t task "..." -p P2`

## Anti-patterns

| Pattern | Problem |
|---------|---------|
| Commit with sorry, no bd issue | Proof gap lost to history |
| "Will fix later" without tracking | Later never comes |
| axiom for provable statement | Soundness hole |
| trivial on ∀∃ goal | May silently produce wrong proof |
| 46 open / 0 in-progress bd issues | Lifecycle not tracked |

# Issue Lifecycle (MANDATORY)

When starting implementation of a bd issue: `bd update <id> --status in-progress`
When committing code that resolves a bd issue: commit message must contain `fixes <id>`
When implementation-review returns APPROVED: close all referenced bd issues

Post-commit hook (`bd-lifecycle.sh`) auto-closes issues referenced with `fixes`/`closes`/`resolves` in commit messages.
