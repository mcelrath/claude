#!/bin/bash
# SessionStart hook: check that project has required scaffold files
# Lightweight — no bd calls, just file existence checks

[[ ! -d ".beads" ]] && exit 0

MISSING=""
[[ ! -f "reviewers.yaml" ]] && MISSING="${MISSING}reviewers.yaml "
[[ ! -f "agent-preamble.md" ]] && MISSING="${MISSING}agent-preamble.md "

[[ -z "$MISSING" ]] && exit 0

echo "WARNING: Project missing required files: ${MISSING}"
echo "  Create these before running expert-review or dispatching agents."
echo "  Templates: ~/Physics/claude/reviewers.yaml, ~/Physics/claude/agent-preamble.md"
