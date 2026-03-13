#!/bin/bash
# Notification hook - checks for pending session resume on session start
# Runs on session start to detect if previous session saved state
# Supports both beads epic IDs and legacy file-based plans
source "$(dirname "$0")/lib/claude-env.sh"
source "$(dirname "$0")/lib/beads-plan.sh"

# Get project name
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT=$(basename "$PWD")
fi

# Get terminal-specific ID (PTY from /proc walk, falls back to CLAUDE_SESSION env)
source "$CLAUDE_DIR/hooks/lib/get_terminal_id.sh"
TERM_ID=$(_get_terminal_id)

# Terminal-specific resume file first
RESUME_FILE=""
if [[ -n "$TERM_ID" ]]; then
    RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}-${TERM_ID}.txt"
fi

# Fallback to project-wide (safe only if single session per project)
if [[ ! -f "$RESUME_FILE" ]]; then
    RESUME_FILE="$CLAUDE_DIR/sessions/resume-${PROJECT}.txt"
fi

if [[ -f "$RESUME_FILE" ]]; then
    SESSION_ID=$(cat "$RESUME_FILE")
    HANDOFF="$CLAUDE_DIR/sessions/${SESSION_ID}/handoff.md"
    TASKS="$CLAUDE_DIR/sessions/${SESSION_ID}/tasks.json"

    if [[ -f "$HANDOFF" ]]; then
        KB_CHECKPOINT=$(grep -oE 'kb-[0-9]{8}-[0-9]{6}-[a-f0-9]{6}' "$HANDOFF" | head -1)
        REVIEW_LINE=$(grep -A1 "## Expert Review" "$HANDOFF" 2>/dev/null | tail -1)

        echo "RESUME: Previous session state found"
        echo "  Handoff: $HANDOFF"
        echo "  Tasks: $TASKS"
        if [[ -n "$REVIEW_LINE" && "$REVIEW_LINE" != "No expert review this session" ]]; then
            echo "  Expert Review: $REVIEW_LINE"
        fi
        if [[ -n "$KB_CHECKPOINT" ]]; then
            echo "  KB Checkpoint: $KB_CHECKPOINT (SOURCE OF TRUTH)"
            echo "  Action: Read handoff, kb_list(project) for recent findings, summarize state"
            echo "  IMPORTANT: Do NOT auto-create tasks from tasks.json - they are often stale."
            echo "  Tasks.json is for CONTEXT only. KB findings show actual work done."
        else
            echo "  Action: Read handoff, kb_list for context, summarize state"
            echo "  IMPORTANT: Do NOT auto-create tasks from tasks.json - they are often stale."
        fi

        # Check work context to determine what this session was actually doing
        WORK_CONTEXT_FILE="$CLAUDE_DIR/sessions/${SESSION_ID}/work_context.json"
        WORK_TYPE=""
        MY_PLAN=""
        PRIMARY_TASK=""

        if [[ -f "$WORK_CONTEXT_FILE" ]]; then
            WORK_TYPE=$(python3 -c "import json; ctx=json.load(open('$WORK_CONTEXT_FILE')); print(ctx.get('work_type', ''))" 2>/dev/null)
            MY_PLAN=$(python3 -c "import json; ctx=json.load(open('$WORK_CONTEXT_FILE')); print(ctx.get('my_plan') or '')" 2>/dev/null)
            PRIMARY_TASK=$(python3 -c "import json; ctx=json.load(open('$WORK_CONTEXT_FILE')); print(ctx.get('primary_task', ''))" 2>/dev/null)

            echo "  Work Context: $WORK_TYPE"
            [[ -n "$PRIMARY_TASK" ]] && echo "  Primary Task: $PRIMARY_TASK"
        fi

        # Detect plan to migrate: prefer work_context my_plan, then handoff, then old current_plan
        PREV_PLAN_REL=$(grep -E "^plans/" "$HANDOFF" 2>/dev/null | head -1)
        if [[ -n "$PREV_PLAN_REL" ]]; then
            PREV_PLAN_FULL="$CLAUDE_DIR/$PREV_PLAN_REL"
        else
            PREV_PLAN_FULL=$(grep -oE '/[^ ]*/.claude/plans/[a-z0-9][-a-z0-9_]+\.md' "$HANDOFF" 2>/dev/null | head -1)
        fi

        if [[ -z "$PREV_PLAN_FULL" || ! -f "$PREV_PLAN_FULL" ]]; then
            OLD_CURRENT_PLAN="$CLAUDE_DIR/sessions/${SESSION_ID}/current_plan"
            if [[ -f "$OLD_CURRENT_PLAN" ]]; then
                PREV_PLAN_FULL=$(cat "$OLD_CURRENT_PLAN")
            fi
        fi

        PLAN_TO_MIGRATE="${MY_PLAN:-$PREV_PLAN_FULL}"

        # Helper: extract critical constraints from a plan file
        _extract_plan_constraints() {
            local PLAN="$1"
            grep -iE '^\s*(FORBIDDEN|REQUIRED|MUST( use| NOT)?|NEVER|DO NOT|WARNING):?\s' "$PLAN" 2>/dev/null
            grep -oE '§GATEKEEPER\.[0-9A-Z_]+[^|]*' "$PLAN" 2>/dev/null
            grep -iE '^\s*(Use|Always use) .+ (not|instead of) ' "$PLAN" 2>/dev/null
        }

        # === BEADS PATH: plan_to_migrate is a beads ID ===
        if bd_is_beads_id "$PLAN_TO_MIGRATE"; then
            EPIC_ID=$(bd_strip_prefix "$PLAN_TO_MIGRATE")
            echo "  Plan: beads epic $EPIC_ID"

            case "$WORK_TYPE" in
                implementation)
                    EPIC_STATUS=$(bd show "$EPIC_ID" --json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,list): d=d[0]
    print(d.get('status',''))
