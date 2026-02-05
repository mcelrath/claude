# Review Agents (MANDATORY)

| When | Agent | Action |
|------|-------|--------|
| Before ExitPlanMode | `expert-review` until APPROVED | Check plan before presenting it |
| code complete | `implementation-review` until ACCEPTED | Check correctness, verify archival |
| Implementation complete | `implementation-review` until ACCEPTED | Prove you're done to experts |
| Expert review corrections applied | `expert-review` until APPROVED | Plan changed, re-reviewed required |

**Triggers for implementation-review**: "done", "complete", "tests pass", after Edit/Write tools
**Triggers for expert-review**: "plan ready", before ExitPlanMode

## Named Reviewer Personas

See `~/.claude/reviewers.yaml` for expert personas organized by domain.

**Usage**: Invoke by name to trigger domain associations:
- "Review as Sidney Coleman" → careful QFT reasoning
- "Use the Munroe-Strogatz panel" → high school accessibility
- "What would Mencken object to?" → witty skepticism

**Key panels**:
- `technical_review`: Peskin + Anderson + Connes
- `popular_writing`: Sagan + Feynman + Munroe + Orwell
- `skeptic_panel`: Mencken + Russell + 't Hooft

## Auto-Select Review Panel (MANDATORY)

When user says any of these trigger phrases, AUTOMATICALLY spawn Haiku to select reviewers:

**Trigger phrases** (case-insensitive):
- "critically review" / "critical review"
- "review this" / "review your work" / "review the above"
- "sanity check" / "check this"
- "verify this" / "is this correct" / "does this make sense"
- "what do you think" (when asking about correctness, not preferences)

**Automatic action**:
```python
Task(subagent_type="general-purpose", model="haiku", prompt=f"""
Read ~/.claude/reviewers.yaml and select 2-3 expert reviewers for this content.

CONTENT TO REVIEW:
{summary of recent work: last code written, calculations done, or claims made}

PROJECT: {current project from pwd}

Select reviewers whose expertise matches the content domain.
ALWAYS include Claude for anti-pattern detection.

Return ONLY valid JSON:
{{
  "panel": [
    {{"name": "Reviewer Name", "domain": "specialty", "focus": ["areas"]}},
    {{"name": "Claude", "domain": "anti-pattern detection", "focus": ["CLAUDE.md violations"]}}
  ],
  "reason": "why these reviewers"
}}
""")
```

Then adopt each reviewer's voice to critique the work. Report findings as:
```
## Review Panel: [names]

### [Reviewer 1] ([domain]):
[critique in their voice]

### [Reviewer 2] ([domain]):
[critique in their voice]

### Claude (anti-patterns):
[CLAUDE.md violations, if any]
```

**Skip auto-select if**: User specifies reviewers by name ("review as Peskin", "use the skeptic panel").

## Background Isolation (MANDATORY for review agents)

**All review agents MUST run in background** to prevent memory exhaustion in parent context.

```python
# CORRECT: Background execution
Task(
    subagent_type="expert-review",
    prompt="Review: ...",
    run_in_background=True
)
# Then poll with TaskOutput or Read the output file

# WRONG: Foreground execution (causes 34GB+ memory growth)
Task(subagent_type="expert-review", prompt="Review: ...")
```

**Polling pattern:**
```python
result = Task(..., run_in_background=True)  # Returns immediately with output_file
# Wait for completion:
TaskOutput(task_id=result.task_id, block=True)  # Waits until done
# Or check status without blocking:
TaskOutput(task_id=result.task_id, block=False)
```

**Why:** Nested agents accumulate context unbounded. Background isolation runs in separate process.

## Research Agent KB Recording (MANDATORY)

**All research/investigation agents MUST record their findings in the KB before returning.**

When spawning agents to investigate questions, answer research queries, or explore topics:

1. **Include KB instruction in prompt**:
```
After completing your investigation, use kb_add to record your findings:
- finding_type: "discovery" for new insights, "success" for verified results, "failure" for dead ends
- project: "{current_project}"
- Include open_questions if any remain
```

