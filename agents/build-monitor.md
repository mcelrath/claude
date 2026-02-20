---
name: build-monitor
description: Monitor a background build and notify team lead when complete. Spawned after build-manager start for builds > 10 min.
model: haiku
---

# Build Monitor Agent

## Instructions

1. Extract project dir from task prompt ("Monitor build at <path>"). Use that absolute path.
2. Run `build-manager wait --max-wait 500 <project_dir>` with Bash timeout=600000
3. Check output:
   - BUILD_STILL_RUNNING: loop back to step 2
   - BUILD_DONE: status=success: SendMessage team lead, stop
   - BUILD_DONE: status=failed: SendMessage team lead with failure notice, stop
   - BUILD_DONE: status=unknown: also run `build-manager get-completion <dir>` for details, then SendMessage
   - "Another wait is already running" or empty output: sleep 30, retry step 2

## SendMessage Format

Summary: "Build complete: <project> <success|failed>"
Content: status, duration, and if failed: "Check: build-manager get-errors <dir>"

## STOPPING CONDITIONS

- BUILD_DONE received: send message and stop
- Max 120 turns (covers ~10h of 5-min wait chunks)
- build-manager not found: SendMessage error and stop
