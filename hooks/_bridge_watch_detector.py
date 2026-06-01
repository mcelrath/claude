#!/usr/bin/env python3
"""Verdict for the block-bridge-watch-background PreToolUse hook.

Reads the Claude Code hook input JSON on stdin; prints exactly one of:
  OK    - allow (not a `bridge watch` invocation, or a clean standalone run_in_background launch)
  AMP   - `bridge watch` backgrounded with a trailing/inline `&` (the antipattern)
  CHAIN - `bridge watch` chained with other commands / not standalone
  FG    - `bridge watch` foreground (run_in_background explicitly not true)

Heredoc bodies and quoted strings are stripped FIRST, so a `bridge send` whose
message body mentions "bridge watch" is NOT a false positive -- only an actual
`bridge watch` *invocation* in command position fires. Fail-open (prints OK) on
any parse error.

Why this hook exists: the agent-bridge watcher is single-shot (relaunched on every
wake). A `&`-backgrounded `bridge watch` fires NO task-notification and is reaped
when the foreground call returns -- silently breaking the watcher protocol. The
watcher must be its OWN Bash call with run_in_background=true.
"""
import sys
import json
import re


def verdict(cmd: str, rib) -> str:
    # 1. Drop heredoc bodies (keep the line that opens the heredoc; drop body + delimiter).
    kept, delim = [], None
    for ln in cmd.split("\n"):
        if delim is not None:
            if ln.strip() == delim:
                delim = None
            continue
        kept.append(ln)
        m = re.search(r"""<<-?\s*['"]?(\w+)['"]?""", ln)
        if m:
            delim = m.group(1)
    code = "\n".join(kept)

    # 2. Drop quoted strings (message bodies, quoted args) so they aren't scanned.
    code = re.sub(r'"[^"]*"', " ", code)
    code = re.sub(r"'[^']*'", " ", code)

    # 3. Only fire on an actual `bridge watch` invocation.
    if not re.search(r"\bbridge\s+watch\b", code):
        return "OK"

    # 4. Background `&` -- after removing redirects (2>&1, >&, &>) and logical &&.
    red = re.sub(r"\d*[<>]&\d*", " ", code).replace("&>", " ").replace("&&", " ")
    if "&" in red:
        return "AMP"

    # 5. Chained with other commands / not standalone.
    if re.search(r"[;|]", code) or "&&" in code or len([l for l in kept if l.strip()]) > 1:
        return "CHAIN"

    # 6. Foreground (run_in_background explicitly false).
    if rib is False:
        return "FG"

    return "OK"


def main():
    try:
        d = json.load(sys.stdin)
        ti = d.get("tool_input", {}) or {}
        cmd = ti.get("command", "") or ""
        rib = ti.get("run_in_background", None)
    except Exception:
        print("OK")
        return
    print(verdict(cmd, rib))


if __name__ == "__main__":
    main()
