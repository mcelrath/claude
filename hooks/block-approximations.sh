#!/bin/bash
# PreToolUse hook: block truncated mode sums, Taylor series approximations,
# curve fitting, and other physics anti-patterns in code
#
# Fires on: Edit, Write, Bash, NotebookEdit, mcp__jupyter__modify_notebook_cells
# Exit 2 = BLOCK the tool call

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null) || true

case "$TOOL_NAME" in
    Edit)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('new_string',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null) || true
        ;;
    Write)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('content',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null) || true
        ;;
    Bash)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null) || true
        FILE=""
        echo "$CODE" | grep -qE "python|heredoc|EOF" || exit 0
        ;;
    NotebookEdit)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('new_source',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('notebook_path',''))" 2>/dev/null) || true
        ;;
    mcp__jupyter__modify_notebook_cells)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('cell_content',''))" 2>/dev/null) || true
        FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('notebook_path',''))" 2>/dev/null) || true
        OP=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('operation',''))" 2>/dev/null) || true
        [[ "$OP" != "add_code" && "$OP" != "edit_code" ]] && exit 0
        ;;
    *) exit 0 ;;
esac

[[ -z "$CODE" ]] && exit 0

# Skip non-physics files (hooks, configs, docs, tests)
if [[ -n "$FILE" ]]; then
    case "$FILE" in
        */.claude/*|*/hooks/*|*/settings.json|*.md|*.txt|*.yaml|*.yml|*.toml|*.cfg|*.ini)
            exit 0 ;;
        */test_*|*_test.py|*/tests/*|*/proofs/scripts/*|*/exploration/*)
            exit 0 ;;
    esac
fi

VIOLATIONS=""

# §GATEKEEPER.2: Truncated mode sums — for b in range(N) pattern
# Allow small fixed ranges (≤9 elements) which are finite algebraic loops, not mode sums.
# Only flag: range(variable), range(large_number≥10), range(start, variable), etc.
if echo "$CODE" | grep -qE 'for\s+b\s+in\s+range\s*\(' 2>/dev/null; then
    # Extract range arguments and check if ALL occurrences are small constants
    LARGE_RANGE=$(echo "$CODE" | grep -oP 'for\s+b\s+in\s+range\s*\(\s*\K[^)]+' 2>/dev/null | while read -r args; do
        # Single arg: range(N) — check if N is a small integer literal
        if echo "$args" | grep -qP '^\s*[0-9]+\s*$'; then
            N=$(echo "$args" | tr -d ' ')
            [[ "$N" -ge 10 ]] && echo "LARGE"
        # Two args: range(start, stop) — check stop
        elif echo "$args" | grep -qP '^\s*[0-9]+\s*,\s*[0-9]+\s*$'; then
            STOP=$(echo "$args" | sed 's/.*,//' | tr -d ' ')
            START=$(echo "$args" | sed 's/,.*//' | tr -d ' ')
            SIZE=$((STOP - START))
            [[ "$SIZE" -ge 10 ]] && echo "LARGE"
        else
            # Variable or expression — assume potentially large
            echo "LARGE"
        fi
    done)
    if [[ -n "$LARGE_RANGE" && "$FILE" != *"zeta_regularized_mode_sum"* ]]; then
        VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.2: 'for b in range(...)' is a TRUNCATED mode sum. Use zeta_regularized_propagator_sum().total instead. Infinite sums are evaluated by analytic continuation, NEVER by truncation."
    fi
fi

# Truncated sums with other variable names (eps, varepsilon, b_max patterns)
if echo "$CODE" | grep -qE 'for\s+\w+\s+in\s+range\s*\(\s*(b_max|n_max|N_max|B_max|cutoff|n_modes)' 2>/dev/null; then
    if [[ "$FILE" != *"zeta_regularized_mode_sum"* ]]; then
        VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.2: Mode sum with explicit cutoff (b_max/n_max/N_max). Use zeta_regularized_propagator_sum().total — no finite cutoff needed."
    fi
fi

