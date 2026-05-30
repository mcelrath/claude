#!/usr/bin/env python3
"""PreToolUse(Write, Bash): redirect script creation from system /tmp to ./tmp/.

Agents NEED scratch scripts -- but a script in system /tmp vanishes on reboot, is not
version-controlled, and cannot be promoted to a cl44/ module. The project keeps a
COMMITTED scratch dir ./tmp/ (ungated, frictionless, preserved). This hook blocks
CREATING a .py/.sh/.lean (etc.) under system /tmp or /var/tmp and redirects to ./tmp/.

Allowed (NOT blocked): reading /tmp; non-script /tmp files (.json/.txt/.log/data);
the harness's own /tmp/claude-* task/output files; anything already under the project.
Fires for sub-agents too (Claude Code v2.1.145+). Fail-open on ANY error -- a bug here
must never block unrelated Write/Bash calls.

Exit 0 = allow. Exit 2 = block with the ./tmp redirect message.
"""
import sys, json, re, os

SCRIPT_EXT = (".py", ".pyi", ".sh", ".bash", ".lean", ".jl")
# a redirect (> / >>) or tee writing to a /tmp script, but NOT /tmp/claude-* (harness)
_BASH_CREATE = re.compile(
    r"""(?:>>?|(?:^|\s)tee(?:\s+-a)?\s+)\s*['"]?(/tmp|/var/tmp)/(?!claude)[\w./+\-]+\.(py|pyi|sh|bash|lean|jl)\b"""
)


def _is_tmp_script_path(path):
    p = (path or "").strip().strip("'\"")
    if not (p.startswith("/tmp/") or p.startswith("/var/tmp/")):
        return False
    if p.startswith("/tmp/claude"):       # harness task/output files
        return False
    return p.endswith(SCRIPT_EXT)


_MSG = (
    "BLOCKED: creating a script under system {loc}. Agents DO need scratch scripts -- "
    "but a /tmp script vanishes on reboot, is not version-controlled, and cannot be "
    "promoted to a cl44/ module. Write it to the project's committed scratch dir "
    "instead:\n"
    "    ./tmp/<topic>/<name>.py        (e.g. ./tmp/ccp/quick_check.py)\n"
    "./tmp/ is git-committed (history preserved), ungated (no cl44 gatekeeper), and is "
    "the staging ground -- promote a load-bearing script to cl44/ when it earns it.\n"
    "(Reading /tmp, non-script /tmp data files, and the harness /tmp/claude-* outputs "
    "are all still fine; only CREATING a script in system /tmp is redirected.)"
)


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0
    tool = d.get("tool_name")
    ti = d.get("tool_input", {}) or {}

    if tool == "Write":
        if _is_tmp_script_path(ti.get("file_path", "")):
            sys.stderr.write(_MSG.format(loc="/tmp"))
            return 2
        return 0

    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        m = _BASH_CREATE.search(cmd)
        if m:
            sys.stderr.write(_MSG.format(loc=m.group(1)))
            return 2
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
