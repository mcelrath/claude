#!/bin/bash
# UserPromptSubmit hook: inject a rotating 5-rule subset of anti-patterns
# Rotation is deterministic per session (seeded by date + PPID)

ALL_RULES=(
    "rg-before-new-code: grep codebase before implementing anything new"
    "no-mocks: use real data, no stubs or fake implementations"
    "options->AskUserQuestion: never open-ended 'what would you like?'"
    "verify-not-guess: run code, check files; never say 'likely' without evidence"
    "check-pwd: read only requested files; stay in working directory"
    "hook-blocks-FINAL: if a hook exits 2, STOP; do not rephrase or work around"
    "no-backwards-compat: delete old code; no aliases, wrappers, or stubs"
    "kb-research-first: spawn kb-research agent before Edit/Write/Task dispatch"
    "no-print-spam: no print headers, labels, or decorative output in scripts"
    "not-found-ne-open: absence of evidence is not evidence of absence; cite searches"
    "no-averaging: Haar/trace averaging destroys gauge info; justify every projection"
    "closure-verb-check: agent said 'complete/verified'? verify scope vs implied claim"
    "concurrent-edit: git diff before every Edit; stop if file changed by another session"
    "no-taylor: exact analytic continuation required; no truncated series"
    "epic-trigger: 3+ phases or 5+ files? create epic + expert-review first"
)

NRULES=${#ALL_RULES[@]}

# Seed: date (YYYYMMDD) + PPID → deterministic per session-day
SEED=$(( $(date +%Y%m%d) + PPID ))

# Pick 5 indices without replacement using LCG
pick_indices() {
    local seed=$1
    local n=$2
    local count=$3
    local -a picked=()
    local -a used=()
    local s=$seed
    while [[ ${#picked[@]} -lt $count ]]; do
        s=$(( (1664525 * s + 1013904223) & 0x7FFFFFFF ))
        idx=$(( s % n ))
        # Check not already used
        local found=0
        for u in "${used[@]}"; do [[ $u -eq $idx ]] && found=1 && break; done
        if [[ $found -eq 0 ]]; then
            picked+=($idx)
            used+=($idx)
        fi
    done
    echo "${picked[@]}"
}

INDICES=$(pick_indices $SEED $NRULES 5)

echo -n "RULES: "
first=1
for i in $INDICES; do
    [[ $first -eq 0 ]] && echo -n " | "
    echo -n "${ALL_RULES[$i]}"
    first=0
done
echo ""
