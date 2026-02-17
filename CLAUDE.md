# Global Development Rules

**For physics-specific methodology, gatekeepers, and computation rules**: See project `CLAUDE.md`

---

# Review Agents (MANDATORY)

| When | Agent | Action |
|------|-------|--------|
| Before ExitPlanMode | `expert-review` until APPROVED | Check plan before presenting it |
| code complete | `implementation-review` until APPROVED | Check correctness, verify archival |
| Implementation complete | `implementation-review` until APPROVED | Prove you're done to experts |
| Expert review corrections applied | `expert-review` until APPROVED | Plan changed, re-reviewed required |

**Triggers for implementation-review**: "done", "complete", "tests pass" (session-end gate — not per-file)
**Triggers for expert-review**: "plan ready", before ExitPlanMode

## Agent Dispatch

**Default: answer yourself.** Agents parallelize, not outsource.
- Reasoning/structural → answer yourself
- Symbolic algebra → Jupyter SageMath/SymPy
- Numerical → computational agent (Haiku/Sonnet + scripts, Jupyter only if iterating)
- Literature/KB/web search → Haiku sub-agent (10x cheaper, saves parent turns)
- Many unfamiliar files → Explore agent (Sonnet, read-only)
- 3+ parallel independent streams → Agent Team

### Reviewer Personas & Review Panel

