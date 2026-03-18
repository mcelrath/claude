#!/bin/bash
# SessionStart hook: ensure project has beads + required scaffold files

# Skip non-git directories
git rev-parse --show-toplevel &>/dev/null || exit 0

ACTIONS=""

if [[ ! -d ".beads" ]]; then
    bd init 2>/dev/null && bd setup claude 2>/dev/null
    ACTIONS="${ACTIONS}Initialized beads. "
fi

MISSING=""
[[ ! -f "reviewers.yaml" ]] && MISSING="${MISSING}reviewers.yaml "
[[ ! -f "agent-preamble.md" ]] && MISSING="${MISSING}agent-preamble.md "

if [[ -n "$MISSING" ]]; then
    ACTIONS="${ACTIONS}Missing: ${MISSING}"
    echo "WARNING: Project missing required files: ${MISSING}"
    echo "  Create these before running expert-review or dispatching agents."
    echo "  Templates: ~/Physics/claude/reviewers.yaml, ~/Physics/claude/agent-preamble.md"
fi

[[ -n "$ACTIONS" ]] && echo "SCAFFOLD: $ACTIONS"
