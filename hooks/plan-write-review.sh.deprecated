#!/bin/bash
# PostToolUse hook for Edit/Write
# When a plan file is written, create beads epic + analysis children from project panel,
# or fall back to legacy session-based expert-review setup
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/beads-plan.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
    exit 0
fi

# Get session ID: try hook input first, then PPID mapping
STATE_DIR="/tmp/claude-kb-state"
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
    SESSION_FILE="$STATE_DIR/session-$PPID"
    [[ -f "$SESSION_FILE" ]] && SESSION_ID=$(cat "$SESSION_FILE")
fi
[[ -z "$SESSION_ID" ]] && exit 0

# Extract file path
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tool_input = data.get('tool_input', {})
print(tool_input.get('file_path', ''))
" 2>/dev/null)

# Check if this is a plan file (not an agent output file)
if [[ "$FILE_PATH" != *"/.claude"*/plans/* ]]; then
    exit 0
fi

# Move agent output files to subdirectory immediately (keeps main dir clean)
AGENT_DIR="$CLAUDE_DIR/plans/agent-output"
mkdir -p "$AGENT_DIR"
if [[ "$FILE_PATH" == *"-agent-"* ]]; then
    mv "$FILE_PATH" "$AGENT_DIR/" 2>/dev/null
    exit 0
fi

SESSION_DIR="$CLAUDE_DIR/sessions/$SESSION_ID"
mkdir -p "$SESSION_DIR"

# Check if project requires expert-review
PWD_PATH=$(pwd)
REQUIRES_REVIEW=false
[[ "$PWD_PATH" == *"/Physics/"* ]] || [[ "$PWD_PATH" == *"/physics/"* ]] && REQUIRES_REVIEW=true
[[ -f "CLAUDE.md" ]] && grep -q "Expert Review.*MANDATORY" CLAUDE.md 2>/dev/null && REQUIRES_REVIEW=true
[[ "$REQUIRES_REVIEW" != "true" ]] && exit 0

# Skip review reminder if plan is already approved/in implementation
grep -q 'Mode: IMPLEMENTATION' "$FILE_PATH" 2>/dev/null && exit 0
grep -q 'expert-review: APPROVED' "$FILE_PATH" 2>/dev/null && exit 0

# Check if current_plan already has a beads epic for this plan
CURRENT_PLAN=""
[[ -f "$SESSION_DIR/current_plan" ]] && CURRENT_PLAN=$(cat "$SESSION_DIR/current_plan")
if bd_is_beads_id "$CURRENT_PLAN"; then
    # Already have a beads epic — update design content, don't recreate
    bd update "$(bd_strip_prefix "$CURRENT_PLAN")" --design-file "$FILE_PATH" 2>/dev/null
    echo "PLAN FILE UPDATED: $(basename "$FILE_PATH")"
    echo "Epic: $(bd_strip_prefix "$CURRENT_PLAN") — run analysis-lead agent or close children to approve."
    exit 0
fi

# === Try BEADS PATH first: create epic + reviewer children ===
PLAN_TITLE=$(head -1 "$FILE_PATH" | sed 's/^# //')
[[ -z "$PLAN_TITLE" ]] && PLAN_TITLE=$(basename "$FILE_PATH" .md)

PANEL_JSON=$(bd_plan_get_panel)
if [[ -n "$PANEL_JSON" && "$PANEL_JSON" != "[]" ]]; then
    # Create epic
    EPIC_ID=$(bd_plan_create_epic "$PLAN_TITLE")
    if [[ -n "$EPIC_ID" ]]; then
        # Store plan content as epic design field
        bd update "$EPIC_ID" --design-file "$FILE_PATH" 2>/dev/null

        # Create reviewer children from panel
        REVIEWER_IDS=()
        while IFS= read -r reviewer_line; do
            [[ -z "$reviewer_line" ]] && continue
            local_name=$(echo "$reviewer_line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null)
            local_role=$(echo "$reviewer_line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('role',''))" 2>/dev/null)
            local_focus=$(echo "$reviewer_line" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin).get('focus',[])))" 2>/dev/null)
            if [[ -n "$local_name" ]]; then
                local_rid=$(bd_plan_add_reviewer "$EPIC_ID" "$local_name" "$local_role" "$local_focus")
                [[ -n "$local_rid" ]] && REVIEWER_IDS+=("$local_rid")
            fi
        done < <(echo "$PANEL_JSON" | python3 -c "import sys,json; [print(json.dumps(r)) for r in json.load(sys.stdin)]" 2>/dev/null)

        # Create synthesis child with deps on all reviewers
        if [[ ${#REVIEWER_IDS[@]} -gt 0 ]]; then
            bd_plan_add_synthesis "$EPIC_ID" "${REVIEWER_IDS[@]}" >/dev/null
        fi

        # Bind session to this epic
        bd_plan_bind_session "$SESSION_DIR" "$EPIC_ID"

        # Also write current_plan as file path for legacy hooks that may still check
        # (Phase 4 removes this)
        echo "$FILE_PATH" > "$SESSION_DIR/current_plan.legacy"

        cat << EOF
PLAN FILE WRITTEN: $(basename "$FILE_PATH")
BEADS EPIC CREATED: $EPIC_ID

STOP! Before presenting this plan to the user, you MUST run expert-review:

Task(subagent_type="expert-review", model="sonnet", run_in_background=True,
     prompt="Review: $FILE_PATH")

Or run analysis-lead for structured review:
Task(subagent_type="analysis-lead", prompt="Analyze: epic $EPIC_ID")

DO NOT show the plan to the user until expert-review returns APPROVED.
If REJECTED or INCOMPLETE, fix the issues first.
EOF
        exit 0
    fi
fi

# === LEGACY FALLBACK: no beads or epic creation failed ===
echo "$FILE_PATH" > "$SESSION_DIR/current_plan"

PLAN_NAME=$(basename "$FILE_PATH")
PROJECT_ROOT="$PWD_PATH"
EXTRA_COPIES=""

RULES_DIR=""
if [[ -d "$PROJECT_ROOT/.claude/rules" ]]; then
    RULES_DIR="$PROJECT_ROOT/.claude/rules"
elif [[ -d "$PROJECT_ROOT/.claude2/rules" ]]; then
    RULES_DIR="$PROJECT_ROOT/.claude2/rules"
fi
[[ -n "$RULES_DIR" ]] && EXTRA_COPIES="${EXTRA_COPIES}
cp -r \"$RULES_DIR\" $CLAUDE_DIR/sessions/\$SESSION_ID/rules/"

[[ -f "$PROJECT_ROOT/CLAUDE.md" ]] && EXTRA_COPIES="${EXTRA_COPIES}
cp \"$PROJECT_ROOT/CLAUDE.md\" $CLAUDE_DIR/sessions/\$SESSION_ID/project-claude.md"

cat << EOF
PLAN FILE WRITTEN: $PLAN_NAME

STOP! Before presenting this plan to the user, you MUST run expert-review:

SESSION_ID=\$(date +%Y%m%d-%H%M%S)-\$(head -c 4 /dev/urandom | xxd -p)
mkdir -p $CLAUDE_DIR/sessions/\$SESSION_ID
cp "$FILE_PATH" $CLAUDE_DIR/sessions/\$SESSION_ID/plan.md${EXTRA_COPIES}
cat > $CLAUDE_DIR/sessions/\$SESSION_ID/context.yaml << 'YAML'
reviewer_persona: "Senior physicist specializing in Clifford algebras"
project_root: $PWD_PATH
YAML
Task(subagent_type="expert-review", model="sonnet", prompt="Review: session://\$SESSION_ID")

DO NOT show the plan to the user until expert-review returns APPROVED.
If REJECTED or INCOMPLETE, fix the issues first.
EOF