except:
    print('')
" 2>/dev/null)

                    if [[ "$EPIC_STATUS" == "closed" ]] || bd_plan_is_approved "$EPIC_ID"; then
                        echo ""
                        echo "PLAN APPROVED — BEGIN IMPLEMENTATION"
                        echo "BEADS EPIC: $EPIC_ID"
                        bd show "$EPIC_ID" 2>/dev/null
                        echo ""
                        echo "DO NOT call ExitPlanMode. The plan is already approved."
                        echo "ACTION: Read the plan (bd show $EPIC_ID), find the first incomplete phase, implement it."
                        echo ""
                    else
                        echo ""
                        echo "PLAN IN PROGRESS — CONTINUE PLANNING"
                        echo "BEADS EPIC: $EPIC_ID"
                        bd show "$EPIC_ID" 2>/dev/null
                        echo ""
                        bd children "$EPIC_ID" 2>/dev/null
                        echo ""
                        echo "The plan was not yet approved. Continue where you left off."
                        echo "When the plan is ready, run expert-review then ExitPlanMode."
                        echo ""
                    fi
                    ;;

                meta)
                    echo ""
                    echo "  META-WORK SESSION (not implementation)"
                    echo "  Previous task: $PRIMARY_TASK"
                    echo "  Epic in handoff was being DEBUGGED, not implemented"
                    echo "  ACTION: Summarize what was done, verify fixes, report completion"
                    echo "  DO NOT resume plan implementation"
                    echo ""
                    ;;

                debugging)
                    echo ""
                    echo "  DEBUGGING SESSION"
                    echo "  Previous task: $PRIMARY_TASK"
                    echo "  Epics in handoff are what you were examining, not implementing"
                    echo "  ACTION: Continue debugging or report findings"
                    echo ""
                    ;;

                *)
                    EPIC_STATUS=$(bd show "$EPIC_ID" --json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,list): d=d[0]
    print(d.get('status',''))
except:
    print('')
