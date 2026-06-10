#!/usr/bin/env python3
"""Settings-path verifier — the kb-876 reorg safety net.

Every hook is wired into Claude Code by an ABSOLUTE path in a settings.json
`hooks.<event>[].hooks[].command` string. When hooks move into domain subdirs,
a single un-updated path makes that hook SILENTLY stop firing (a guard vanishes
with no error). This script parses every settings file that references
`.claude/hooks/`, extracts each referenced hook-script path, and asserts it
exists and is executable. Run it after EVERY reorg phase.

Critically it scans NOT just the global settings but the Physics project
settings too — those reference compose_time_check.py / symbol_surface.py by
absolute path and would dangle green if only the global file were checked.

Exit 0 = every referenced hook path resolves. Exit 1 = at least one is missing
(listed on stderr). Pass -v to print every checked path.







"""
import json
import os
import re
import sys

HOME = os.path.expanduser('~')

# Settings files that reference $HOME/.claude/hooks/. Resolve the global symlink
# to its real file. Physics project settings are first-class consumers (the
# compose_time_check / symbol_surface absolute refs).
SETTINGS_FILES = [
    os.path.join(HOME, 'Projects/ai/claude/settings.json'),          # global (real)
    os.path.join(HOME, 'Physics/claude/.claude/settings.json'),
    os.path.join(HOME, 'Physics/secular-constraints/.claude/settings.json'),
]

# A hook-script path token inside a command string: $HOME-prefixed or the literal
# /home/<user>/ form, under .claude/hooks/, ending in .sh or .py.
PATH_RX = re.compile(r'(?:\$HOME|/home/[^/\s"\']+)/\.claude/hooks/[^\s"\';|&]+\.(?:sh|py)')

EXPECTED_GLOBAL = 62  # sanity check; update if the hook set legitimately changes


def _commands(obj):
    """Yield every hooks.<event>[].hooks[].command string in a settings dict."""
    hooks = obj.get('hooks', {})
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            continue
        for g in groups:
            for h in (g.get('hooks') or []):
                cmd = h.get('command')
                if isinstance(cmd, str):
                    yield event, cmd


def main():
    verbose = '-v' in sys.argv
    missing = []
    total = 0
    per_file = {}
    for sf in SETTINGS_FILES:
        if not os.path.isfile(sf):
            sys.stderr.write(f"NOTE: settings file absent (skipped): {sf}\n")
            continue
        try:
            data = json.load(open(sf))
        except Exception as e:
            sys.stderr.write(f"ERROR: cannot parse {sf}: {e}\n")
            return 1
        n = 0
        for event, cmd in _commands(data):
            for m in PATH_RX.findall(cmd):
                path = m.replace('$HOME', HOME)
                total += 1
                n += 1
                # +x is only required for a BARE-path invocation; a hook run via
                # an interpreter (`python3 X.py`, `bash X.sh`) needs only to exist.
                interp = re.search(r'(?:python3?|bash|sh)\s+' + re.escape(m), cmd) is not None
                exists = os.path.isfile(path)
                ok = exists and (interp or os.access(path, os.X_OK))
                if verbose:
                    print(f"  {'OK ' if ok else 'BAD'} [{os.path.basename(sf)}:{event}] {path}")
                if not ok:
                    reason = 'missing' if not exists else 'not executable (bare-invoked)'
                    missing.append(f"  {reason}: {path}  (in {sf} {event})")
        per_file[sf] = n

    g = per_file.get(SETTINGS_FILES[0], 0)
    print(f"\nverify_settings_paths: {total} hook path refs checked across "
          f"{len([f for f in per_file])} settings file(s); global={g}")
    if g and g != EXPECTED_GLOBAL:
        print(f"  NOTE: global ref count {g} != expected {EXPECTED_GLOBAL} "
              f"(update EXPECTED_GLOBAL if the hook set changed intentionally)")
    if missing:
        sys.stderr.write(f"\nFAIL: {len(missing)} referenced hook path(s) do not resolve:\n")
        sys.stderr.write("\n".join(missing) + "\n")
        return 1
    print("PASS: every referenced hook path resolves to an executable file.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
