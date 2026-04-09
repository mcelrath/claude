#!/bin/bash
# SessionStart hook: ensure project has beads + required scaffold files

# Skip non-git directories
git rev-parse --show-toplevel &>/dev/null || exit 0

ACTIONS=""

if [[ ! -d ".beads" ]]; then
    # Sanitize directory name for Dolt database (no dots, hyphens, or special chars)
    PROJECT_DIR=$(basename "$(git rev-parse --show-toplevel)")
    DB_NAME=$(echo "$PROJECT_DIR" | tr '.-' '_' | tr -cd 'a-zA-Z0-9_')
    # All hosts connect to dolt server on tardis
    DOLT_HOST="${BEADS_DOLT_SERVER_HOST:-tardis}"
    DOLT_PORT="${BEADS_DOLT_SERVER_PORT:-3308}"
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
        bd init --database="$DB_NAME" --server-host="$DOLT_HOST" --server-port="$DOLT_PORT" 2>/dev/null \
        && bd setup claude 2>/dev/null
    ACTIONS="${ACTIONS}Initialized beads (db=$DB_NAME, server=$DOLT_HOST:$DOLT_PORT). "
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