# Bare exponential mode sums: sum(... * exp(-beta * eps * b))
if echo "$CODE" | grep -qE 'exp\s*\(\s*-.*\*\s*(eps|varepsilon|epsilon|eps_b|varepsilon_b|eps0)\s*\*\s*b' 2>/dev/null; then
    VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.2: Bare exponential exp(-β·ε·b) in mode sum. Must include Fermi-Dirac + species structure via zeta_regularized_propagator_sum()."
fi

# §GATEKEEPER.7: Loop diagram patterns
if echo "$CODE" | grep -qE 'G\s*\(\s*p\s*\+\s*q|G_pq|_angular_averaged_trace' 2>/dev/null; then
    VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.7: Loop diagram pattern (two propagators G(p)×G(p+q)). Framework is EXACT — use Euclidean spectral sum (256 Fock pairs), not Feynman diagrams."
fi

# §GATEKEEPER.8: Fitting/approximation instead of analytical
if echo "$CODE" | grep -qE 'curve_fit|polyfit|np\.polyfit|lstsq|np\.linalg\.lstsq|scipy\.optimize\.curve_fit' 2>/dev/null; then
    # Allow in test files and exploration scripts
    if [[ "$FILE" == *"/lib/"* ]]; then
        VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.8: Numerical fitting (curve_fit/polyfit/lstsq) in production code. All computations must be EXACT — derive analytically instead of fitting."
    fi
fi

# Taylor series / asymptotic expansion in caller code (not inside zeta library)
if echo "$CODE" | grep -qE 'Taylor|taylor_expand|series_expansion|asymptotic_expansion' 2>/dev/null; then
    if [[ "$FILE" != *"zeta_regularized_mode_sum"* && "$FILE" != *"ewsb_monodromy"* ]]; then
        VIOLATIONS="$VIOLATIONS
WARNING §GATEKEEPER.8: Taylor/asymptotic expansion detected. Are you approximating something that has an exact closed form? Check zeta_regularized_propagator_sum() and ewsb_monodromy first."
    fi
fi

# Truncation patterns: n_terms with small values
if echo "$CODE" | grep -qE 'n_terms\s*=\s*[0-9]+' 2>/dev/null; then
    if [[ "$FILE" != *"zeta_regularized_mode_sum"* && "$FILE" != *"ewsb_monodromy"* ]]; then
        VIOLATIONS="$VIOLATIONS
WARNING: n_terms= parameter detected. If this truncates an infinite series, use zeta_regularized_propagator_sum().total for the exact result."
    fi
fi

# Bare spectral zeta without library
if echo "$CODE" | grep -qE 'sum\s*\(.*b\s*\*\*\s*2\s*\*.*\*\*\s*\(\s*-s\s*\)' 2>/dev/null; then
    VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.2: Bare spectral zeta sum Σ b² × (ε₀b)^(-s). Use zeta_regularized_mode_sum library."
fi

# Split mode sum in caller code
if echo "$CODE" | grep -qE '\.finite_part|\.asymptotic_part|zeta_tail\s*\(' 2>/dev/null; then
    if [[ "$FILE" != *"zeta_regularized_mode_sum"* ]]; then
        VIOLATIONS="$VIOLATIONS
BLOCKED §GATEKEEPER.6: Accessing .finite_part/.asymptotic_part/zeta_tail() in caller code. Always use result.total — never split the mode sum."
    fi
fi

if [[ -n "$VIOLATIONS" ]]; then
    # Check if any are hard blocks (BLOCKED) vs warnings
    if echo "$VIOLATIONS" | grep -q "^BLOCKED"; then
        echo "$VIOLATIONS" >&2
        echo "" >&2
        echo "STOP: Physics anti-pattern detected. See .claude/rules/physics-antipatterns.md for correct patterns." >&2
        echo "If you believe this is a false positive (e.g., editing the zeta library itself), explain to the user." >&2
        exit 2
    else
        # Warnings only — allow but inform
        echo "$VIOLATIONS"
        exit 0
    fi
fi

exit 0
