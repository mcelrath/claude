#!/bin/bash
# Self-test for the Claude Code hook stack. Exercises each block hook with a
# known-bad and known-good input, verifies the expected exit code, and reports
# pass/fail. Run manually after editing any hook or settings.json:
#
#     ~/.claude/hooks/hooks-selftest.sh
#
# Exit 0 = all green. Exit 1 = some test failed.

set -u
HOOKS="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SID="selftest_$$"
PASS=0
FAIL=0
FAILED_NAMES=()

# Run a hook, return its exit code.
# Args: hook_script, json_input
run() {
    local hook="$1"
    local json="$2"
    printf '%s' "$json" | "$hook" >/tmp/_hook_stdout.$$ 2>/tmp/_hook_stderr.$$
    echo $?
}

# Args: name, expected_exit, hook, json
check() {
    local name="$1"
    local expect="$2"
    local hook="$3"
    local json="$4"
    local got
    got=$(run "$hook" "$json")
    if [ "$got" = "$expect" ]; then
        PASS=$((PASS+1))
        # printf '  [ok] %s\n' "$name"
    else
        FAIL=$((FAIL+1))
        FAILED_NAMES+=("$name (expected exit $expect, got $got)")
        printf '  [FAIL] %s — expected exit %s, got %s\n' "$name" "$expect" "$got"
        if [ -s /tmp/_hook_stderr.$$ ]; then
            sed 's/^/    stderr: /' /tmp/_hook_stderr.$$ | head -5
        fi
    fi
}

j() {
    # Build JSON input. Args: key=value pairs. Special: tool_input is JSON-encoded.
    python3 -c '
import sys, json
d = {}
for arg in sys.argv[1:]:
    k, _, v = arg.partition("=")
    if k == "tool_input":
        d[k] = json.loads(v)
    else:
        d[k] = v
print(json.dumps(d))
' "$@"
}

echo "== JSON syntax =="
if python3 -m json.tool "$SETTINGS" >/dev/null 2>&1; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("settings.json is not valid JSON")
    echo "  [FAIL] settings.json malformed"
fi

echo "== block-markdown-files.sh =="
H="$HOOKS/block-markdown-files.sh"
# Allowed: existing CLAUDE.md path pattern (no real file needed, structural allowlist)
check "CLAUDE.md structural allow" 0 "$H" \
    "$(j tool_name=Write session_id="$SID" tool_input='{"file_path":"/home/x/CLAUDE.md"}')"
# Allowed: existing file
touch /tmp/__hook_selftest_existing.md
check "existing-file allow"        0 "$H" \
    "$(j tool_name=Write session_id="$SID" tool_input='{"file_path":"/tmp/__hook_selftest_existing.md"}')"
# Blocked: reflex pattern, no flag, no file
rm -f /tmp/claude-md-allow-$SID /tmp/SUMMARY_FAKE.md
check "reflex SUMMARY.md block"    2 "$H" \
    "$(j tool_name=Write session_id="$SID" tool_input='{"file_path":"/tmp/SUMMARY_FAKE.md"}')"
# Blocked: reflex pattern, flag set (should STILL block)
: > /tmp/claude-md-allow-$SID
check "reflex blocks even w/ flag" 2 "$H" \
    "$(j tool_name=Write session_id="$SID" tool_input='{"file_path":"/tmp/SPRINT_FAKE.md"}')"
# Blocked: new ad-hoc md, no flag
rm -f /tmp/claude-md-allow-$SID /tmp/__hook_selftest_new.md
check "new ad-hoc block w/o flag"  2 "$H" \
    "$(j tool_name=Write session_id="$SID" tool_input='{"file_path":"/tmp/__hook_selftest_new.md"}')"
# Allowed: new ad-hoc md, flag set
: > /tmp/claude-md-allow-$SID
check "new ad-hoc allow w/ flag"   0 "$H" \
    "$(j tool_name=Write session_id="$SID" tool_input='{"file_path":"/tmp/__hook_selftest_new.md"}')"
rm -f /tmp/claude-md-allow-$SID /tmp/__hook_selftest_existing.md

echo "== block-markdown-via-bash.sh =="
H="$HOOKS/block-markdown-via-bash.sh"
check "redirect-to-md no flag"     2 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"echo hi > /tmp/x.md"}')"
check "tee-to-md no flag"          2 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"echo hi | tee /tmp/x.md"}')"
check "mv-to-md no flag"           2 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"mv /tmp/a.txt /tmp/b.md"}')"
check "ls *.md allowed"            0 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"ls /tmp/*.md"}')"
: > /tmp/claude-md-allow-$SID
check "redirect-to-md w/ flag"     0 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"echo hi > /tmp/x.md"}')"
rm -f /tmp/claude-md-allow-$SID

echo "== md-asked-gate.sh (PostToolUse AskUserQuestion) =="
H="$HOOKS/md-asked-gate.sh"
rm -f /tmp/claude-md-allow-$SID
check "AskUserQuestion sets flag"  0 "$H" \
    "$(j tool_name=AskUserQuestion session_id="$SID")"
if [ -e "/tmp/claude-md-allow-$SID" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("md-asked-gate did not set flag")
    echo "  [FAIL] flag not set after AskUserQuestion"
fi
rm -f /tmp/claude-md-allow-$SID

echo "== block-print-spam.sh =="
H="$HOOKS/block-print-spam.sh"
# Block: 3+ decorative lines
SPAM_CMD='python3 <<E
print("=== Running ===")
print("Step 1")
print("Done!")
E'
check "decorative prints block"    2 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input="$(python3 -c 'import json,sys; print(json.dumps({"command":sys.stdin.read()}))' <<<"$SPAM_CMD")")"
# Allow: real computation
check "real compute allow"         0 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"python3 -c \"import numpy as np; print(np.mean([1,2,3]))\""}')"

echo "== block-large-heredoc.sh =="
H="$HOOKS/block-large-heredoc.sh"
# Build a 65-line python heredoc body
LONG_PY=$(python3 -c 'print("\n".join(f"x{i}={i}" for i in range(65)))')
LONG_CMD="python3 <<E
${LONG_PY}
E"
check "python <<EOF 65 lines block" 2 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input="$(python3 -c 'import json,sys; print(json.dumps({"command":sys.stdin.read()}))' <<<"$LONG_CMD")")"
# Allow: same body but going to a file
FILE_CMD="cat > /tmp/x.py <<E
${LONG_PY}
E"
check "cat>file 65 lines allow"    0 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input="$(python3 -c 'import json,sys; print(json.dumps({"command":sys.stdin.read()}))' <<<"$FILE_CMD")")"
# Allow: bd create heredoc
BD_CMD="bd create --description '...' <<E
${LONG_PY}
E"
check "bd create 65 lines allow"   0 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input="$(python3 -c 'import json,sys; print(json.dumps({"command":sys.stdin.read()}))' <<<"$BD_CMD")")"
# Allow: short heredoc
check "short heredoc 5 lines allow" 0 "$H" \
    "$(j tool_name=Bash session_id="$SID" tool_input='{"command":"python3 <<E\nimport sys\nx=1\ny=2\nprint(x+y)\nE"}')"

# Cleanup
rm -f /tmp/_hook_stdout.$$ /tmp/_hook_stderr.$$ /tmp/claude-md-allow-$SID
rm -f /tmp/SUMMARY_FAKE.md /tmp/SPRINT_FAKE.md /tmp/__hook_selftest_*.md

echo
echo "== Summary =="
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    for n in "${FAILED_NAMES[@]}"; do
        echo "  - $n"
    done
    exit 1
fi
echo "All hooks healthy."
exit 0