2. **Standard prompt suffix for research agents**:
```
BEFORE RETURNING: Use kb_add(content=<your_findings>, finding_type="discovery",
project="{project}", tags="<relevant,tags>", verified=<bool>,
open_questions=[<any_remaining_questions>])
```

3. **Parent verification**: After agent completes, check if KB entry was created. If not, add one summarizing the agent's findings.

**Why:** Research findings are valuable even if the investigation reaches a dead end. Recording prevents re-investigation and preserves institutional knowledge.

## Research Agent Context Injection (MANDATORY)

**Before launching a research agent, the PARENT must:**

1. **Pre-search KB** for relevant findings (saves agent tokens, ensures context)
2. **Include findings in prompt** as structured context
3. **Require expert panel selection** for domain-specific questions

### Standard Research Agent Prompt Template

```
TASK: {task_description}

## PRIOR KNOWLEDGE (from KB)
{kb_findings_summary}
- kb-XXXXX: {one-line summary}
- kb-YYYYY: {one-line summary}
If these answer the question, STOP and report "Already resolved: kb-XXXXX"

## EXPERT PANEL REQUIREMENT
Before deep investigation, select 2-3 domain experts from:
- {domain1}: (e.g., {expert_names})
- {domain2}: (e.g., {expert_names})
State your panel and their relevance to this specific question.

## TECHNICAL QUESTIONS
1. {specific_question_1}
2. {specific_question_2}

## DELIVERABLE
{expected_output_format}

BEFORE RETURNING: kb_add(content=<findings>, finding_type="discovery",
project="{project}", tags="{tags}", verified=<bool>)
```

### Parent Pre-Search Pattern

Before calling Task for research:
```python
# 1. Search KB for relevant findings
findings = kb_search("relevant terms", project="claude", limit=5)

# 2. Format as context block (token-efficient)
kb_context = "\n".join([
    f"- {f.id}: {f.summary[:80]}" for f in findings
])

# 3. Include in agent prompt
prompt = f"""
TASK: {task}

## PRIOR KNOWLEDGE (from KB)
{kb_context}
If these answer the question, STOP and report the finding ID.

## EXPERT PANEL REQUIREMENT
...
"""
```

### Expert Panel Domains Reference

| Topic | Suggested Experts |
|-------|-------------------|
| Categories/Functors | Baez, Mac Lane, Lurie |
| Polylogarithms/K-theory | Zagier, Goncharov, Brown |
| Clifford algebras | Lounesto, Porteous, Atiyah |
| Hodge theory | Deligne, Schmid, Saito |
| Representation theory | Vogan, Kazhdan, Lusztig |
| Physics/QFT | Peskin, Weinberg, Coleman |
| Anti-patterns | Claude (always include) |

**Why this matters:**
- Agents often re-discover what KB already knows (wasted tokens)
- Without expert panel, agents give shallow answers
- Pre-injected context is 10x more token-efficient than agent searching

## Agent Task Classification

**Before launching ANY research agent, classify the task:**

| Task Type | Signs | How to Handle |
|-----------|-------|---------------|
| **Reasoning** | "Does X connect to Y?", "Assess whether...", structural questions | Answer YOURSELF (fastest, most reliable) |
| **Symbolic algebra** | "Compute the integral of...", "Factor this polynomial", "Simplify..." | Jupyter with SageMath/SymPy (symbolic tools are valid) |
| **Numerical computation** | "Verify numerically", "Compute eigenvalues", "Plot X" | Agent with Jupyter/numpy |
| **Hybrid** | "Compute X, then assess whether it implies Y" | SPLIT: compute first, then YOU reason about result |

### Reasoning Questions: Answer Yourself

Pure reasoning is about mathematical structure, not computation. Answer these yourself — you have KB context and domain knowledge. If delegating, use Sonnet with bounded scope (5 min phases, mandatory intermediate output).

**Origin of this rule:** Three Opus agents launched for theory questions ("Does theta lift connect to RH?", etc.) spent >1 hour reading files and setting up notebooks without output. The answers were obtainable by 30 seconds of reasoning.