Personas in `~/.claude/reviewers.yaml`. Key panels: `technical_review` (Peskin+Anderson+Connes), `popular_writing` (Sagan+Feynman+Munroe+Orwell), `skeptic_panel` (Mencken+Russell+'t Hooft). Invoke by name: "Review as Peskin", "use the skeptic panel".

**Auto-select triggers** (case-insensitive): "critically review", "review this", "sanity check", "verify this", "is this correct", "does this make sense", "what do you think" (about correctness).

On trigger, spawn Haiku to select panel:
```python
Task(subagent_type="general-purpose", model="haiku", prompt=f"""
Read ~/.claude/reviewers.yaml, select 2-3 experts for: {summary}. PROJECT: {project}.
ALWAYS include Claude for anti-pattern detection.
Return ONLY JSON: {{"panel": [{{"name":str,"domain":str,"focus":[str]}}], "reason":str}}
""")
```
Then adopt each reviewer's voice. Report as: `## Review Panel: [names]` with `### [Name] ([domain]):` subsections. Skip auto-select if user specifies reviewers by name.

### Subagent Rules (MANDATORY)

- **Review agents**: always `run_in_background=True` (prevents 34GB+ memory growth)
- **All agents**: kb_add before returning; parent verifies KB entry exists
- **Physics project agents only**: Include "Read docs/reference/api_signatures.md BEFORE importing from lib/" in prompt
- **All agents**: Include "For literature/KB/web search, use kb-research agent (5 rounds, 12 turns)" in prompt
- **All agents**: Prefer scripts over Jupyter for computation (fewer turn-wasting API errors)
- **Turn budget**: ALWAYS set `max_turns` on Task calls. Include TURN BUDGET section in prompt (see agent-prompts.md). Agents killed without kb_add lose ALL work.
- **Output**: structured JSON with schema; caller formats for user. Mandatory suffix: `Return ONLY valid JSON. Schema: {[fields]}`
- **Model selection**: Haiku for lookups/existence checks, Sonnet for implementation, Opus for lead only (max 1 per batch)
- **KB search**: use kb-research agent (see `~/.claude/agents/kb-research.md`)

**Agent prompts, templates, expert panels:** See `~/.claude/docs/reference/agent-prompts.md`

### Agent Task Classification

| Task Type | Signs | How to Handle |
|-----------|-------|---------------|
| **Reasoning** | "Does X connect to Y?", structural questions | Answer YOURSELF. If delegating: Sonnet with bounded scope (5 min phases). |
| **Symbolic algebra** | "Compute integral", "Factor polynomial" | Jupyter with SageMath/SymPy |
| **Numerical computation** | "Verify numerically", "Plot X" | Agent with Jupyter/numpy |
| **Hybrid** | "Compute X, then assess Y" | SPLIT: compute first, then YOU reason about result |

### Agent Teams

Use when: 3+ independent parallel streams. NOT for sequential/same-file/under-15-min work.
Rules: Max 3-4 teammates (Sonnet), Opus lead only. Assign file ownership (no concurrent edits). Lead delegates (Shift+Tab), teammates kb_add before completing. Lead runs expert-review on combined output.

### Scope and Timeout Rules

| Rule | Action |
|------|--------|
| **3+ parallel Opus agents** | FORBIDDEN. Use Haiku/Sonnet for at least 2. |
| **Agent running >10 min** | Likely stuck. Check output, consider killing. |
| **Agent reads >10 files without KB entry** | Scope too broad. Kill and answer yourself. |
| **Numerical Jupyter for structural theory** | Wrong tool. Use reasoning or symbolic algebra. |
| **Mixed compute+theory prompt** | SPLIT into separate agents or answer theory yourself. |
| **Agent spawned without max_turns** | FORBIDDEN. Always set max_turns (see agent-prompts.md). |
| **Agent prompt without TURN BUDGET section** | Add it. Agents terminated without kb_add lose ALL work. |

## Plan Session Isolation

Your current plan file path is stored in `~/.claude/sessions/<session-id>/current_plan`.
- Written automatically by hook when you create/edit a plan in `~/.claude/plans/`
- Session ID comes from `/tmp/claude-kb-state/session-<PPID>`
- Read this file to know YOUR plan (don't use `find | head -1`)
- After implementation-review APPROVED: plan is automatically archived by the agent

## Git Commit After Implementation (MANDATORY)

**After implementation-review returns APPROVED, commit your changes immediately.**

Rules:
1. **Commit ONLY files you touched** — use `git add <file1> <file2> ...` with explicit paths
2. **Never use `git add .` or `git add -A`** — other Claude sessions may be working on other files
3. **Check what's staged** — run `git status --short` before committing to verify you're only committing your changes
4. **Use `--no-gpg-sign`** — GPG signing doesn't work in non-interactive sessions

Example workflow:
```bash
# Check what you modified
git status --short

# Add ONLY the files you changed for this implementation
git add path/to/file1.py path/to/file2.py

# Verify staging
git status --short

# Commit with descriptive message
git commit --no-gpg-sign -m "Brief description of changes

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

**When NOT to commit:**
- If implementation-review returns INCOMPLETE or REJECTED
- If there are test failures
- If the user asks you to hold off on committing

### implementation-review Prompt Formats

Supported invocation formats (ARCHIVE state handles all):
1. `Review: session://{id}` — Caller creates session dir with context.yaml and current_plan
2. `Review: ~/.claude/plans/name.md` — Direct path, no session setup needed
3. `Review: /absolute/path/to/plan.md` — Absolute path
4. `Review: name.md` — Relative, expands to `~/.claude/plans/`

Hook `plan-write-review.sh` writes `current_plan` when a plan file is edited.

## Plan Modification Rule

**After ANY substantive edit to a plan file, re-run expert-review before ExitPlanMode.**

"Substantive" means: adding new sections/examples, changing recommended approaches, modifying checklists/anti-pattern tables, incorporating reviewer feedback.

Does NOT require re-review: typo fixes, renumbering sections, formatting changes.

## Plan Presentation Requirements

When presenting a plan for approval, include:
1. **Review status**: Whether expert-review was run and final verdict (APPROVED/iterations required)
2. **Revision summary**: If modifications were required, summarize key changes made
3. **Experts consulted**: List which domain experts reviewed the plan (e.g., physics, architecture, security)

## ExitPlanMode Workflow

**Expert-review loop** (runs in background to prevent memory growth):
```
1. Task(subagent_type="expert-review", run_in_background=True, ...)
2. task_id = result from Task call
3. output = TaskOutput(task_id, block=True, timeout=120000)
4. Parse verdict from output (APPROVED / REJECTED / INCOMPLETE)
5. If REJECTED or INCOMPLETE: revise plan, go to step 1
6. If APPROVED: append ## Approval Status and call ExitPlanMode
```
Do NOT call ExitPlanMode until TaskOutput returns APPROVED.

Before ExitPlanMode, append `## Approval Status` with `expert-review: APPROVED`, `User: PENDING`, `Mode: PLANNING`.
On resume: check `Mode:` — if `IMPLEMENTATION`, execute plan (don't call ExitPlanMode again).
PostToolUse hook `plan-mode-approved.sh` updates `Mode: PLANNING` → `Mode: IMPLEMENTATION` automatically when user approves ExitPlanMode.

**CRITICAL:** If session resumes with `Mode: IMPLEMENTATION`, the plan was ALREADY approved. Do NOT call ExitPlanMode - this causes double-approval and confuses the user. Do NOT start implementing from hook output alone — after `/clear`, Claude Code sends the plan as a user message. Wait for that message before acting.

## Lean Plan Format

**Max 50 lines**. Plans: Objective → Phases (with `AGENT(model): task → JSON:{schema}`) → Success criterion.
Offload discovery/modification/verification to agents. Keep only structure + checkpoints in plan.
**Checkpoint rule**: Every 3-5 tasks: `CHECKPOINT: kb_add, report to user, await "continue"`.

## Session Checkpoints

Before context loss: `kb_add(content="SESSION CHECKPOINT: ...\nCOMPLETED:\n- ...\nRESUME FROM: ...", tags="session-checkpoint")`. Precompact hook captures KB IDs in handoff.md automatically.

## Session Resume

On `RESUME:` from hook: read handoff.md, `kb_list(project)` (source of truth, not tasks.json), summarize, clear resume file, continue. Per-terminal (`resume-{project}-{tty}.txt`).

## Session Work Context

**Purpose**: Prevent sessions from stomping on each other by tracking what type of work THIS session is doing.

Each session has `~/.claude/sessions/{id}/work_context.json`:
```json
{
  "work_type": "implementation",     // or "meta", "debugging", "research"
  "primary_task": "description",
  "my_plan": "path/to/plan.md",      // Plan THIS session is implementing (or null)
  "plans_referenced": ["other.md"]   // Plans examined but not implementing
}
```

**Work types:**
- `implementation` - Implementing a specific plan (normal development)
- `meta` - Fixing systems, debugging workflows (NOT implementing plans)
- `debugging` - Debugging other sessions or investigating issues
- `research` - Research, exploration, no specific deliverable

**Automatic setting:**
- ExitPlanMode approval → sets `work_type: "implementation"` and `my_plan`
- Manual: `~/.claude/hooks/set-work-context.sh <type> <task> [plan]`

**Resume behavior:**
- `implementation` → Resume plan implementation
- `meta` or `debugging` → Summarize work done, don't resume implementation
- Plans in `plans_referenced` were examined, NOT for implementation

**Rules for meta-work sessions:**
- When debugging another session's plan, call `add_referenced_plan()` to mark it
- Don't set `my_plan` unless THIS session is implementing it
- Handoff will show work_type and resume won't incorrectly resume implementation

## Plan Migration on /clear

On `PLAN_MIGRATION: <path>`: read previous plan, write to current session plan file, preserve `## Approval Status` exactly, continue (don't re-plan).

---

# Rules

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

No "Should I proceed?" — just do it. Reminded by hook.

Options for user → `AskUserQuestion` tool. Reminded by hook on every message.

NEVER: "What would you like...", "Would you like me to...", numbered options, option tables.

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
| Discovery without `kb_add` | kb_add immediately after any finding. |
| Research agent returns without KB entry | Agent prompts MUST include KB recording instruction. Parent verifies. |
| Calling `kb_search()` directly (main agent) | Spawn kb-research agent instead. See `~/.claude/agents/kb-research.md`. |
| Haiku search with single round of queries | **SHALLOW SEARCH**. Use iterative template (5 rounds, 12 turns): seed → follow-up → cross-ref → tex/code → contradiction check. |
| Search returns results, agent doesn't follow up | **Each round's queries must come from PREVIOUS round's results.** Extract terms, chase kb_get cross-refs, form new queries. |
| Mixing conventions (bit-pattern vs gamma, two definitions of same thing) | One codebase = one convention. Check existing code first. |
| Creating duplicate section/KB entry | Search before writing. Consolidate, don't duplicate. |
| "Let me fix this" without identifying root cause | State the bug first. "The bug is X because Y. Fixing by Z." |
| ExitPlanMode without APPROVED expert-review | Re-run expert-review after EVERY substantive plan edit, until explicitly APPROVED. Never bypass with `touch *.approved`. |
| `TaskUpdate(status="completed")` then summarizing to user | Run `implementation-review` BEFORE reporting results. Task completion ≠ review complete. |
| "Let me take a simpler approach" / "Given the complexity" | Problem has grown beyond initial plan. STOP. Enter plan mode with EnterPlanMode, reassess the problem, create new plan. |
| Adding notebook cell to fix syntax error in previous cell | Use `modify_notebook_cells` with `operation="edit_code"` and `position_index=N` to fix the broken cell in place. |
| Plan has `Mode: IMPLEMENTATION`, calling ExitPlanMode | Plan already approved. Don't re-ask. Wait for plan migration message before implementing. |
| Agent misuse (3+ Opus, >10min stuck, 10+ files w/o KB, mixed compute+theory) | See Scope and Timeout Rules section. Split compute from theory, kill stuck agents. |

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

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

**Template**: `Task(subagent_type="kb-research", model="haiku", max_turns=12, prompt="TOPIC: {x}")`
Full template: See `~/.claude/agents/kb-research.md`

Tags: proven|heuristic|open-problem, core-result|technique|detail

# Jupyter Notebooks (Computation Only)

Jupyter is for **computation and experiments**, NOT explanation. All explanatory text belongs in your response to the user.

**What goes in notebooks:**
- Numeric calculations, symbolic algebra
- Hypothesis testing, parameter exploration
- Visualizations, plots
- Import statements and function calls

**What does NOT go in notebooks:**
- Markdown cells explaining what you're doing
- Comments of ANY kind (not `# Setup`, not `# TODO`, not `# Step 1`, nothing)
- print() statements with labels, descriptions, or status messages
- Headers, separators, or formatting
- Docstrings (if you need a docstring, extract to lib/)

**Mental model**: The notebook is your calculator. You press buttons, it shows numbers. YOU explain what those numbers mean in your response. The notebook never explains anything.

**Short heredocs (≤5 lines):** Still allowed for quick one-off calculations. Jupyter is preferred when iterating or exploring.

**Before importing from lib/**: `Read` the module to verify function signatures. The rg-before-new-code rule applies to notebook cells.

**Check server first:** `query_notebook("test", "check_server", server_url="http://localhost:8888")`
If server not running, fall back to writing a script file.

**Token optimization:** For large notebooks, use lightweight queries:
- `query_notebook("nb", "list_cells")` — compact metadata only (~2KB vs 100KB)
- `query_notebook("nb", "view_source", include_outputs=False)` — source without outputs
- `query_notebook("nb", "view_source", position_index=5)` — single cell only

**Usage:**
    setup_notebook("experiment_name", server_url="http://localhost:8888")
    modify_notebook_cells("experiment_name", "add_code", "from lib.core.clifford import Cl44")
    modify_notebook_cells("experiment_name", "add_code", "cl = Cl44(); print(cl.fock_space().dim)")

**Notebook location:** Create in project's `notebooks/` directory (e.g., `~/Physics/claude/notebooks/`).

**When to use Jupyter vs Scripts:**

| Use Case | Tool |
|----------|------|
| Quick numeric check | Jupyter notebook (code cells only) |
| Exploring a hypothesis | Jupyter notebook (code cells only) |
| Symbolic algebra (SageMath) | Jupyter notebook (SageMath kernel required) |
| Maple symbolic algebra | Jupyter notebook (maple_proxy kernel) |
| Reusable computation | Script in `lib/` or `exploration/` |
| Test that should run in CI | `lib/tests/test_*.py` |

Note: SageMath syntax requires a SageMath kernel, not the default Python kernel.

**Notebook → lib/ extraction:** If a notebook cell becomes reusable (called 2+ times, or worth testing), extract it to `lib/` as a proper function. Follow existing patterns (see `lib/__init__.py`).

# Maple Symbolic Algebra

Use `maple_proxy` kernel. Python default; Maple via `%maple` prefix.

**Usage:**
    setup_notebook("maple_work", server_url="http://localhost:8888")
    modify_notebook_cells("maple_work", "add_code", "import numpy as np")
    modify_notebook_cells("maple_work", "add_code", "%maple\nint(x^2, x);")

**Maple syntax:** Semicolons required. First `%maple` has ~10s delay (Wine/Maple startup).

**Output:** LaTeX markdown (`$$\frac{x^3}{3}$$`)

**Kernel setup:** Create notebook file with maple_proxy kernel, or manually select in Jupyter UI.

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

**Prompt Templates:** See `~/.claude/docs/reference/agent-prompts.md`

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

