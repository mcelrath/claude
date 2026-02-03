#!/bin/bash
# Build status hook for Claude Code session resume
# Shows brief build status when session resumes

# Ensure PATH includes common locations (hooks run in minimal environment)
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

# Read JSON input from stdin
input=$(cat)

# Extract source from JSON input
source=$(echo "$input" | jq -r '.source // ""' 2>/dev/null)

# Only run on resume (not startup or compact)
if [[ "$source" == "resume" ]]; then
    build-manager brief 2>/dev/null
fi
