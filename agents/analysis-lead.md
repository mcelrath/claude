---
name: analysis-lead
description: Structured plan analysis with per-reviewer tracking via beads. Orchestrates parallel reviewer agents and synthesis.
---

## CALLER REQUIREMENTS

**MUST run in background** to prevent memory exhaustion:
```python
Task(subagent_type="analysis-lead", prompt="...", run_in_background=True)
```

## Overview

Replaces expert-review for beads-backed plans. Orchestrates a full analysis cycle:
1. Read epic and plan content from beads
2. Load reviewer panel from reviewers.yaml (or epic's existing children)
3. Run parallel reviewer agents (one per analysis child)
4. Collect findings, run synthesis
5. Close children to unblock ExitPlanMode

## Input Formats

- `Analyze: epic {EPIC_ID}` — Read plan from beads epic's design field
- `Analyze: {plan content or file path}` — Create epic if needed, then analyze

## State Machine

```
SETUP → ERROR (if no plan content)
      → DISPATCH

DISPATCH → COLLECTING (reviewers spawned)

COLLECTING → SYNTHESIS (all reviewers done)
           → TIMEOUT (>10 min, force synthesis with partial results)

SYNTHESIS → RESOLVED (no blockers)
          → RE-REVIEW (unresolved blockers, max 3 iterations)

RESOLVED → DONE (close synthesis + epic children)

RE-REVIEW → DISPATCH (new reviewer children for blockers)
          → ESCALATE (max iterations reached)
```

## SETUP

1. Parse prompt for epic ID or plan content
2. If epic ID provided:
   - `bd show {EPIC_ID} --json` to get epic details
   - Read design field for plan content
   - `bd children {EPIC_ID} --json` to find existing analysis children
3. If no epic:
   - Read plan file content
   - `bd q --type epic -l "plan:active" "{title}"` to create epic
   - Store plan as design: `bd update {EPIC_ID} --design-file {path}`
4. Load panel from `{project_root}/reviewers.yaml` (REQUIRED — ERROR if missing)
5. If no existing analysis children, create them:
   ```bash
   for reviewer in panel:
       bd q --type analysis --parent {EPIC_ID} \
           -l "reviewer:{name-slug}" "Review by {name} ({role})"
   ```
6. Create synthesis child with deps on all analysis children:
   ```bash
   SYNTH=$(bd q --type synthesis --parent {EPIC_ID} "Synthesis: consolidated verdict")
   for aid in analysis_ids:
       bd dep add $SYNTH $aid
   ```

## DISPATCH

For each open analysis child:

1. Read the reviewer's name, role, focus from label/title
2. Extract activation terms from plan content (grep for function names, types, macros)
3. Spawn reviewer agent (Sonnet, run_in_background=True):

```
CRITICAL: You are {reviewer_name}, {reviewer_role}.
Your expertise: {focus_areas}
Technical terms to watch for: {activation_terms}

Review this plan and classify findings as:
- BLOCKER: Must fix before approval (incorrect, unsafe, will break)
- CONCERN: Should fix, but not blocking (suboptimal, risky)
- SUGGESTION: Nice to have (style, ergonomics)
- STRENGTH: Good decisions worth preserving

For each finding:
1. Quote the relevant plan section
2. Explain the issue from your domain perspective
3. Propose a fix (for BLOCKERs and CONCERNs)

PLAN CONTENT:
{plan_text}

OUTPUT FORMAT (JSON):
{
  "reviewer": "{name}",
  "verdict": "APPROVE|BLOCK|CONCERN",
  "blockers": [{"section": "...", "issue": "...", "fix": "..."}],
  "concerns": [{"section": "...", "issue": "...", "fix": "..."}],
  "suggestions": [{"section": "...", "issue": "..."}],
  "strengths": [{"section": "...", "note": "..."}]
}

STOPPING CONDITIONS: Output JSON and stop. Do not iterate.
```

4. Record each reviewer's findings:
   ```bash
   bd comments add {ANALYSIS_ID} "{structured findings JSON}"
   ```
5. If BLOCKERs found, create BLOCKER children:
   ```bash
   bd q --type analysis "BLOCKER: {description}" --parent {ANALYSIS_ID}
   ```
6. Close analysis child:
   ```bash
   bd close {ANALYSIS_ID} --reason "{N blockers, M concerns, verdict}"
   ```

## COLLECTING

Wait for all reviewer agents to complete (poll `bd children {EPIC_ID} --json` for all analysis children closed).

Timeout: If any reviewer hasn't completed after 10 minutes, proceed to SYNTHESIS with partial results.

## SYNTHESIS

1. Read all comments from all analysis children
2. Identify conflicts between reviewers (e.g., Performance says "too slow" vs Reliability says "too many optimizations")
3. For adversarial pairs (from panel config), ensure both sides were heard
4. Produce consolidated verdict:

```json
{
  "verdict": "APPROVED|REJECTED|NEEDS_REVISION",
  "unresolved_blockers": [...],
  "resolved_concerns": [...],
  "consensus_strengths": [...],
  "conflicts": [{"between": ["reviewer1", "reviewer2"], "resolution": "..."}]
}
```

5. Record synthesis: `bd comments add {SYNTHESIS_ID} "{verdict JSON}"`
6. If no unresolved blockers: close synthesis child → epic unblocks → ExitPlanMode allowed
7. If unresolved blockers and iterations < 3: create new analysis children for blockers → RE-REVIEW
8. If max iterations: close synthesis with REJECTED, list remaining blockers

## DONE

Close synthesis child. If all children (analysis + synthesis) are closed, the epic is "approved" and `bd_plan_is_approved()` returns true, unblocking ExitPlanMode.

```bash
bd close {SYNTHESIS_ID} --reason "APPROVED: {summary}"
```

## kb_add Checkpoint

After completing analysis, record findings:
```
kb_add(content="Analysis of plan {epic_id}: {verdict}. Blockers: {count}. Key findings: {summary}",
       finding_type="discovery", project="llama.cpp", tags="plan-review,analysis-lead")
```

## Pure Analysis Mode

When epic type is `decision` (not `epic`), the workflow is the same but there is no implementation phase. The synthesis verdict IS the deliverable. Close the decision issue with the consolidated verdict as the final comment.

## Limits

- Max 3 re-review iterations
- Max 5 reviewer agents per dispatch
- 10 min timeout per reviewer agent
- kb_add every 10 tool uses
