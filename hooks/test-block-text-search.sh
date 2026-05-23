#!/usr/bin/env bash
# Test suite for block-text-search-on-source.sh. Runs each case as an
# isolated JSON payload into the hook and checks exit code.

HOOK="$HOME/.claude/hooks/block-text-search-on-source.sh"

PASS=0
FAIL=0

run_case() {
  local desc="$1"; local cmd="$2"; local expect="$3"
  local payload
  payload=$(printf '%s' "$cmd" | python3 -c 'import sys,json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.stdin.read()}}))')
  echo "$payload" | "$HOOK" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$expect" ]; then
    PASS=$((PASS+1))
    printf "PASS  exit=%s  %s\n" "$rc" "$desc"
  else
    FAIL=$((FAIL+1))
    printf "FAIL  exit=%s  expected=%s  %s\n" "$rc" "$expect" "$desc"
  fi
}

# Block cases
run_case "lean grep"              "grep PosDef ~/Physics/mathlib4/Mathlib/LinearAlgebra/Matrix/PosDef.lean" 2
run_case "py grep"                "grep TODO ~/Physics/claude/lib/foo.py" 2
run_case "tex purpose-built"      "grep author ~/Physics/claude/sections/sec2.tex" 2
run_case "pipe .lean | grep"      "cat foo.lean | grep PosDef" 2
run_case "find -exec grep py"     "find ~/Physics/claude/lib -name '*.py' -exec grep -l TODO {} +" 2
run_case "md ast-grep custom"     "grep heading README.md" 2
run_case "toml"                   "grep version Cargo.toml" 2
run_case "xml purpose-built"      "grep tag config.xml" 2
run_case "html ast-grep native"   "grep div index.html" 2
run_case "css"                    "grep color styles.css" 2
run_case "json"                   "grep key data.json" 2
run_case "yaml"                   "grep version config.yaml" 2
run_case "rg .rs"                 "rg fn ~/Physics/claude/lib/foo.rs" 2
run_case "cu CUDA"                "grep kernel kernels/foo.cu" 2
run_case "hip"                    "grep kernel kernels/foo.hip" 2
run_case "sql purpose-built"      "grep SELECT queries/foo.sql" 2
run_case "csv purpose-built"      "grep header data.csv" 2
run_case "log purpose-built"      "grep error /tmp/build.log" 2
run_case "xargs grep"             "find . -name '*.py' | xargs grep TODO" 2

# Allow cases
run_case "txt allowed"            "grep PATTERN /tmp/notes.txt" 0
run_case "ini allowed"            "grep section /etc/foo.ini" 0
run_case "build-dir allow"        "grep error ~/Physics/claude/.lake/build/foo.log" 0
run_case "no extension"           "ls /tmp" 0
run_case "ls bash"                "ls -la ~/.claude/hooks/" 0
run_case "git status"             "git status" 0
run_case "echo no search"         "echo hello world" 0

# False-positive guards (prose mentions of extensions)
run_case "prose .lean files"      "echo 'foo .lean files allowed'" 0
run_case "prose grep-on-.lean"    "echo 'grep-on-.lean discouraged'" 0
run_case "kb add with .py in body" "kb add 'foo .py thing' -t discovery" 0

# Leading-tool exemptions (CLI tools whose BODIES may mention grep/.lean etc.)
run_case "bridge send with grep word"  "bridge send peer 'mentions grep and rg'" 0
run_case "bridge send with .lean ref"  "bridge send peer 'see foo.lean line 5'" 0
run_case "kb add with .lean ref"       "kb add 'CondensateMatrices.tau2_M lives in CondensateMatrices.lean' -t discovery" 0
run_case "bd update with grep word"    "bd update claude-xx --notes 'grep usage now hook-blocked on .py files'" 0
run_case "loogle query"                "loogle 'Matrix.PosDef.add'" 0
run_case "loogle type-pattern"         "loogle 'PosDef ?A → 0 < Matrix.det ?A'" 0
run_case "ast-grep on .py (CORRECT)"   "ast-grep --lang python --pattern 'def \$F(\$\$\$): \$\$\$' lib/foo.py" 0
run_case "sg alias"                    "sg --lang rust --pattern 'fn \$F' src/foo.rs" 0

echo
echo "Total: $((PASS+FAIL))  PASS=$PASS  FAIL=$FAIL"
exit $FAIL
