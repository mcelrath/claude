#!/usr/bin/env python3
"""Regression test suite for the Claude Code hooks (the "agent harness").

Each hook is pure-ish: it reads a tool-call payload on stdin and decides via
exit code / stdout JSON. This suite asserts that decision on canonical inputs +
the specific regressions fixed in development, so a hook edit can't silently
break agent workflows ("regression-free harness improvement").

Decision model (what we assert per case):
  block    -> exit 2                          (PreToolUse hard block)
  pass     -> exit 0, no allow-decision        (block-hook lets the call through)
  approve  -> exit 0, stdout permissionDecision=allow  (auto-approve hooks)
  defer    -> exit 0, no permissionDecision    (auto-approve hook declines -> normal flow)

Run:  python3 ~/.claude/hooks/tests/run_hook_tests.py        (exit 0 = all pass)
      python3 ~/.claude/hooks/tests/run_hook_tests.py -v     (show every case)
A nonzero exit means a hook's behavior changed — investigate before shipping.
"""
import json, os, subprocess, sys

HOOKS = os.path.expanduser('~/.claude/hooks')


def bash(name): return ['bash', os.path.join(HOOKS, name)]
def py(name):   return ['python3', os.path.join(HOOKS, name)]


def bash_cmd(command, tool='Bash'):
    return {'tool_name': tool, 'tool_input': {'command': command}}


# (label, argv, payload-dict, expect, optional stderr/stdout substring)
CASES = [
    # ---- block-text-search-on-source.sh ----
    ('bts: grep on .py blocks',      bash('block-text-search-on-source.sh'), bash_cmd('grep -n foo bar.py'), 'block', None),
    ('bts: rg on .rs blocks',        bash('block-text-search-on-source.sh'), bash_cmd('rg pattern src/lib.rs'), 'block', None),
    ('bts: cat-source-pipe-grep blocks', bash('block-text-search-on-source.sh'), bash_cmd('cat foo.py | grep x'), 'block', None),
    ('bts: grep of command output passes', bash('block-text-search-on-source.sh'), bash_cmd('bd show kb-1 | grep status'), 'pass', None),
    ('bts: ls|grep passes (output, not source)', bash('block-text-search-on-source.sh'), bash_cmd('ls /tmp | grep foo'), 'pass', None),
    ('bts: ast-grep passes',         bash('block-text-search-on-source.sh'), bash_cmd("ast-grep --lang python --pattern 'def $F($$$): $$$'"), 'pass', None),

    # ---- block-markdown-via-bash.sh (regressions: arrow + commit-message) ----
    ('md: > x.md blocks',            bash('block-markdown-via-bash.sh'), bash_cmd('echo hi > notes.md'), 'block', None),
    ('md: tee x.md blocks',          bash('block-markdown-via-bash.sh'), bash_cmd('echo hi | tee notes.md'), 'block', None),
    ('md: git mv to NEW .md blocks', bash('block-markdown-via-bash.sh'), bash_cmd('git mv old.txt new.md'), 'block', None),
    ('md: cat README.md passes (read)', bash('block-markdown-via-bash.sh'), bash_cmd('cat README.md'), 'pass', None),
    ('md REGRESSION: arrow in commit msg passes',
        bash('block-markdown-via-bash.sh'), bash_cmd('git commit -m "moved survey -> secular-constraints/CLAUDE.md"'), 'pass', None),
    ('md REGRESSION: redirect-glyph inside -m passes',
        bash('block-markdown-via-bash.sh'), bash_cmd('git commit -m "fix: echo>x.md and 2>err.md still blocked"'), 'pass', None),
    ('md: real redirect AFTER -m still blocks',
        bash('block-markdown-via-bash.sh'), bash_cmd('git commit -m "msg" && echo hi > real.md'), 'block', None),

    # ---- guard-destructive-git.sh ----
    ('git: reset --hard blocks',     bash('guard-destructive-git.sh'), bash_cmd('git reset --hard HEAD~1'), 'block', None),
    ('git: stash drop blocks',       bash('guard-destructive-git.sh'), bash_cmd('git stash drop'), 'block', None),
    ('git: clean -f blocks',         bash('guard-destructive-git.sh'), bash_cmd('git clean -fd'), 'block', None),
    ('git: reset --soft passes',     bash('guard-destructive-git.sh'), bash_cmd('git reset --soft HEAD~1'), 'pass', None),
    ('git: restore --staged passes', bash('guard-destructive-git.sh'), bash_cmd('git restore --staged .'), 'pass', None),
    ('git: normal commit passes',    bash('guard-destructive-git.sh'), bash_cmd('git commit --no-gpg-sign -m x'), 'pass', None),

    # ---- block-local-dolt-server.sh ----
    ('dolt: bd dolt start blocks',   bash('block-local-dolt-server.sh'), bash_cmd('bd dolt start'), 'block', None),
    ('dolt: dolt sql-server blocks', bash('block-local-dolt-server.sh'), bash_cmd('dolt sql-server -P 3308'), 'block', None),
    ('dolt: bd dolt status passes',  bash('block-local-dolt-server.sh'), bash_cmd('bd dolt status'), 'pass', None),
    ('dolt: bd list passes',         bash('block-local-dolt-server.sh'), bash_cmd('bd list'), 'pass', None),

    # ---- block-print-spam.sh ----
    ('spam: 3 echo banners block',   bash('block-print-spam.sh'),
        bash_cmd('echo "=== a ==="\necho "=== b ==="\necho "=== c ==="'), 'block', None),
    ('spam: single echo passes',     bash('block-print-spam.sh'), bash_cmd('echo done'), 'pass', None),

    # ---- allow-env-prefix.py (auto-approve via allowlist) ----
    ('env: ash-pcie approves',       py('allow-env-prefix.py'), bash_cmd('ash-pcie info 5'), 'approve', None),
    ('env: bare ls approves',        py('allow-env-prefix.py'), bash_cmd('ls -la /tmp'), 'approve', None),

    # ---- auto-approve-readonly-bash.py ----
    ('ro: cat|head approves',        py('auto-approve-readonly-bash.py'), bash_cmd('cat x.txt | head -5'), 'approve', None),
    ('ro: rm defers (not read-only)', py('auto-approve-readonly-bash.py'), bash_cmd('rm x.txt'), 'defer', None),
]


