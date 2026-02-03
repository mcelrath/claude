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

## Plan Session Isolation

Your current plan file path is stored in `~/.claude/sessions/<session-id>/current_plan`.
- Written automatically by hook when you create/edit a plan in `~/.claude/plans/`
- Session ID comes from `/tmp/claude-kb-state/session-<PPID>`
- Read this file to know YOUR plan (don't use `find | head -1`)
- After implementation-review APPROVED: plan is automatically archived by the agent

## Plan Modification Rule

**After ANY substantive edit to a plan file, re-run expert-review before ExitPlanMode.**

"Substantive" means: adding new sections/examples, changing recommended approaches, modifying checklists/anti-pattern tables, incorporating reviewer feedback.

Does NOT require re-review: typo fixes, renumbering sections, formatting changes.

## Plan Presentation Requirements

When presenting a plan for approval, include:
1. **Review status**: Whether expert-review was run and final verdict (APPROVED/iterations required)
2. **Revision summary**: If modifications were required, summarize key changes made
3. **Experts consulted**: List which domain experts reviewed the plan (e.g., physics, architecture, security)

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

## Session Resume

Hook `session-start-resume.sh` outputs `RESUME:` if previous state exists.

On seeing `RESUME:` in hook output:
1. Read the handoff.md file shown
2. `kb_list(project)` for recent findings - THIS is the source of truth
3. Review tasks.json for CONTEXT only - DO NOT auto-create tasks (they're often stale)
4. Summarize what was actually done based on KB findings
5. `rm ~/.claude/sessions/resume-{PROJECT}.txt` to clear pointer
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
| Columns don't line up / inconsistent spacing | Test output visually. Fixed-width fields. Verify alignment. |
| "Extracted 50,000" when expecting ~10 | Sanity check results. If output seems wrong, it is. |
| `Should I use X or Y?` / `What is the correct approach?` | You're the expert. Figure it out yourself. |
| Discovery without `kb_add` | kb_add immediately after any finding. |
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

# Physics/claude Prompt Templates

Domain-specific templates for ~/Physics/claude codebase:

**Plan execution agents** (for lean plan format):

```python
# File audit (find violations)
'Find files in lib/ with pattern `for b in range.*b_max`. JSON: {files:[{path,line,snippet}], count:int}'

# Batch modification
'In files {file_list}, replace `truncated_sum(b_max)` with `zeta_regularized_sum()`. JSON: {modified:[], failed:[], count:int}'

# Verification
'Run pytest lib/tests/test_{module}.py. JSON: {passed:bool, failures:[], duration_s:float}'

# KB population
'Search KB for {topic}, if not found add: {content}. JSON: {action:"found"|"added", id:str}'

# Pattern extraction
'Extract before/after pattern from {file}:{lines} to docs/patterns/{name}.md. JSON: {written:bool, path:str}'
```

**Discovery agents**:

```python
# Module lookup (which file computes X?)
'Which lib/ module computes {observable}? JSON: {file:str, function:str, returns:str}'

# Deprecation check
'Is {function} deprecated? Check lib/ for replacement. JSON: {deprecated:bool, replacement:str|null, reason:str}'

# Fock state query
'What are occupation numbers for state {state_int}? JSON: {bits:[int], N_L:int, N_R:int, pairing_eigenvalues:{A:int,B:int,C:int}}'

# Clifford algebra property
'Does Cl({p},{q}) have property {prop}? Verify in lib/core/clifford.py. JSON: {has_property:bool, method:str, evidence:str}'

# Observable at dilaton
'What modules compute {observable} at dilaton φ? JSON: {modules:[], primary:str, dataclass_returned:str}'

# Zeta regularization check
'Does {file} use zeta regularization for mode sums? JSON: {uses_zeta:bool, regularization_function:str|null, line:int}'

# Condensate type usage
'Which CondensateType does {file} use? JSON: {type:str, is_tau2_m:bool, line:int}'

# Test coverage
'What tests cover {module}? JSON: {test_files:[], test_count:int, covers_main_functions:bool}'

# Dataclass structure
'What fields does {DataclassName} have? JSON: {fields:[{name,type}], is_frozen:bool, file:str}'

# Physical constant location
'Where is {constant} defined? JSON: {file:str, line:int, value:str, units:str}'
```

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

