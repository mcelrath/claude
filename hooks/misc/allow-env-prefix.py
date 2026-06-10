#!/usr/bin/env python3
"""PreToolUse(Bash) hook: make leading env-var assignments transparent to permissions.

If a command segment starts with VAR=value prefixes (e.g. AGENT_ID=x bridge ...),
strip them and re-check the stripped command against the Bash allowlist in
~/.claude/settings.json. If EVERY segment of the compound command matches an
allow rule (raw or stripped) and NONE matches a deny rule, emit
permissionDecision=allow. Otherwise emit nothing and fall through to the
normal permission flow (prompt). Deny rules always win: any deny match -> no
decision from us.
"""
import json
import os
import re
import sys

ENV_PREFIX = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|\"[^\"]*\"|[^\s;|&(]*)(?:\s+|$))+")


def extract_subshells(text):
    """Return (contents of every $(...), text with each $(...) masked out)."""
    out, i, masked = [], 0, ""
    while True:
        j = text.find("$(", i)
        if j < 0:
            return out, masked + text[i:]
        k, depth = j + 2, 1
        while k < len(text) and depth:
            if text[k] == "(":
                depth += 1
            elif text[k] == ")":
                depth -= 1
            k += 1
        out.append(text[j + 2:k - 1])
        masked += text[i:j] + "SUBST"
        i = k


def normalize(s):
    """Matching variant: drop quotes, expand $HOME and leading ~."""
    s = s.replace('"', "").replace("'", "")
    s = s.replace("${HOME}", "/home/mcelrath").replace("$HOME", "/home/mcelrath")
    if s.startswith("~/"):
        s = "/home/mcelrath/" + s[2:]
    return s

# Shell control-flow tokens: not commands. Bare ones are skipped outright;
# prefix ones are stripped so the carried command is what gets checked.
SKIP_SEGMENTS = {"do", "done", "then", "else", "fi", "esac", "{", "}", ";;", "\\"}
KEYWORD_PREFIXES = ("do ", "then ", "else ", "elif ", "if ", "while ", "until ")
FOR_HEADER = re.compile(r"^for\s+\S+\s+in\b|^for\s+\(\(")
CASE_HEADER = re.compile(r"^case\s+.+\s+in$")

# cd into these roots is considered trusted (own projects + own state dirs).
# A compound command that cd's here and whose every segment matches the Bash
# allowlist is auto-allowed, overriding the harness's cd-before-git heuristic.
TRUSTED_CD_ROOTS = [
    "/home/mcelrath",
    "/tmp",
]


HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_heredocs(cmd):
    """Remove heredoc bodies (opaque data) so segment analysis sees only code."""
    lines = cmd.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        for m in HEREDOC_RE.finditer(line):
            tag = m.group(2)
            i += 1
            while i < len(lines) and lines[i].strip() != tag:
                i += 1  # heredoc body: data, not commands
        i += 1
    return "\n".join(out)


def cd_targets_trusted(segs):
    """True iff every `cd` segment targets a trusted root. No cd -> True."""
    for s in segs:
        if s == "cd" or s.startswith("cd "):
            target = s[2:].strip().split()[0] if len(s) > 2 else ""
            if not target or target.startswith("-"):
                return False
            target = os.path.expanduser(target)
            if not os.path.isabs(target):
                return False
            real = os.path.realpath(target)
            if not any(real == r or real.startswith(r + "/") for r in TRUSTED_CD_ROOTS):
                return False
    return True


def load_bash_patterns():
    allow, deny = [], []
    try:
        with open(os.path.expanduser("~/.claude/settings.json")) as f:
            perm = json.load(f).get("permissions", {})
    except Exception:
        return [], []
    for src, out in ((perm.get("allow", []), allow), (perm.get("deny", []), deny)):
        for r in src:
            m = re.fullmatch(r"Bash\((.*)\)", r)
            if m:
                out.append(m.group(1))
            elif r == "Bash":
                out.append("")
    return allow, deny


def matches(cmd, pat):
    if pat == "":
        return True
    if pat.endswith(":*"):
        return cmd.startswith(pat[:-2])
    if pat.endswith("*"):
        return cmd.startswith(pat[:-1].rstrip())
    return cmd == pat


