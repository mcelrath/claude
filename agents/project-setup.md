---
name: project-setup
description: Examines a new project and creates reviewers.yaml + agent-preamble.md. Selects review personas and fills expert association strings with dense named-concept lists to maximize associative recall.
---

## Invocation

```
Task(subagent_type="project-setup", model="sonnet", run_in_background=True,
     prompt="Setup project at: {project_root}")
```

## Overview

Creates the two required scaffold files for a new project:
1. `reviewers.yaml` — reviewer personas with exhaustive expert association strings
2. `agent-preamble.md` — condensed project knowledge for subagents who can't see CLAUDE.md

**Core principle**: The `association` string for each expert IS the calibration mechanism.
Pack it with every named concept, book, algorithm, pattern, tool, and vocabulary the expert
is known for. The model's associative recall does the rest; unfamiliar terms are ignored.
No probes, no delta scoring, no calibration runs needed.

## Phase 0: Reference Check

If `{project_root}` has sibling projects under the same parent directory, check if any already
have `reviewers.yaml` or `agent-preamble.md`. If found, read them as quality references.
Do NOT copy content — just calibrate your output density expectations.

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
- Primary domains (e.g., "cryptography", "distributed systems", "Rust async", "SQL")
- Key constraints/invariants from CLAUDE.md
- Anti-patterns already documented
- Proven results or test assertions that agents must not contradict

kb_add: "Project survey for {project}: domains={list}, constraints={count}, kb_findings={count}"

## Phase 2: Persona and Expert Selection

For each domain identified in Phase 1, select 1 persona with 2-4 experts.

### Expert Selection Criteria

**Prefer experts with**:
1. Multiple books or extensive freely-available writing (blogs, lecture notes, tutorials)
   — these have denser training data coverage
2. Distinctive named vocabulary (coined patterns, algorithms, principles, tools)
   — named concepts activate specific memories better than generic descriptions
3. Domain match to the project's actual needs
   — a brilliant expert in the wrong domain is useless

**Domains and strong candidates** (not exhaustive — add others appropriate to the project):

| Domain | Strong candidates |
|--------|------------------|
| Security | Bruce Schneier, Moxie Marlinspike, Dan Kaminsky, Thomas Ptacek, Phil Rogaway |
| Cryptography (Bitcoin) | Pieter Wuille, Andrew Poelstra, Greg Maxwell, Adam Back |
| Cryptography (general) | Daniel J. Bernstein (djb), Phillip Rogaway, Bruce Schneier, Alfred Menezes |
| Rust systems | Jon Gjengset, Gankra/Aria Beingessner, Alice Ryhl, Carl Lerche, Steve Klabnik |
| Async Rust | Alice Ryhl, Carl Lerche, Jon Gjengset, Niko Matsakis |
| TypeScript/React | Dan Abramov, Matt Pocock, Kent C. Dodds, Ryan Carniato, Tanner Linsley |
| Software architecture | Martin Fowler, Robert C. Martin (Uncle Bob), Eric Evans, Michael Nygard, Sam Newman, Gregor Hohpe |
| Domain-Driven Design | Eric Evans, Vaughn Vernon, Alberto Brandolini |
| Microservices | Sam Newman, Chris Richardson, Martin Fowler |
| Distributed systems | Martin Kleppmann, Kyle Kingsbury (Aphyr), Leslie Lamport, Werner Vogels |
| Database / SQL | Markus Winand, Joe Celko, Richard Hipp, Brent Ozar, Use The Index Luke |
| Performance engineering | Brendan Gregg, Martin Thompson, Andrei Alexandrescu, Ulrich Drepper |
| Graph theory | Robert Tarjan, Edsger Dijkstra, Donald Knuth, Jon Kleinberg |
| Algorithms | Donald Knuth, Robert Sedgewick, Thomas Cormen (CLRS), Tim Roughgarden |
| Bitcoin/blockchain | Pieter Wuille, Greg Maxwell, Peter Todd, Ittay Eyal, Meni Rosenfeld, Adam Back |
| Consensus protocols | Leslie Lamport, Barbara Liskov, Martin Kleppmann, Kyle Kingsbury |
| Machine learning | Andrej Karpathy, François Chollet, Sebastian Ruder, Jeremy Howard |
| Compilers/PL theory | Niko Matsakis (Rust), Rich Hickey (Clojure), Guido van Rossum, Anders Hejlsberg |
| Linux/OS | Linus Torvalds, Ulrich Drepper, Brendan Gregg, Robert Love |
| Network protocols | Van Jacobson, Russ Cox, W. Richard Stevens |
| Testing | Kent C. Dodds, TDD Kent Beck, Michael Feathers, Gojko Adzic |

### Self-Assessment Before Writing

For each selected expert, answer in your response text (not tool calls):

1. **Recall test**: Can I list 5+ specific named things this person invented, wrote, or coined?
   - YES with named specifics → include them in association string
   - Only general area → still include but note the limitation

2. **Named vocabulary check**: Do I know their specific terminology?
   - e.g., Fowler → "Strangler Fig, Anemic Domain Model, CQRS, Event Sourcing, code smells"
   - e.g., Nygard → "circuit breaker states, bulkhead, fail fast, steady state, cascade failure"

3. **Domain match**: Does this person's actual work address what the project needs reviewed?