" 2>/dev/null)

                    if [[ "$EPIC_STATUS" == "closed" ]] || bd_plan_is_approved "$EPIC_ID"; then
                        echo ""
                        echo "PLAN APPROVED — BEGIN IMPLEMENTATION"
                        echo "BEADS EPIC: $EPIC_ID"
                        bd show "$EPIC_ID" 2>/dev/null
                        echo ""
                        echo "DO NOT call ExitPlanMode. The plan is already approved."
                        echo "ACTION: Read the plan, find the first incomplete phase, implement it."
                        echo ""
                    else
                        echo ""
                        echo "PLAN IN PROGRESS — CONTINUE PLANNING"
                        echo "BEADS EPIC: $EPIC_ID"
                        bd show "$EPIC_ID" 2>/dev/null
                        echo ""
                        bd children "$EPIC_ID" 2>/dev/null
                        echo ""
                    fi
                    ;;
            esac

        # === LEGACY FILE PATH ===
        elif [[ -n "$PLAN_TO_MIGRATE" && -f "$PLAN_TO_MIGRATE" ]]; then
            PLAN_MODE=$(grep -E "^Mode: (PLANNING|IMPLEMENTATION)" "$PLAN_TO_MIGRATE" | sed 's/Mode: //')
            echo "  Plan: $PLAN_TO_MIGRATE"

            case "$WORK_TYPE" in
                implementation)
                    if [[ "$PLAN_MODE" == "IMPLEMENTATION" ]]; then
                        echo ""
                        echo "PLAN APPROVED — BEGIN IMPLEMENTATION"
                        echo "Plan: $PLAN_TO_MIGRATE"
                        echo "DO NOT call ExitPlanMode. The plan is already approved."
                        echo "ACTION: Read the plan file above, find the first incomplete phase, implement it."
                        echo ""
                        CONSTRAINTS=$(_extract_plan_constraints "$PLAN_TO_MIGRATE" | sort -u | head -15)
                        if [[ -n "$CONSTRAINTS" ]]; then
                            echo "=== CRITICAL CONSTRAINTS FROM PLAN ==="
                            echo "$CONSTRAINTS"
                            echo "=== END CONSTRAINTS ==="
                            echo ""
                        fi
                    elif grep -q 'expert-review: APPROVED' "$PLAN_TO_MIGRATE" 2>/dev/null; then
                        sed -i 's/Mode: PLANNING/Mode: IMPLEMENTATION/' "$PLAN_TO_MIGRATE" 2>/dev/null
                        sed -i 's/User: PENDING/User: APPROVED/' "$PLAN_TO_MIGRATE" 2>/dev/null
                        echo ""
                        echo "PLAN APPROVED — BEGIN IMPLEMENTATION (auto-fixed Mode)"
                        echo "Plan: $PLAN_TO_MIGRATE"
                        echo ""
                        echo "--- PLAN CONTENT ---"
                        cat "$PLAN_TO_MIGRATE"
                        echo "--- END PLAN ---"
                        echo ""
                        CONSTRAINTS=$(_extract_plan_constraints "$PLAN_TO_MIGRATE" | sort -u | head -15)
                        if [[ -n "$CONSTRAINTS" ]]; then
                            echo "=== CRITICAL CONSTRAINTS FROM PLAN ==="
                            echo "$CONSTRAINTS"
                            echo "=== END CONSTRAINTS ==="
                            echo ""
                        fi
                    else
                        echo ""
                        echo "PLAN IN PROGRESS — CONTINUE PLANNING"
                        echo "Plan: $PLAN_TO_MIGRATE"
                        echo "The plan was not yet approved. Continue where you left off."
                        echo "When the plan is ready, run expert-review then ExitPlanMode."
                        echo ""
                        echo "--- PLAN CONTENT ---"
                        cat "$PLAN_TO_MIGRATE"
                        echo "--- END PLAN ---"
                        echo ""
                    fi
                    ;;

                meta)
                    echo ""
                    echo "  META-WORK SESSION (not implementation)"
                    echo "  Previous task: $PRIMARY_TASK"
                    echo "  Plan listed in handoff is what you were DEBUGGING, not implementing"
                    echo "  ACTION: Summarize what was done, verify fixes, report completion"
                    echo "  DO NOT resume plan implementation"
                    echo ""
                    ;;

                debugging)
                    echo ""
                    echo "  DEBUGGING SESSION"
                    echo "  Previous task: $PRIMARY_TASK"
                    echo "  Plans in handoff are what you were examining, not implementing"
                    echo "  ACTION: Continue debugging or report findings"
                    echo ""
                    ;;

                *)
                    if [[ "$PLAN_MODE" == "IMPLEMENTATION" ]]; then
                        echo ""
                        echo "PLAN APPROVED — BEGIN IMPLEMENTATION"
                        echo "Plan: $PLAN_TO_MIGRATE"
                        echo "DO NOT call ExitPlanMode. The plan is already approved."
                        echo "ACTION: Read the plan file above, find the first incomplete phase, implement it."
                        echo ""
                        CONSTRAINTS=$(_extract_plan_constraints "$PLAN_TO_MIGRATE" | sort -u | head -15)
                        if [[ -n "$CONSTRAINTS" ]]; then
                            echo "=== CRITICAL CONSTRAINTS FROM PLAN ==="
                            echo "$CONSTRAINTS"
                            echo "=== END CONSTRAINTS ==="
                            echo ""
                        fi
                    else
                        echo ""
                        echo "PLAN IN PROGRESS — CONTINUE PLANNING"
                        echo "Plan: $PLAN_TO_MIGRATE"
                        echo "The plan was not yet approved. Continue where you left off."
                        echo "When the plan is ready, run expert-review then ExitPlanMode."
                        echo ""
                        echo "--- PLAN CONTENT ---"
                        cat "$PLAN_TO_MIGRATE"
                        echo "--- END PLAN ---"
                        echo ""
                    fi
                    ;;
            esac
        elif [[ "$WORK_TYPE" == "meta" || "$WORK_TYPE" == "debugging" ]]; then
            echo ""
            echo "  ${WORK_TYPE^^} SESSION (no implementation plan)"
            echo "  Previous task: $PRIMARY_TASK"
            echo "  ACTION: Summarize work done, verify completion"
            echo ""
        fi

        # Common resume footer
        echo "RESUME INSTRUCTIONS:"
        echo "- Read $HANDOFF for full context"
        echo "- If a plan was shown above, CONTINUE WORKING ON IT immediately"
        echo "- After resuming, run: rm $RESUME_FILE"
        echo "- Do NOT ask 'What would you like to work on?' — just continue."
    fi
fi