def split_segments(cmd):
    segs, cur, i, quote, depth = [], "", 0, None, 0
    while i < len(cmd):
        c = cmd[i]
        if quote:
            cur += c
            if c == quote and cmd[i - 1] != "\\":
                quote = None
        elif c in "'\"":
            quote = c
            cur += c
        elif c in "({":
            depth += 1
            cur += c
        elif c in ")}":
            depth = max(0, depth - 1)
            cur += c
        elif depth == 0 and cmd[i:i + 2] in ("&&", "||"):
            segs.append(cur)
            cur = ""
            i += 1
        elif depth == 0 and c == "&" and (cur.endswith(">") or cmd[i + 1:i + 2] == ">"):
            cur += c  # redirection: 2>&1, &>file -- not a separator
        elif depth == 0 and c in ";|&\n":
            segs.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    segs.append(cur)
    return [s.strip() for s in segs if s.strip()]


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if data.get("tool_name") != "Bash":
        return
    cmd = data.get("tool_input", {}).get("command", "") or ""
    cmd = re.sub(r"\\\s*\n\s*", " ", cmd)  # join backslash continuations
    segs = split_segments(strip_heredocs(cmd))
    if not segs:
        return
    if not cd_targets_trusted(segs):
        return  # cd outside trusted roots: let the harness prompt
    allow, deny = load_bash_patterns()
    if not allow:
        return
    queue = list(segs)
    while queue:
        s = queue.pop(0).strip()
        if not s or s.startswith("#") or s in SKIP_SEGMENTS:
            continue  # comments / bare control-flow tokens execute nothing
        # Subshell/group unwrap: "( ... )" or "( ... ) 9>/path" runs exactly its
        # inner segments (the trailing redirection opens a file, runs nothing).
        # Unwrap and queue the contents so flock-guarded build groups are judged
        # by what they actually run (the "Contains subshell" prompt class).
        m_grp = re.fullmatch(r"\(\s*(.*?)\s*\)(?:\s*[0-9]*[<>][>&]?\s*\S+)*", s, re.DOTALL)
        if m_grp:
            queue.extend(split_segments(m_grp.group(1)))
            continue
        changed = True
        while changed:  # strip layered keyword prefixes: "if !", "do then", ...
            changed = False
            for kw in KEYWORD_PREFIXES:
                if s.startswith(kw):
                    s = s[len(kw):].lstrip()
                    changed = True
        # Wrapper-prefix strip: "timeout N cmd" / "nice [-n N] cmd" / "flock [opts] FD"
        # run cmd with the same permissions semantics; judge the wrapped command.
        # A bare "flock -w N 9" (lock acquire, often "|| exit 99") runs nothing.
        changed = True
        while changed:
            changed = False
            m_to = re.match(r"^(?:timeout\s+(?:-k\s+\S+\s+)?\d+[smhd]?\s+|nice\s+(?:-n\s+-?\d+\s+)?)", s)
            if m_to:
                s = s[m_to.end():].lstrip()
                changed = True
        if re.fullmatch(r"flock\s+(?:-[a-zA-Z]+\s+\S+\s+)*\d+(\s*\|\|\s*exit\s+\d+)?", s):
            continue  # lock acquisition: no command executed
        if re.fullmatch(r"exit\s+\d+", s):
            continue
        if not s or FOR_HEADER.match(s) or CASE_HEADER.match(s):
            continue  # loop/case headers bind variables, run nothing
        # Command substitutions run commands: check each one independently,
        # then mask them so env-prefix stripping sees a clean assignment.
        subs, masked = extract_subshells(s)
        for sub in subs:
            queue.extend(split_segments(sub))
        stripped = ENV_PREFIX.sub("", masked)
        variants = [s, masked, stripped, normalize(s), normalize(stripped)]
        if any(matches(v, p) for v in variants for p in deny):
            return  # deny wins: stay silent, let the harness handle it
        if not stripped or stripped == "SUBST":
            continue  # pure assignment / bare substitution: subshells queued above
        if not any(matches(v, p) for v in variants for p in allow):
            return  # some segment isn't allowlisted even after stripping
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason":
                "all segments match the Bash allowlist; env prefixes stripped; "
                "cd targets confined to trusted project roots",
        }
    }))


if __name__ == "__main__":
    main()
