#!/bin/bash
# PreToolUse hook: check canonical_results.tsv when computing
# Intercepts Jupyter cell execution and Bash python heredocs
# Returns matching canonical results to prevent recomputation

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

case "$TOOL_NAME" in
    mcp__jupyter__modify_notebook_cells)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('cell_content',''))" 2>/dev/null)
        OP=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('operation',''))" 2>/dev/null)
        [[ "$OP" != "add_code" && "$OP" != "edit_code" ]] && exit 0
        ;;
    Bash)
        CODE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
        echo "$CODE" | grep -qE "python|heredoc|EOF" || exit 0
        ;;
    *) exit 0 ;;
esac

[[ -z "$CODE" ]] && exit 0

TSV="$HOME/Physics/claude/canonical_results.tsv"
[[ ! -f "$TSV" ]] && exit 0

KEYWORDS=""
echo "$CODE" | grep -qiE "tau2|tau_m|tau_squared|eigenval" && KEYWORDS="$KEYWORDS tau2"
echo "$CODE" | grep -qiE "vierbein|det\(e\)|det_e" && KEYWORDS="$KEYWORDS vierbein"
echo "$CODE" | grep -qiE "partition|cosh|exact_Z|Z_closed" && KEYWORDS="$KEYWORDS exact_Z"
echo "$CODE" | grep -qiE "sin2|theta_W|weinberg" && KEYWORDS="$KEYWORDS sin2"
echo "$CODE" | grep -qiE "gamma5|gamma_5|chirality|gamma9|krein" && KEYWORDS="$KEYWORDS gamma5"
echo "$CODE" | grep -qiE "centralizer|gl.4|commutant" && KEYWORDS="$KEYWORDS centralizer"
echo "$CODE" | grep -qiE "neutrino|grade.1|boson.*sector" && KEYWORDS="$KEYWORDS neutrino"
echo "$CODE" | grep -qiE "color.*classif|gl.3|C_2.*casimir" && KEYWORDS="$KEYWORDS color"
echo "$CODE" | grep -qiE "B.L|b_minus_l|baryon.*lepton" && KEYWORDS="$KEYWORDS BL"
echo "$CODE" | grep -qiE "vacuum.*energy|sign.*convention" && KEYWORDS="$KEYWORDS vacuum"
echo "$CODE" | grep -qiE "polylog.*coeff|c_1.*c_3|P.*invol" && KEYWORDS="$KEYWORDS polylog"
echo "$CODE" | grep -qiE "planck.*mass|M_Pl|induced.*grav" && KEYWORDS="$KEYWORDS M_Pl"
echo "$CODE" | grep -qiE "gauge.*coupl|1/g|Var.*bare" && KEYWORDS="$KEYWORDS gauge_coupling"
echo "$CODE" | grep -qiE "mode.*deg|g_b.*b\^2|weyl.*law" && KEYWORDS="$KEYWORDS mode"
echo "$CODE" | grep -qiE "higgs.*mech|bidoublet|custodial" && KEYWORDS="$KEYWORDS higgs"
echo "$CODE" | grep -qiE "gluon.*mass|lambda_a.*tau" && KEYWORDS="$KEYWORDS gluon"
echo "$CODE" | grep -qiE "state.*count|24.*ferm|32.*state|8.*boson" && KEYWORDS="$KEYWORDS state_count"
echo "$CODE" | grep -qiE "massless.*6|6.*massless|quark.*grade" && KEYWORDS="$KEYWORDS massless"
echo "$CODE" | grep -qiE "dilaton|e\^phi|T_0.*lambda" && KEYWORDS="$KEYWORDS dilaton"
echo "$CODE" | grep -qiE "cosmic.*age|freeze.*out|rho.*a\^" && KEYWORDS="$KEYWORDS cosmic"

[[ -z "$KEYWORDS" ]] && exit 0

MATCHES=""
for kw in $KEYWORDS; do
    RESULT=$(grep -i "$kw" "$TSV" | grep -v "^#" | head -3)
    [[ -n "$RESULT" ]] && MATCHES="$MATCHES$RESULT
"
done

MATCHES=$(echo "$MATCHES" | sort -u | head -5)

if [[ -n "$MATCHES" ]]; then
    echo "KNOWN RESULTS (from canonical_results.tsv):"
    echo "$MATCHES" | while IFS=$'\t' read -r key result evidence; do
        [[ -n "$key" ]] && echo "  $key = $result [$evidence]"
    done
    echo "If recomputing to VERIFY, proceed. If recomputing because you forgot, use these values."
fi

exit 0
