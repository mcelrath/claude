#!/bin/bash
# Library functions for managing session work context
source "$(dirname "${BASH_SOURCE[0]}")/claude-env.sh"

# Get session directory for current session
get_session_dir() {
    local STATE_DIR="/tmp/claude-kb-state"
    local SESSION_FILE="$STATE_DIR/session-$PPID"

    if [[ -f "$SESSION_FILE" ]]; then
        local SESSION_ID=$(cat "$SESSION_FILE")
        echo "$CLAUDE_DIR/sessions/$SESSION_ID"
    else
        return 1
    fi
}

# Initialize work context for a new session
init_work_context() {
    local work_type="${1:-research}"  # implementation | meta | debugging | research
    local primary_task="$2"
    local my_plan="${3:-}"

    local session_dir=$(get_session_dir)
    [[ -z "$session_dir" ]] && return 1

    mkdir -p "$session_dir"

    if [[ -n "$my_plan" ]]; then
        cat > "$session_dir/work_context.json" <<EOF
{
  "primary_task": "$primary_task",
  "work_type": "$work_type",
  "my_plan": "$my_plan",
  "plans_referenced": []
}
EOF
    else
        cat > "$session_dir/work_context.json" <<EOF
{
  "primary_task": "$primary_task",
  "work_type": "$work_type",
  "my_plan": null,
  "plans_referenced": []
}
EOF
    fi
}

# Add a plan to referenced list (for debugging/reading, not implementing)
add_referenced_plan() {
    local plan_path="$1"
    local session_dir=$(get_session_dir)
    [[ -z "$session_dir" ]] && return 1

    local context_file="$session_dir/work_context.json"
    [[ ! -f "$context_file" ]] && return 1

    # Add to plans_referenced array if not already there
    python3 -c "
import json, sys
try:
    with open('$context_file', 'r') as f:
        ctx = json.load(f)
    if '$plan_path' not in ctx.get('plans_referenced', []):
        ctx.setdefault('plans_referenced', []).append('$plan_path')
    with open('$context_file', 'w') as f:
        json.dump(ctx, f, indent=2)
except:
    sys.exit(1)
"
}

# Set my_plan (the plan THIS session is implementing)
set_my_plan() {
    local plan_path="$1"
    local session_dir=$(get_session_dir)
    [[ -z "$session_dir" ]] && return 1

    local context_file="$session_dir/work_context.json"

    # Initialize if doesn't exist
    if [[ ! -f "$context_file" ]]; then
        init_work_context "implementation" "Implementing plan" "$plan_path"
        return
    fi

    # Update existing
    python3 -c "
import json
try:
    with open('$context_file', 'r') as f:
        ctx = json.load(f)
    ctx['my_plan'] = '$plan_path'
    if ctx['work_type'] == 'research':
        ctx['work_type'] = 'implementation'
    with open('$context_file', 'w') as f:
        json.dump(ctx, f, indent=2)
except:
    pass
"
}

# Get work context as JSON
get_work_context() {
    local session_dir=$(get_session_dir)
    [[ -z "$session_dir" ]] && return 1

    local context_file="$session_dir/work_context.json"
    [[ -f "$context_file" ]] && cat "$context_file"
}

# Get specific field from work context
get_work_context_field() {
    local field="$1"
    local session_dir=$(get_session_dir)
    [[ -z "$session_dir" ]] && return 1

    local context_file="$session_dir/work_context.json"
    [[ ! -f "$context_file" ]] && return 1

    python3 -c "
import json, sys
try:
    with open('$context_file', 'r') as f:
        ctx = json.load(f)
    val = ctx.get('$field')
    if val is not None:
        print(val)
except:
    sys.exit(1)
"
}
