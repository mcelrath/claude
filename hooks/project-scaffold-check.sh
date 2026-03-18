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
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
    echo "WARNING: Project missing required files: ${MISSING}"
    echo "  Run project-setup agent to create them:"
    echo "  Task(subagent_type=\"project-setup\", model=\"sonnet\", run_in_background=True,"
    echo "       prompt=\"Setup project at: $PROJECT_ROOT\")"
fi

[[ -n "$ACTIONS" ]] && echo "SCAFFOLD: $ACTIONS"
