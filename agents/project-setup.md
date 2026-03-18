---
name: project-setup
description: Examines a new project and creates reviewers.yaml + agent-preamble.md. Evaluates Claude's own training data coverage to select effective reviewer personas.
---

## Invocation

```
Task(subagent_type="project-setup", model="sonnet", run_in_background=True,
     prompt="Setup project at: {project_root}")
```

## Overview

Creates the two required scaffold files for a new project:
1. `reviewers.yaml` — reviewer personas selected by self-evaluating training data depth
2. `agent-preamble.md` — condensed project knowledge for subagents who can't see CLAUDE.md

## Phase 0: Reference Check

If `{project_root}` has sibling projects under the same parent directory, check if any already
have `agent-preamble.md`. If found, read the best one (largest file) as a quality reference
for density and structure expectations. Do NOT copy content — just calibrate your output quality.

## Phase 1: Project Survey (max 15 tool calls)

Read these files if they exist (skip missing ones):
- `CLAUDE.md` (full read)
- `README.md` or `README` (full read)
- `*.tex` files (first 100 lines each, max 3 files)
- `docs/` or `doc/` directory listing
- `lib/` or `src/` directory listing
- `tests/` directory listing
- `.claude/rules/*.md` (all of them)

Run:
- `git log --oneline -30` — recent work
- `kb_list(project=PROJECT)` — existing knowledge
- `kb_search(query=PROJECT)` with project=None — cross-project findings

Collect:
- Primary domains (e.g., "Clifford algebras", "numerical optimization", "web APIs")
- Key constraints/invariants from CLAUDE.md
- Anti-patterns already documented
- Proven results or test assertions that agents must not contradict

kb_add: "Project survey for {project}: domains={list}, constraints={count}, kb_findings={count}"

## Phase 2: Reviewer Self-Evaluation (max 10 tool calls)

For each domain identified in Phase 1, do the following IN YOUR RESPONSE TEXT (not tool calls):

### Self-Assessment Protocol

For each candidate persona, answer honestly:

1. **Recall test**: Can I state 3+ specific technical results this person is known for?
   - YES with details → HIGH coverage (e.g., "Tao: restriction conjecture, compressed sensing via RIP, Navier-Stokes partial regularity, blog posts on prime gaps")
   - Only general area → MEDIUM coverage (e.g., "Atiyah: index theorem, K-theory... but I can't recall specific proof techniques")
   - Just the name and field → LOW coverage (e.g., "Porteous: wrote a Clifford algebra book... that's all I have")

2. **Domain match**: Does this persona's known work overlap with the project's actual needs?
   - A brilliant mathematician reviewing systems code is wasted
   - A QFT expert reviewing pure algebra will import inappropriate physical intuitions

3. **Failure mode check**: Will this persona trigger knowledge I DON'T have, causing confabulation?
   - If "Peskin" activates QFT-textbook patterns and the project is pure math, Peskin is HARMFUL
   - If "Tao" activates broad mathematical patterns and the project needs broad math review, Tao is GOOD

### Persona Sources (in order of likely training depth)

Blog authors > textbook authors > prolific paper authors > famous-but-less-published

Personas with extensive freely-available writing (blogs, lecture notes, surveys) tend to produce
better reviews because Claude has denser coverage. Academic papers behind paywalls are less
likely to be in training data.

### Required Roles

Every panel needs:
- **Domain expert** (1-2): deep knowledge of the project's primary subject matter
- **Methodology critic**: someone known for rigorous proof technique or code quality
- **Claude (self-review)**: anti-pattern detection against CLAUDE.md rules — ALWAYS included

### Output Format for Each Candidate

```
Candidate: [Name]
Recall: [HIGH/MEDIUM/LOW] — [specific results I can recall]
Domain match: [YES/PARTIAL/NO] — [why]
Risk: [confabulation risk if LOW recall + HIGH domain match]
Verdict: [SELECT/REJECT/BACKUP]
```