### Agent Scope and Timeout Rules

| Rule | Action |
|------|--------|
| **3+ parallel Opus agents** | FORBIDDEN. Use Haiku/Sonnet for at least 2. |
| **Agent running >10 min** | Likely stuck. Check output, consider killing. |
| **Agent reads >10 files without KB entry** | Scope too broad. Kill and answer yourself. |
| **Numerical Jupyter for structural theory** | Wrong tool. Structural questions need reasoning or symbolic algebra, not numerics. |
| **Mixed compute+theory prompt** | SPLIT into separate agents or answer theory part yourself. |

### Bounded Agent Prompt Template

```
QUESTION: {question}

## PRIOR KNOWLEDGE
{kb_context}

## SCOPE CONSTRAINTS
- Phase 1 (5 min): State approach, produce intermediate output
- Phase 2 (5 min): Complete computation/analysis
- If stuck after Phase 1, kb_add what you have and RETURN

DELIVERABLE: ≤300 words. Conclusion first.
BEFORE RETURNING: kb_add(content=<findings>, finding_type="discovery", project="{project}")
```

### Decision Tree: Agent or Self?

```
Is the question answerable by reasoning from known definitions?
├── YES → Answer yourself (fastest, most reliable)
└── NO → Does it require symbolic algebra (integrals, factoring, simplification)?
    ├── YES → Jupyter with SageMath/SymPy
    └── NO → Does it require numerical computation?
        ├── YES → Computational agent (Haiku/Sonnet with Jupyter)
        └── NO → Does it require reading many unfamiliar files?
            ├── YES → Explore agent (Sonnet, read-only)
            └── NO → Answer yourself
```

**Default: answer yourself.** Agents are for parallelizing independent work, not outsourcing thinking.

## Plan Session Isolation