def run_case(argv, payload):
    p = subprocess.run(argv, input=json.dumps(payload), capture_output=True,
                       text=True, timeout=20)
    return p.returncode, p.stdout, p.stderr


def classify(rc, out):
    if rc == 2:
        return 'block'
    allow = '"permissionDecision"' in out and '"allow"' in out
    if rc == 0 and allow:
        return 'approve'
    if rc == 0 and out.strip():
        return 'output'   # emitted something that isn't an allow (e.g. advisory)
    return 'pass'         # rc 0, no output == defer/pass


def main():
    verbose = '-v' in sys.argv
    npass = nfail = 0
    fails = []
    for label, argv, payload, expect, substr in CASES:
        if not os.path.exists(argv[-1]):
            fails.append(f"SKIP/MISSING hook: {label} ({argv[-1]})"); nfail += 1; continue
        rc, out, err = run_case(argv, payload)
        got = classify(rc, out)
        # 'pass' and 'defer' are the same observable (rc0, no allow-decision)
        ok = (got == expect) or (expect in ('pass', 'defer') and got in ('pass', 'defer'))
        if substr and substr not in (out + err):
            ok = False
        if ok:
            npass += 1
            if verbose: print(f"  PASS  {label}  [{got}]")
        else:
            nfail += 1
            fails.append(f"FAIL  {label}: expected {expect}, got {got} (rc={rc})")
    print(f"\n{npass} passed, {nfail} failed, {len(CASES)} total")
    for f in fails:
        print("  " + f)
    sys.exit(1 if nfail else 0)


if __name__ == '__main__':
    main()