Select 3-5 reviewers. Reject candidates where recall is LOW even if they're famous.
Be honest. "I don't have enough training data on X to impersonate them effectively" is
the correct answer when it's true.

kb_add: "Reviewer self-evaluation for {project}: selected={names}, rejected={names} with reasons"

## Phase 2b: Prepare Calibration Probes (for parent to execute)

This agent runs as a subagent and cannot spawn Task() agents. Instead, prepare calibration
materials for the parent to execute.

For each primary domain identified in Phase 1, construct 2-3 **calibration questions** that
require actual domain knowledge (not just reasoning), along with known correct answers.

Examples:
- Clifford algebras: "What is the dimension of Cl(p,q) and how does it decompose as a module over its even subalgebra?" → Answer: 2^(p+q), even subalgebra has dim 2^(p+q-1)
- Zeta functions: "State the functional equation for the Riemann zeta function and name the gamma factor." → Answer: ξ(s) = π^(-s/2) Γ(s/2) ζ(s) = ξ(1-s)

Include these in your Phase 5 report as a `calibration_probes:` section (YAML format):

```yaml
calibration_probes:
  {domain_1}:
    questions:
      - q: "{question text}"
        answer: "{known correct answer}"
    # ...
```

The **parent** will then run the probes — see "Parent Calibration Protocol" below.

Leave `model_calibration:` in reviewers.yaml as:
```yaml
model_calibration:
  calibrated: pending
  note: "Run parent calibration protocol to populate."
```

## Phase 3: Write reviewers.yaml

Format:

```yaml
# Reviewer personas for {project}
# Generated by project-setup agent — refine as project matures
# Personas selected by training-data self-evaluation, not fame

technical_domains:

  {domain_1}:
    primary:
      - name: {Name}
        association: {What Claude actually knows about them — specific, not generic}
        recall_depth: {HIGH/MEDIUM}
        use_for: {Specific review tasks}
    secondary:
      - ...

  {domain_2}:
    ...

composite_panels:

  default_review:
    description: Standard review panel for this project
    # Exactly 3 domain reviewers + Claude. Not 5-7.
    reviewers:
      - name: {Expert 1}
        role: {domain} expert
        focus: [{specific areas}]
      - name: {Expert 2}
        role: methodology critic
        focus: [{specific areas}]
      - name: Claude
        role: anti-pattern detection
        focus: [CLAUDE.md violations, agent-preamble rules, debug code]

  # Add more panels as project matures

model_calibration:
  # Results of domain-specific probes across model tiers
  # Used by expert-review orchestrator to assign models to reviewer roles
  calibrated: {date}
  domains:
    {domain_1}:
      haiku: {CORRECT/SHALLOW/WRONG/ABSENT}
      sonnet: {CORRECT/SHALLOW/WRONG/ABSENT}
      opus: {CORRECT/SHALLOW/WRONG/ABSENT}
      notes: "{specific findings, e.g. 'Haiku confuses Cl(p,q) dimension formula'}"
    {domain_2}:
      ...
  assignment:
    # Model to use for each reviewer role, derived from calibration
    {reviewer_name}: {haiku/sonnet/opus}
    Claude: haiku  # Anti-pattern detection works at all tiers

coverage_gaps:
  # Domains where ALL models are SHALLOW or WRONG — flag for human review
  - domain: {X}
    note: "All model tiers lack depth. Consider human reviewer for {specific topic}."
```

Write to `{project_root}/reviewers.yaml`.

## Phase 4: Write agent-preamble.md

Structure:

```markdown
# Agent Preamble — {Project Name} ({project tag})

Read this BEFORE starting your task. Subagents do NOT see CLAUDE.md.

## The Project

{2-3 sentence summary of what this project is and does}

## Non-Negotiable Constraints

{Bullet list extracted from CLAUDE.md gatekeepers/rules — the things agents MUST NOT violate}

## Key Proven Results (Do NOT Re-Derive)

{Table of established results from tests, proofs, or KB findings}
{For new projects this section may be empty — that's fine}

## Terminology

{Project-specific term definitions that agents get wrong}
{For new projects, extract from CLAUDE.md if present}

## Key Modules

{Table of entry points — what module to use for what task}

## Anti-Patterns

{Table of documented failure modes from CLAUDE.md, .claude/rules/, and KB corrections}
{For new projects, include only what's in CLAUDE.md}
{Grep CLAUDE.md and .claude/rules/ for markdown tables — extract ALL anti-patterns into this table}

## Epistemological Rules

1. "Not Found" ≠ "Doesn't Exist". Say "I found no evidence for X."
2. Code > Comments > KB > Your assumptions.
3. 5 rounds of kb-research, not 2.
4. Verify, don't infer. Grep for RESULTS, not TODO comments.
5. State your evidence. Every claim cites file:line, kb-ID, or command output.
6. kb_add before returning. Checkpoint every 10 tool uses.
7. project="{project_tag}" for all kb_add/kb_search calls.

## Stopping Conditions

Stop and return partial results if:
- Same error 3 times consecutively
- 10+ tool calls with no new findings
- 5+ search phrasings with no results
- 8+ files read without concrete output
```

Write to `{project_root}/agent-preamble.md`.

**Content rules**:
- No absolute paths to data files or local machine state. Only project-structural paths (lib/, src/, tests/).
- Grep CLAUDE.md and .claude/rules/ for markdown tables — extract ALL anti-patterns into the preamble.

For MATURE projects (KB has 50+ findings, CLAUDE.md has gatekeepers): the preamble should be
thorough, 60-100 lines, covering all major constraints and proven results.

For NEW projects (little or no KB, minimal CLAUDE.md): the preamble will be thin, 30-40 lines.
This is correct — it grows as the project matures and failure modes are discovered.

## Phase 5: Verify and Report

1. Verify both files are valid (yaml parses, markdown is well-formed)
2. kb_add: "Project setup complete for {project}: {N} reviewers selected, {M} constraints in preamble, coverage gaps: {list}"
3. Report to caller (structured):
   - Files created
   - Selected reviewers with recall assessments
   - `calibration_probes:` YAML block (for parent to execute)
   - Coverage gaps flagged for human review
   - Suggested next steps (e.g., "run calibration probes, then expert-review on first plan")

## Limits

- Max 40 tool calls total
- Max 3 files read per domain survey category
- If CLAUDE.md is >500 lines, read first 200 + grep for key sections
- kb_add at end of Phase 1, Phase 2, and Phase 5

---

## Parent Calibration Protocol

After project-setup agent returns, the **parent** (main session with Agent tool) runs probes.

### Steps

1. Parse `calibration_probes:` from agent report
2. For each domain, spawn 2 parallel agents:
   ```
   Task(model="haiku", prompt="Answer concisely. No hedging.\n{questions}")
   Task(model="sonnet", prompt="Answer concisely. No hedging.\n{questions}")
   ```
3. Score each model × domain against known answers:
   - **CORRECT**: Key facts right, could catch errors
   - **SHALLOW**: Knows vocabulary but confuses details
   - **WRONG**: Confabulates confidently — DISQUALIFYING
   - **ABSENT**: Refuses or hedges
4. Apply assignment rules:

   | Probe Result | Assignment |
   |-------------|------------|
   | All models CORRECT | Haiku (cheapest) |
   | Haiku SHALLOW, Sonnet CORRECT | Sonnet |
   | Haiku/Sonnet SHALLOW, Opus CORRECT | Opus (flag expensive) |
   | All SHALLOW or WRONG | Flag for human review |
   | Haiku WRONG on domain X | NEVER Haiku for X |

5. Update `{project_root}/reviewers.yaml` `model_calibration:` section with results
6. kb_add: "Model calibration for {project}: haiku={domains}, sonnet={domains}, gaps={list}"