Your current plan file path is stored in `~/.claude/sessions/<session-id>/current_plan`.
- Written automatically by hook when you create/edit a plan in `~/.claude/plans/`
- Session ID comes from `/tmp/claude-kb-state/session-<PPID>`
- Read this file to know YOUR plan (don't use `find | head -1`)
- After implementation-review APPROVED: plan is automatically archived by the agent

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

**Before calling ExitPlanMode**, append to the plan file:

```markdown
---
## Approval Status
- expert-review: APPROVED
- User: PENDING
- Mode: PLANNING
```

**After user approves** (context clears, plan injected into new session):

The new session MUST check the plan's `## Approval Status` section:
- If `Mode: PLANNING` or no status section → normal planning flow
- If `Mode: IMPLEMENTATION` → **do NOT call ExitPlanMode**, begin executing the plan

**Hook responsibility**: When user approves via ExitPlanMode, update the plan file:
```markdown
## Approval Status
- expert-review: APPROVED
- User: APPROVED
- Mode: IMPLEMENTATION — Execute plan, do not call ExitPlanMode
```

## Lean Plan Format (Context-Efficient)

**Max 50 lines**. Plans describe WHAT, agents do HOW.

```markdown
# Plan: [name]

## Objective
[1-2 sentences]

## Phase 1: [title]
- [ ] AGENT(haiku): [query] → JSON:{schema}
- [ ] AGENT(sonnet): [modification task]
- [ ] Verify: [single assertion]
- [ ] CHECKPOINT: kb_add, pause for user

## Phase 2: [title]
...

## Success: [single measurable criterion]
```

**Mandatory offloads** (NEVER inline in plan):

| Task Type | Offload To |
|-----------|------------|
| Find files matching pattern | `AGENT(haiku): find X → {files:[], count:int}` |
| List functions in module | `AGENT(haiku): list functions → {functions:[]}` |
| Code examples/patterns | Reference doc: `docs/patterns/X.md` or `lib/patterns/` |
| Before/after comparisons | Agent applies pattern, confirms |
| Background/context | KB lookup (already known) |
| Mathematical derivations | KB finding or separate doc |
| File-by-file modifications | `AGENT(sonnet): apply fix to files in list` |
| Verification tests | `AGENT(haiku): run test → {passed:bool}` |

**What stays in plan**: Objective, phase structure, checkpoints, success criterion
**What's offloaded**: Discovery, modification, verification, examples, background

**Checkpoint rule**: Every 3-5 tasks, insert:
```
- [ ] CHECKPOINT: kb_add findings, report to user, await "continue"
```

At checkpoint: save state to KB, output summary, STOP until user responds.

## Session Checkpoints

When completing significant work or before context might be lost, create a KB checkpoint:

```python
kb_add(
    content="SESSION CHECKPOINT: {1-2 sentence summary}\n\nCOMPLETED:\n- {items}\n\nIN PROGRESS:\n- {current work}\n\nRESUME FROM: {next action}",
    finding_type="discovery",
    project=PROJECT,
    tags="session-checkpoint"
)
```

The precompact hook automatically captures KB IDs in handoff.md when /compact or /clear runs.

## Session Resume

Hook `session-start-resume.sh` outputs `RESUME:` if previous state exists.

**TTY-aware**: Resume files are per-terminal (`resume-{project}-{tty}.txt`), so concurrent sessions in same project don't conflict.

On seeing `RESUME:` in hook output:
1. Read the handoff.md file shown
2. `kb_list(project)` for recent findings - THIS is the source of truth
3. Review tasks.json for CONTEXT only - DO NOT auto-create tasks (they're often stale)
4. Summarize what was actually done based on KB findings
5. `rm ~/.claude/sessions/resume-{PROJECT}-{TTY}.txt` to clear pointer (or project-wide if no TTY)
6. Continue from where handoff indicates

**Why no auto-TaskCreate**: Agents don't reliably call TaskUpdate when completing work.
The JSONL-extracted tasks.json shows tasks as "pending" even when completed.
KB findings show actual work done and are authoritative.

---

# Rules

kb_search before implementation. Enforced by hook.

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
| `python3 -c "print('...')..."` with mostly prints | Scripts are for COMPUTATION. Write formatted output directly in your response. |
| `python -c` with more print() than computations | Hook blocks >70% print ratio. Return JSON/dict, format in response. |
| Heredoc >5 lines | Use Jupyter MCP for computation, or Write a script file. Import lib/ functions. |
| Markdown cell in notebook | Notebooks are for computation only. Explanation goes in your response text. |
| Any comment in notebook | No comments of any kind. Not `# Setup`, not `# TODO`, nothing. Just code. |
| `print("text...")` in notebook | Only print computed values/variables. No labels, descriptions, or status messages. |
| `I believe` / `This likely` / `This probably` | Speculation without verification. Run code, verify from data. |
| `Should I proceed?` / `What would you like...` | Don't ask permission. Just do it. |
| Reading parent directory for subdirectory work | Check pwd. Read requested files. Stay where told. |
| `DEBUG` / `Status:` / extra labels in output | Output only what was asked. Minimal, clean, relevant. |
| Columns don't line up / inconsistent spacing | Test output visually. Fixed-width fields. Verify alignment. See "Table Formatting" section. |
| Box-drawing table (┌┬┐├┼┤└┴┘│─) | NEVER. Use: `Header  Col2\n-------  ----\nval1     val2` (dashes + spaces only) |
| "Extracted 50,000" when expecting ~10 | Sanity check results. If output seems wrong, it is. |
| `Should I use X or Y?` / `What is the correct approach?` | You're the expert. Figure it out yourself. |
| Discovery without `kb_add` | kb_add immediately after any finding. |
| Research agent returns without KB entry | Agent prompts MUST include KB recording instruction. Parent verifies. |
| Launching research agent without pre-searching KB | **PARENT must search KB first**, include findings in prompt. Agents re-discovering known facts = wasted tokens. |
| Research agent prompt without expert panel requirement | Domain questions need expert panel. Include "Select 2-3 experts from: [domains]" in prompt. |
| Agent finding duplicates KB entry | Parent didn't pre-search. If agent finds what KB has, parent failed. |
| Mixing conventions (bit-pattern vs gamma, two definitions of same thing) | One codebase = one convention. Check existing code first. |
| Creating duplicate section/KB entry | Search before writing. Consolidate, don't duplicate. |
| "Let me fix this" without identifying root cause | State the bug first. "The bug is X because Y. Fixing by Z." |
| Editing plan after expert-review, then calling ExitPlanMode | Re-run expert-review after EVERY substantive plan edit. Adding tests/sections counts. |
| `expert-review` returning APPROVED without verification | Run expert-review UNTIL APPROVED as instructed - check the actual approval status |
| `touch *.approved` without running expert-review | NEVER bypass expert-review by manually creating approval files. The hook exists to enforce review. |
| Calling ExitPlanMode after expert-review returned anything other than APPROVED | Re-run expert-review until it explicitly returns APPROVED. "REJECTED", "INCOMPLETE", "NEEDS REVISION" all require iteration. |
| `print("=== Section ===")` or `print("Key finding:")` in notebook | Headers/labels go in response text, not notebooks. |
| `print(f"x = {x}, which means...")` in notebook | Split: `print(x)` in notebook, explanation in response. |
| Multiple print() showing a "story" in notebook | Notebook computes; you narrate in response text. |
| `TaskUpdate(status="completed")` then summarizing to user | Run `implementation-review` BEFORE reporting results. Task completion ≠ review complete. |
| `What would you like...` / `What should I...` / `What do you want...` | Work is done → STOP. Need options → use `AskUserQuestion` tool. Never open-ended prompts. |
| `print("SUMMARY ...` or `print("""` or `print("="*70)` | present results directly to the user, do not print them with python |
| Notebook cell with >3 print() but <3 computations | Hook blocks cells >70% presentation. Compute values, return tuple/dict, narrate in response. |
| "Let me take a simpler approach" / "Given the complexity" | Problem has grown beyond initial plan. STOP. Enter plan mode with EnterPlanMode, reassess the problem, create new plan. |
| Adding notebook cell to fix syntax error in previous cell | Use `modify_notebook_cells` with `operation="edit_code"` and `position_index=N` to fix the broken cell in place. |
| Plan has `Mode: IMPLEMENTATION`, calling ExitPlanMode | Plan already approved in previous session. Execute it, don't re-ask. |
| Opus agent for "does X connect to Y?" | **Reasoning question → answer yourself** or Sonnet with bounded scope (5 min phases). Opus agents with tools rabbit-hole into file reads. |
| Agent prompt mixes "compute X" with "assess whether Y" | **SPLIT**: one computational agent + you assess the result. Mixed prompts cause agents to compute indefinitely. |
| 3+ parallel Opus agents | **CPU/context explosion**. Use Haiku/Sonnet for at least 2. One Opus max per batch. |
| Agent reads 10+ files without KB entry | **Kill it**. Scope too broad. Answer yourself or narrow the question. |
| Numerical Jupyter for structural theory | **Wrong tool**. Structural questions need reasoning or symbolic algebra (SageMath/SymPy), not numerical notebooks. |
| "Verify from data" applied to structural math | **MISAPPLIED RULE**. "Verify from data" means run CODE to check NUMERICAL claims. Structural math uses PROOF or symbolic algebra. |
| Agent running >10 minutes with no KB entry | **Likely stuck**. Check output file. If agent is looping on file reads/KB searches, kill and do it yourself. |

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

# KB

```
kb_search(query, project)
kb_add(content, finding_type, project, tags, evidence)
kb_correct(supersedes_id, content, reason)
```

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

# KB Search via Haiku Agent

**For ALL KB exploration**, use a Haiku agent instead of direct search:
```
Task(subagent_type="general-purpose", model="haiku",
     prompt="Search KB (project='PROJECT') for [TOPIC]. Try 3+ search phrasings
             from different angles. Summarize relevant findings with IDs.")
```

**When to use**:
- Before starting work on any topic
- When surprised by a result (contradicts belief or seems "too good/bad")
- Before adding a finding (check for duplicates/contradictions)

**Why agent**: Haiku is faster/cheaper, and thorough KB search requires multiple phrasings.

# Haiku Task Delegation

Use `model="haiku"` for lightweight tasks beyond KB search:

| Task Type | Example Prompt |
|-----------|----------------|
| Existence check | "Does lib/ contain any file implementing X? Return JSON: {found: bool, files: []}" |
| File summary | "Summarize src/foo.py purpose in 1 sentence. Return JSON: {purpose: str}" |
| Signature extraction | "List public functions in module X. Return JSON: {functions: [{name, args, returns}]}" |
| Pattern search | "Find files importing Y. Return JSON: {files: []}" |
| Validation | "Run pytest test_foo.py. Return JSON: {passed: bool, failures: []}" |
| Format conversion | "Convert this to markdown table. Return just the table." |

**Keep on Sonnet/Opus**: Architectural planning, debugging, code generation, expert review, anything requiring multi-step reasoning.

**Keep on SELF (no agent)**: Pure math/theory questions, assessing whether mathematical structures connect, anything answerable by reasoning from known definitions. See "Agent Task Classification".

**Template**:
```
Task(subagent_type="general-purpose", model="haiku",
     prompt="[task]. Return JSON: {[schema]}")
```

# Agent Output Compression

**All agent prompts MUST request structured output** to minimize return tokens:

| Instead of | Use |
|------------|-----|
| "Find X and explain what you found" | "Find X. Return JSON: {found: bool, path: str, line: int}" |
| "Summarize the results" | "Return JSON: {summary: str (max 50 words), items: []}" |
| "Tell me if it passes" | "Return JSON: {passed: bool, error: str|null}" |

**Mandatory suffix for all Task prompts**:
```
Return ONLY valid JSON, no prose. Schema: {[fields]}
```

**Caller responsibility**: The agent returns data; YOU format it for the user in your response text.

**Anti-patterns**:
- Agent prompt without output schema → verbose prose response
- Asking agent to "explain" → paragraphs of explanation
- No length constraint → unbounded output

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

# Prompt Templates

Ready-to-use terse prompts for common Haiku agent tasks:

```python
# File existence
'Does {path} contain files matching {pattern}? JSON: {found:bool, files:[], count:int}'

# Function search
'Find function {name} in {path}. JSON: {found:bool, file:str, line:int, signature:str}'

# Import check
'What does {file} import? JSON: {imports:[], from_imports:[{module,names}]}'

# Test result
'Run pytest {path}. JSON: {passed:bool, total:int, failed:int, errors:[]}'

# Diff summary
'Summarize changes in {file}. JSON: {added:int, removed:int, functions_changed:[]}'

# Type check
'What type is {symbol} in {file}? JSON: {type:str, defined_at:str}'
```

**Usage**: Copy template, fill placeholders, wrap in Task call with `model="haiku"`.

# "Not Found" Is Not "Open"

**CRITICAL DISTINCTION**: When you can't find something, that means YOU haven't found it, not that it doesn't exist.

**Before declaring something "open", "incomplete", or "unresolved"**:

1. **Search KB via Haiku agent** (try multiple phrasings)
2. **Search code for implementations**: `rg "relevant_term" lib/`
3. **Cross-check comments vs implementations**: Trust code over comments

**Phrasing rules**:

| Wrong | Right |
|-------|-------|
| "This is an open question" | "I found no KB finding or implementation for this" |
| "No KB finding exists for X" | "Haiku KB search returned no results for X (tried: [queries])" |
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
1. Search KB via Haiku agent first
2. `kb_check_contradictions("<content>", project="PROJECT")` for surprising findings
3. `kb_add(content, finding_type, project="PROJECT", tags)`

Finding types: `success`, `failure`, `discovery`, `experiment`
Tags: `proven`/`heuristic`/`open-problem`, domain-specific

**Good Finding Structure**:
- **Title**: Direct fact statement (NOT "RESOLVED:", "PHASE N:")
- **Content**: Self-contained (no opaque kb-XXXXX cross-refs)
- **Code ref**: file:function for verification

**Maintenance**:
```
kb_review_queue(project="PROJECT")
kb_suggest_consolidation(project="PROJECT")
kb_validate(project="PROJECT", use_llm=True)
```