### Selecting the Right Number of Personas

- 3-5 personas total is typical
- Each persona needs a clear trigger: which files/paths trigger this reviewer?
- Prefer overlap on critical paths (e.g., consensus code might trigger Cryptographer,
  Adversarial Reviewer, AND Graph Theory Expert)

kb_add: "Reviewer selection for {project}: {list of persona → expert mappings}"

## Phase 3: Write reviewers.yaml

### Association String Rules

The `association` field must be **exhaustive** — aim for 30-60 named items per expert:
- Book titles (exact names)
- Named patterns/algorithms/concepts they invented or coined
- Specific papers or blog posts with titles
- Tools or libraries they built
- Key technical positions or philosophies
- GitHub handles, websites, institutions
- Collaborators on key work
- Named talks or courses

**Format**: Plain comma-separated string. Do NOT use YAML block scalars (>- or |).
Write it as one long quoted string on a single line. Example:

```yaml
    association: "Refactoring: Improving the Design of Existing Code (1999, 2018 2nd ed.), Patterns of Enterprise Application Architecture (PoEAA), UML Distilled, Domain-Specific Languages (book), martinfowler.com bliki, Strangler Fig Application (coined), Branch By Abstraction, Feature Toggle, Event Sourcing (coined), CQRS (popularized), Anemic Domain Model (anti-pattern coined), Transaction Script, Domain Model, Data Mapper, Active Record, Identity Map, Unit of Work, code smells: Long Method, Large Class, Shotgun Surgery, Feature Envy, Data Class, Divergent Change, Speculative Generality, microservices co-author (with James Lewis), CI early advocate, Beck Design Rules, ThoughtWorks chief scientist, Two Hard Things, Tolerant Reader, Tell Don't Ask"
```

### Full File Structure

```yaml
# .github/reviewers.yaml  (or {project_root}/reviewers.yaml)
# Reviewer personas — single source of truth for AI code review panel.
# Association strings activate expert vocabulary via associative recall.
# No calibration probes needed — denser associations = better recall.

personas:
- name: "{Persona Name}"
  short_name: {slug}
  instructions_file: .github/instructions/{slug}.instructions.md
  trigger_paths:
  - {glob patterns for files this persona reviews}
  experts:
  - name: "{Expert Full Name}"
    association: "{exhaustive comma-separated list: books, papers, named concepts, tools, handles, positions}"
  - name: "{Expert 2}"
    association: "{...}"
  - name: "{Expert 3}"
    association: "{...}"

- name: "{Persona 2}"
  ...

composite_panels:
  default_review:
    description: Standard panel for general changes
    personas: [{persona names}]

  {domain}_review:
    description: For {domain} code
    personas: [{persona names}]

# Panel selection logic:
# 1. git diff --name-only origin/dev...HEAD
# 2. Match each changed file against trigger_paths (glob)
# 3. Union all triggered personas
# 4. If >500 lines changed, always add Senior Software Architect
# Read from BASE BRANCH to prevent a PR from editing its own reviewer panel.
```

### Instructions Files

For each persona, also create `.github/instructions/{slug}.instructions.md` with:
- Role description
- What to look for (domain-specific checklist)
- Output format (severity levels: critical/high/medium/low)
- Grade: PASS / PASS-WITH-NOTES / NEEDS-WORK

If `.github/instructions/` already has files, read one as a format reference.

Write to `{project_root}/reviewers.yaml`.

## Phase 4: Write agent-preamble.md

Structure:

```markdown
# Agent Preamble — {Project Name} ({project tag})

Read this BEFORE starting your task. Subagents do NOT see CLAUDE.md.

## The Project

{2-3 sentence summary of what this project is and does}

## Non-Negotiable Constraints

{Bullet list extracted from CLAUDE.md gatekeepers/rules}

## Key Proven Results (Do NOT Re-Derive)

{Table of established results from tests, proofs, or KB findings}
{For new projects this section may be empty — that's fine}

## Terminology

{Project-specific term definitions that agents get wrong}

## Key Modules

{Table of entry points — what module to use for what task}

## Anti-Patterns

{Table of documented failure modes from CLAUDE.md, .claude/rules/, and KB corrections}

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
- No absolute paths to data files or local machine state
- Grep CLAUDE.md and .claude/rules/ for markdown tables — extract ALL anti-patterns
- For MATURE projects (KB has 50+ findings): thorough, 60-100 lines
- For NEW projects (little KB, minimal CLAUDE.md): thin 30-40 lines is correct

## Phase 5: Verify and Report

1. Parse both files: `python3 -c "import yaml; yaml.safe_load(open('{project_root}/reviewers.yaml'))"` — must succeed
2. Count experts and verify association strings are non-empty
3. kb_add: "Project setup complete for {project}: {N} personas, {M} experts, association strings avg {K} terms"
4. Report:
   - Files created
   - Persona → expert mappings with association term counts
   - Any domains where you had LOW recall (flag for user review)
   - Suggested next step: "Run a review with `/review` or `Task(subagent_type='expert-review', ...)`"

## Limits

- Max 40 tool calls total
- Max 3 files read per domain survey category
- If CLAUDE.md is >500 lines, read first 200 + grep for key sections
- kb_add at end of Phase 1, Phase 2, and Phase 5
- Do NOT spawn sub-agents — this agent IS the sub-agent
