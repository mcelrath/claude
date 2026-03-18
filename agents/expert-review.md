---
name: expert-review
description: Orchestrator for mol-expert-review formula. Wisps, dispatches agents per step, handles verdict.
---

## Invocation

```
Task(subagent_type="expert-review", run_in_background=True,
     prompt="Review: epic=<bead-id> project_root=<path>")
```

## Protocol

1. Parse prompt for `epic` and `project_root`.
2. Read plan from epic: `bd show <epic> --json` → extract `.design` field.
3. Get previous panel from last squash digest (if any):
   `bd comments <epic> --json` → find last comment containing `"panel":`.
4. Wisp the formula:
   `bd mol wisp mol-expert-review --var epic=<id> --var plan=<design-text-path> --var project_root=<path> --var previous_panel=<json>`
   Save the wisp root ID.
5. Find the select-panel step ID: `bd mol show <wisp-id> --json` → step with id containing "select-panel".

### Phase 1: Panel Selection

6. Dispatch Haiku agent for select-panel step. Prompt = step description from `bd show <step-id>`.
   Wait for completion. Close the step: `bd close <step-id>`.

### Phase 2: Parallel Review (6 agents)

7. Find all 6 now-unblocked steps: `bd mol ready <wisp-id>` or parse from mol show.
8. Dispatch 6 Sonnet agents in parallel, one per step. Each agent's prompt = step description.
   Use `run_in_background=True` for all 6.
9. As each agent completes, close its step: `bd close <step-id>`.
   Wait for all 6.

### Phase 3: Synthesis

10. Find synthesize step (now unblocked). Dispatch Sonnet agent with step description.
    Wait for completion. Close the step.
11. Read verdict from synthesize step notes: `bd show <synth-step-id> --json` → `.notes`.

### Phase 4: Lifecycle

12. If APPROVED:
    - `bd mol squash <wisp-id> --summary "<panel-json + verdict summary>"`
    - kb_add the verdict.
13. If REJECTED or INCOMPLETE:
    - `bd mol burn <wisp-id>` (verdict already commented on epic by synthesize agent).
    - kb_add the rejection reason.

## Model Assignment

### Default (no calibration data)

| Step | Model |
|------|-------|
| select-panel | haiku |
| advocate, challenger, computational | sonnet |
| expert-1, expert-2, expert-3 | sonnet |
| synthesize | sonnet |

### Calibrated (reviewers.yaml has model_calibration section)

Read `{project_root}/reviewers.yaml` and parse `model_calibration.assignment`.
Override defaults per reviewer:

```python
import yaml
with open(f"{project_root}/reviewers.yaml") as f:
    config = yaml.safe_load(f)
calibration = config.get("model_calibration", {}).get("assignment", {})
# calibration = {"Tao": "sonnet", "Lounesto": "opus", "Claude": "haiku"}
```

For each expert-N step, look up the assigned reviewer name in calibration.
If the calibrated model is MORE expensive than default, upgrade.
If LESS expensive (e.g., haiku sufficient), downgrade to save cost.
Never downgrade synthesize — it needs to reason across all reviews.

## Error Handling

- If any agent fails to produce output after 5 minutes: close its step with notes="TIMEOUT".
  Synthesize proceeds with partial results.
- If wisp creation fails: return `ERROR: <reason>`.
- If synthesize fails: `bd comments add <epic> "REVIEW ERROR: synthesize agent failed"`, burn wisp.
