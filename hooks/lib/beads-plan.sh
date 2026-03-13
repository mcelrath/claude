#!/bin/bash
# Shared library for beads-backed plan management
# All functions call `bd` CLI, return exit codes
# Source this from hooks that manage plan state

# Pattern match: beads ID format is {prefix}-{hex} (e.g. llamacpp-abc123)
bd_is_beads_id() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    # Strip "beads:" prefix if present (used by precompact marker)
    value="${value#beads:}"
    [[ "$value" =~ ^[a-z]+-[a-z0-9]+$ ]]
}

# Strip "beads:" prefix from a value stored in current_plan
bd_strip_prefix() {
    local value="$1"
    echo "${value#beads:}"
}

# Create a plan epic with plan:active label
# Usage: bd_plan_create_epic "Plan Title"
# Prints: epic ID
bd_plan_create_epic() {
    local title="$1"
    bd q --type epic -l "plan:active" "$title" 2>/dev/null
}

# Add a reviewer analysis child to a plan epic
# Usage: bd_plan_add_reviewer epic_id name domain "focus1,focus2"
# Prints: analysis child ID
bd_plan_add_reviewer() {
    local epic_id="$1"
    local name="$2"
    local domain="$3"
    local focus="$4"
    local slug=$(echo "$name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    local output
    output=$(bd create --type analysis --parent "$epic_id" \
        -l "reviewer:$slug" \
        "Review by $name ($domain)" 2>/dev/null)
    echo "$output" | grep -oP '(?<=Created issue: )\S+' | head -1
}

# Add synthesis child with dependencies on all analysis children
# Usage: bd_plan_add_synthesis epic_id analysis_id1 analysis_id2 ...
# Prints: synthesis child ID
bd_plan_add_synthesis() {
    local epic_id="$1"
    shift
    local analysis_ids=("$@")

    local create_output
    create_output=$(bd create --type synthesis --parent "$epic_id" "Synthesis: consolidated verdict" 2>/dev/null)
    local synth_id
    synth_id=$(echo "$create_output" | grep -oP '(?<=Created issue: )\S+' | head -1)
    [[ -z "$synth_id" ]] && return 1

    for aid in "${analysis_ids[@]}"; do
        bd dep add "$synth_id" "$aid" >/dev/null 2>&1
    done

    echo "$synth_id"
    return 0
}

# Check if all analysis + synthesis children of a plan epic are closed
# Returns 0 if approved (all closed), 1 if not
bd_plan_is_approved() {
    local epic_id="$1"
    epic_id=$(bd_strip_prefix "$epic_id")

    local children_json
    children_json=$(bd children "$epic_id" --json 2>/dev/null)
    [[ -z "$children_json" || "$children_json" == "[]" || "$children_json" == "null" ]] && return 1

    local open_count
    open_count=$(echo "$children_json" | python3 -c "
import sys, json
try:
    children = json.load(sys.stdin)
    if not isinstance(children, list):
        children = []
    print(sum(1 for c in children if c.get('status') not in ('closed', 'done')))
except:
    print(1)
" 2>/dev/null)

    [[ "$open_count" == "0" ]]
}

# Get plan epic status as a string
# Prints: "open (2/5 reviews done)" or "closed" etc.
bd_plan_status() {
    local epic_id="$1"
    epic_id=$(bd_strip_prefix "$epic_id")

    local epic_json
    epic_json=$(bd show "$epic_id" --json 2>/dev/null)
    [[ -z "$epic_json" ]] && echo "unknown" && return 1

    local status
    status=$(echo "$epic_json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if isinstance(d, list): d = d[0]
    print(d.get('status', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)

    # Get children counts
    local children_json
    children_json=$(bd children "$epic_id" --json 2>/dev/null)
    if [[ -n "$children_json" && "$children_json" != "[]" && "$children_json" != "null" ]]; then
        local counts
        counts=$(echo "$children_json" | python3 -c "
import sys, json
try:
    children = json.load(sys.stdin)
    if not isinstance(children, list): children = []
    total = len(children)
    closed = sum(1 for c in children if c.get('status') in ('closed', 'done'))
    print(f'{closed}/{total} reviews done')
except:
    print('?')
" 2>/dev/null)
        echo "$status ($counts)"
    else
        echo "$status"
    fi
}

# Close a plan epic
bd_plan_close() {
    local epic_id="$1"
    epic_id=$(bd_strip_prefix "$epic_id")
    bd close "$epic_id" 2>/dev/null
}

# Read project panel from reviewers.yaml for the current working directory project
# Prints: JSON array of reviewer objects
bd_plan_get_panel() {
    local project_name="${1:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"
    local reviewers_yaml="${CLAUDE_DIR:-$HOME/.claude}/reviewers.yaml"

    [[ ! -f "$reviewers_yaml" ]] && echo "[]" && return 1

    python3 -c "
import yaml, json, sys
try:
    with open('$reviewers_yaml') as f:
        data = yaml.safe_load(f)
    panels = data.get('project_panels', {})
    panel = panels.get('$project_name', {})
    reviewers = panel.get('reviewers', [])
    print(json.dumps(reviewers))
except Exception as e:
    print('[]', file=sys.stderr)
    print('[]')
" 2>/dev/null
}

# Get adversarial pairs from project panel
# Prints: JSON array of adversarial pair objects
bd_plan_get_adversarial_pairs() {
    local project_name="${1:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"
    local reviewers_yaml="${CLAUDE_DIR:-$HOME/.claude}/reviewers.yaml"

    [[ ! -f "$reviewers_yaml" ]] && echo "[]" && return 1

    python3 -c "
import yaml, json, sys
try:
    with open('$reviewers_yaml') as f:
        data = yaml.safe_load(f)
    panels = data.get('project_panels', {})
    panel = panels.get('$project_name', {})
    pairs = panel.get('adversarial_pairs', [])
    print(json.dumps(pairs))
except:
    print('[]')
" 2>/dev/null
}

# Bind a session to a plan epic: write epic ID to current_plan
bd_plan_bind_session() {
    local session_dir="$1"
    local epic_id="$2"
    [[ -z "$session_dir" || -z "$epic_id" ]] && return 1
    mkdir -p "$session_dir"
    echo "$epic_id" > "$session_dir/current_plan"
}

# Extract activation terms from a file or diff
# Prints: CSV of technical terms found
bd_extract_activation_terms() {
    local input="$1"  # file path or "-" for stdin

    if [[ "$input" == "-" ]]; then
        grep -oE '[a-z_]+_t\b|ggml_[a-z_]+|cuda[A-Z][a-zA-Z]+|hip[A-Z][a-zA-Z]+|GGML_[A-Z_]+|__[a-z_]+\b' | sort -u | tr '\n' ',' | sed 's/,$//'
    elif [[ -f "$input" ]]; then
        grep -oE '[a-z_]+_t\b|ggml_[a-z_]+|cuda[A-Z][a-zA-Z]+|hip[A-Z][a-zA-Z]+|GGML_[A-Z_]+|__[a-z_]+\b' "$input" | sort -u | tr '\n' ',' | sed 's/,$//'
    fi
}
