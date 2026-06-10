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


def _build_hook_index():
    """Map hook basename -> full path, walking domain subdirs (post-kb-876
    reorg) but skipping lib/ tests/ __pycache__ (helpers, not hooks). First
    match wins. Lets the suite keep referencing hooks by bare name as they move."""
    idx = {}
    for root, dirs, files in os.walk(HOOKS):
        dirs[:] = [d for d in dirs if d not in ('lib', 'tests', '__pycache__')]
        for f in files:
            if f.endswith(('.sh', '.py')) and f not in idx:
                idx[f] = os.path.join(root, f)
    return idx


_HOOK_INDEX = _build_hook_index()


def _find(name):
    return _HOOK_INDEX.get(name, os.path.join(HOOKS, name))


def bash(name): return ['bash', _find(name)]
def py(name):   return ['python3', _find(name)]


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

    # ---- block-followup-without-bd-id.sh (kb-94j: restored 'deferred' trigger) ----
    ('followup: deferred-to without bd-ID blocks', bash('block-followup-without-bd-id.sh'),
        {'tool_name': 'Write', 'tool_input': {'file_path': '/x/.claude/plans/PLAN-z.md',
         'content': '- Strategy B: deferred to a follow-up epic.\n'}}, 'block', None),
    ('followup: deferred-to WITH bd-ID passes', bash('block-followup-without-bd-id.sh'),
        {'tool_name': 'Write', 'tool_input': {'file_path': '/x/.claude/plans/PLAN-z.md',
         'content': '- kb-1234: sync upstream, deferred to a follow-up epic.\n'}}, 'pass', None),
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


def _run(argv, env=None, stdin=''):
    e = dict(os.environ)
    if env:
        e.update(env)
    return subprocess.run(argv, input=stdin, capture_output=True, text=True,
                          timeout=20, env=e)


def state_tests():
    """Persistent session-state root (kb-h3b): resolution, GC, owed-deferred.

    Returns a list of (label, ok, detail). These are shaped differently from the
    CASES table (they need temp dirs / multi-step setup), so they run as their own
    block and fold their pass/fail into the main tally."""
    import tempfile, shutil, time
    LIB = os.path.join(HOOKS, 'lib')
    r = []

    # 1. _state.py default resolves under ~/.claude/state (CLAUDE_STATE_DIR empty)
    p = _run(['python3', '-c', 'import _state; print(_state.STATE_DIR)'],
             env={'PYTHONPATH': LIB, 'CLAUDE_STATE_DIR': ''})
    got = p.stdout.strip()
    r.append(('state: _state.py default -> ~/.claude/state', got.endswith('/.claude/state'), got))

    # 2. CLAUDE_STATE_DIR override honored (python)
    p = _run(['python3', '-c', 'import _state; print(_state.STATE_DIR)'],
             env={'PYTHONPATH': LIB, 'CLAUDE_STATE_DIR': '/tmp/kbtest-ovr'})
    r.append(('state: CLAUDE_STATE_DIR override (python)', p.stdout.strip() == '/tmp/kbtest-ovr', p.stdout.strip()))

    # 3. state.sh agrees with the python side on the override
    p = _run(['bash', '-c', f'source "{LIB}/state.sh"; echo "$STATE_DIR"'],
             env={'CLAUDE_STATE_DIR': '/tmp/kbtest-ovr'})
    r.append(('state: state.sh honors CLAUDE_STATE_DIR', p.stdout.strip() == '/tmp/kbtest-ovr', p.stdout.strip()))

    # 4. session-init GC: old files swept, fresh kept, owed-deferred trimmed by epoch
    T = tempfile.mkdtemp()
    try:
        now = int(time.time())
        old = os.path.join(T, 'sidA-context'); open(old, 'w').close(); os.utime(old, (now - 20000, now - 20000))
        oldd = os.path.join(T, 'sidA-readcov'); os.mkdir(oldd); os.utime(oldd, (now - 20000, now - 20000))
        fresh = os.path.join(T, 'sidB-context'); open(fresh, 'w').close()
        od = os.path.join(T, 'owed-deferred'); open(od, 'w').write(f'{now - 25000} 1 old\n{now - 50} 2 fresh\n')
        _run(['bash', _find('session-init.sh')], env={'CLAUDE_STATE_DIR': T}, stdin='{}')
        body = open(od).read() if os.path.exists(od) else ''
        ok = (not os.path.exists(old)) and (not os.path.exists(oldd)) and os.path.exists(fresh) \
            and ('2 fresh' in body) and ('1 old' not in body)
        r.append(('state: GC sweeps old (+readcov), keeps fresh, trims owed-deferred', ok,
                  f"old_gone={not os.path.exists(old)} dir_gone={not os.path.exists(oldd)} "
                  f"fresh={os.path.exists(fresh)} owed={body.strip()!r}"))
    finally:
        shutil.rmtree(T, ignore_errors=True)

    # 5. owed-deferred persistence: the Stop hook reads DEFER_FILE from the persistent root
    H = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(H, '.agent-bridge')); os.makedirs(os.path.join(H, 'state'))
        open(os.path.join(H, '.agent-bridge', 'messages.jsonl'), 'w').write(
            json.dumps({"id": 1, "ts": "t", "sender": "peer", "to": ["me"],
                        "needs_reply": True, "subject": "q", "body": "b"}) + '\n')
        hook = py('bridge-owed-reply-stop.py')
        # HOME is a throwaway (to isolate the bridge mailbox), but the hook
        # resolves lib via ~/.claude/hooks/lib (move-safe, HOME-relative) — so
        # point PYTHONPATH at the REAL lib for the _state import to resolve.
        env = {'HOME': H, 'AGENT_ID': 'me', 'CLAUDE_STATE_DIR': os.path.join(H, 'state'),
               'BRIDGE_OWED_HARD_BLOCK': '1', 'PYTHONPATH': os.path.join(HOOKS, 'lib')}
        p = _run(hook, env=env, stdin='{}')               # no defer -> hard block
        r.append(('bridge owed-deferred: blocks without defer (exit 2)', p.returncode == 2, f"rc={p.returncode}"))
        open(os.path.join(H, 'state', 'owed-deferred'), 'w').write(f'{int(time.time())} 1 testing\n')
        p2 = _run(hook, env=env, stdin='{}')              # fresh defer at persistent root -> cleared
        r.append(('bridge owed-deferred: defer at persistent root clears block (exit 0)', p2.returncode == 0, f"rc={p2.returncode}"))
    finally:
        shutil.rmtree(H, ignore_errors=True)

    return r


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
    for label, ok, detail in state_tests():
        if ok:
            npass += 1
            if verbose: print(f"  PASS  {label}")
        else:
            nfail += 1
            fails.append(f"FAIL  {label}: {detail}")
    # settings-path verifier (kb-876 reorg safety net) folds in as one case.
    vp = os.path.join(HOOKS, 'tests', 'verify_settings_paths.py')
    if os.path.exists(vp):
        r = subprocess.run(['python3', vp], capture_output=True, text=True)
        if r.returncode == 0:
            npass += 1
            if verbose: print("  PASS  settings-path verifier (all hook paths resolve)")
        else:
            nfail += 1
            fails.append("FAIL  settings-path verifier: " + (r.stderr.strip().splitlines() or ['a hook path does not resolve'])[-1])
    print(f"\n{npass} passed, {nfail} failed, {npass + nfail} total")
    for f in fails:
        print("  " + f)
    sys.exit(1 if nfail else 0)


if __name__ == '__main__':
    main()
