"""Shared bash command tokenizer + allow-rule matching for the auto-approve hooks.

Claude Code's permission analyzer prompts on ANY compound/expansion-bearing Bash
command (simple_expansion `$v`, arithmetic `$((v))`, command-substitution
`$(...)`, loops) because it can't statically match it against the prefix
allowlist — even when every tool in it IS allowlisted. The auto-approve hooks
close that gap by parsing the command into command-word positions and checking
each against a trusted set, then emitting permissionDecision=allow.

This module is the SINGLE source of that fragile tokenizer so the read-only
approver and the allowlisted-compound approver can't diverge.
"""
import json
import os
import re


def blank_quotes(cmd: str) -> str:
    """Replace quoted-string bodies with empty quotes so separators inside them
    (a '|' in a grep pattern, ';' in a python -c body) don't create phantom
    command positions. Reject-scans run on the RAW text before this."""
    s = re.sub(r"'[^']*'", "''", cmd)
    return re.sub(r'"[^"]*"', '""', s)


# Command-word starts: line start, after a separator, after a control keyword,
# inside command substitution. if/elif/while/until are INCLUDED so the command
# they introduce IS checked (else `if EVILCMD; then` would slip through unseen).
SPLIT_RE = re.compile(
    r'(?:^|[;&|]|&&|\|\||\$\(|`|\bdo\b|\bthen\b|\belse\b'
    r'|\bif\b|\belif\b|\bwhile\b|\buntil\b|\n)\s*')

# Shell control keywords / loop scaffolding — not commands to check.
SKIP_WORDS = {
    'for', 'while', 'until', 'if', 'then', 'elif', 'else', 'fi', 'do', 'done',
    'esac', 'case', 'in', 'select', 'function', 'time', '{', '}', '!',
    # loop/flow control builtins (harmless; NOT eval/exec/source which can run
    # arbitrary code and must remain checked)
    'break', 'continue', 'return', 'shift', 'wait', 'exit',
}


def command_words(cmd: str):
    """Yield (word, rest) for every simple-command position. `word` is the first
    token; `rest` is the blanked text from that token onward (used to detect
    assignments and multi-word tool prefixes like `systemctl --user`)."""
    blanked = blank_quotes(cmd)
    blanked = re.sub(r'\d*>&\d', ' ', blanked)        # fd dup (2>&1) is not a sep
    blanked = re.sub(r'\d?>>?\s*\S+', ' ', blanked)   # blank output redirects
    words = []
    for m in SPLIT_RE.finditer(blanked):
        rest = blanked[m.end():]
        w = re.match(r'[A-Za-z0-9_./\[\-~]+', rest)
        if w:
            words.append((w.group(0), rest))
    return words


# Read-only-by-NAMING-CONVENTION project diagnostic binaries (oracles/probes).
DIAG_RE = re.compile(r'(?:[-_](?:oracle|test|probe))$|^iptest\d*$')
DIAG_EXPLICIT = {
    'am-rs-p2p_decode_oracle', 'am-rs-p2p_copy_test', 'iptest', 'iptest2',
    'iptest3', 'llm-test',
}
DIAG_TRUSTED_PREFIXES = (
    '/home/mcelrath/.local/bin/', '~/.local/bin/',
    './build/bin/', 'build/bin/', './bin/', 'bin/',
)


def is_diagnostic(word: str) -> bool:
    """Read-only diagnostic binary: basename ends -oracle/-test/-probe (or
    iptestN) AND is a bare name or under a trusted bin dir (so /tmp/evil_oracle
    is NOT trusted)."""
    bn = word.rsplit('/', 1)[-1]
    if bn not in DIAG_EXPLICIT and not DIAG_RE.search(bn):
        return False
    if '/' not in word:
        return True
    return word.startswith(DIAG_TRUSTED_PREFIXES)


def load_allow_prefixes(settings_path: str | None = None) -> list[str]:
    """Parse settings.json permissions.allow into Bash command prefixes.

    `Bash(systemctl --user:*)` -> 'systemctl --user'; `Bash(curl:*)` -> 'curl';
    `Bash(./build/bin/*:*)` -> './build/bin/*'; bare `Bash(echo:*)` -> 'echo'.
    Trailing `:*`, ` *`, and `:` are stripped. Non-Bash rules are ignored."""
    path = settings_path or os.path.expanduser('~/.claude/settings.json')
    try:
        allow = json.load(open(path)).get('permissions', {}).get('allow', [])
    except Exception:
        return []
    prefixes = []
    for rule in allow:
        if not (isinstance(rule, str) and rule.startswith('Bash(') and rule.endswith(')')):
            continue
        spec = rule[5:-1]                      # inside Bash(...)
        spec = re.sub(r':\*$', '', spec)        # drop trailing :*
        spec = re.sub(r'\s+\*$', '', spec)      # drop trailing  *
        spec = spec.rstrip(':').strip()
        # Skip degenerate / redirection specs like 'cat >' or empty.
        if not spec or '>' in spec or '<' in spec:
            continue
        prefixes.append(spec)
    return prefixes


def matches_allow(base: str, rest: str, prefixes: list[str]) -> bool:
    """True if this command position is covered by an allow prefix.

    Handles multi-word prefixes ('systemctl --user'), glob path prefixes
    ('./build/bin/*'), and ~ expansion. `rest` is the (quote-blanked) text from
    the command token onward, so a multi-word prefix is matched against it."""
    home = os.path.expanduser('~')
    cand_rest = rest.replace('~', home, 1) if rest.startswith('~') else rest
    cand_base = base.replace('~', home, 1) if base.startswith('~') else base
    for p in prefixes:
        pe = p.replace('~', home, 1) if p.startswith('~') else p
        if '*' in pe or '?' in pe:
            # glob prefix (e.g. /abs/bin/*): match the command token (path)
            import fnmatch
            if fnmatch.fnmatch(cand_base, pe):
                return True
            continue
        if ' ' in pe:
            # multi-word prefix: match against the full rest, word-bounded
            if cand_rest == pe or cand_rest.startswith(pe + ' '):
                return True
            continue
        # single-word tool prefix: the command token must equal it
        if cand_base == pe or cand_base.rstrip(';') == pe:
            return True
    return False
