---
description: Save session state to KB and handoff file before /clear
---

# Save State Command

Save current session state so you can /clear and resume later.

## Step 1: Get Session ID + Create Directory

Run these Bash commands (REQUIRED before any writes):

```bash
# Get session ID
cat /tmp/claude-kb-state/session-$PPID 2>/dev/null || echo "unknown-$(date +%Y%m%d-%H%M%S)"
```
Store result as SESSION_ID.

```bash
# Get project name
basename $(git rev-parse --show-toplevel 2>/dev/null || pwd)
```
Store result as PROJECT.

```bash
# Create session directory
mkdir -p ~/.claude/sessions/${SESSION_ID}
```

## Step 2: Get Plan File + Task List

```bash
cat ~/.claude/sessions/${SESSION_ID}/current_plan 2>/dev/null || echo "none"
```

Run `TaskList` tool to get current task state.

## Step 3: Reconcile Task State

Before saving, verify task state against evidence:
1. `TaskList` to get current tasks
2. For each pending task, check:
   - Was a related file edited? (compare task description vs files changed)
   - Was a KB finding added that indicates completion?
3. `TaskUpdate(taskId=X, status="completed")` for tasks with completion evidence
4. For tasks with unclear status, add note to description

## Step 4: Write KB Session Checkpoint (SOURCE OF TRUTH)

Write a structured KB finding with session state:
```
kb_add(
    content="SESSION CHECKPOINT: {1-2 sentence summary of work done}

COMPLETED:
- {list of completed items with evidence}

IN PROGRESS:
- {current work with specific state, e.g. 'Lean proof: 1 sorry remains at line 581'}

BLOCKED:
- {any blockers}

FILES CHANGED: {comma-separated list}
RESUME FROM: {specific next action}",
    finding_type="discovery",
    project=PROJECT,
    tags="session-checkpoint"
)
```

Store the returned KB ID as CHECKPOINT_ID.

## Step 5: Find and Deduplicate Other KB Findings

For each finding from this conversation (NOT the checkpoint):
1. `kb_search(finding_summary, project=PROJECT)`
2. If similar finding exists (similarity > 0.7): skip
3. If no match: `kb_add(content, finding_type, project=PROJECT)`

Track: findings_added = []

## Step 6: Write Files (Atomic)

**Write handoff.md.tmp:**
```markdown
# Session Handoff

## Session
ID: {SESSION_ID}
Project: {PROJECT}
Saved: {timestamp}

## Plan
File: {PLAN_FILE}

## Tasks
{TaskList output as JSON array}

## Current Work
{what was being worked on}

## Decisions
{key decisions made}

## KB Checkpoint
{CHECKPOINT_ID} - THIS IS THE SOURCE OF TRUTH for session state

## KB Findings Added
{list of kb-ids added in Step 5}

## Resume
1. Read this file
2. **kb_get({CHECKPOINT_ID})** - GET SESSION STATE FROM KB FIRST
3. TaskCreate from tasks.json (may be stale - trust KB checkpoint over tasks.json)
4. Continue from checkpoint's RESUME FROM field
```

**Write tasks.json.tmp:**
```json
[{"id": "1", "subject": "...", "status": "...", "description": "..."}]
```

## Step 7: Atomic Commit

Only if ALL writes succeeded:
```bash
cd ~/.claude/sessions/${SESSION_ID}
mv handoff.md.tmp handoff.md
mv tasks.json.tmp tasks.json
echo "${SESSION_ID}" > ../resume-${PROJECT}.txt
```

If ANY write failed: `rm -f *.tmp` and DO NOT create resume pointer.

## Step 8: Output

```
STATE SAVED
- Session: {SESSION_ID}
- Project: {PROJECT}
- KB Checkpoint: {CHECKPOINT_ID} (source of truth)
- Findings: {N} added to KB
- Tasks: {M} saved (reconciled)
- Handoff: ~/.claude/sessions/{SESSION_ID}/handoff.md
- Safe to /clear
```
