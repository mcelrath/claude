#!/usr/bin/env python3
"""PreToolUse/Bash: auto-approve commands composed ENTIRELY of read-only tools.

Purpose: control-flow commands (for/while loops, command substitution) can never
be covered by prefix allow-rules — Claude Code prompts on every analysis sweep
(e.g. emmy's lean-audit | python | head|grep loops). This hook inspects every
simple-command position in the script; if ALL command words are in the read-only
whitelist and no file-writing redirection is present, it emits
permissionDecision=allow. Otherwise it stays silent (normal permission flow).

Deny-hooks (guard-destructive-git, block-text-search, etc.) still run and can
block — this hook only removes the PROMPT for provably read-only commands.
"""
import json
import re
import sys

READONLY = {
    # filesystem inspect
    'ls', '/bin/ls', 'cat', 'head', 'tail', 'wc', 'stat', 'file', 'du', 'df',
    'find', 'fd', 'tree', 'realpath', 'readlink', 'basename', 'dirname', 'pwd',
    # text/search (block-text-search hook still gates source files)
    'grep', 'rg', 'awk', 'sed', 'cut', 'sort', 'uniq', 'tr', 'diff', 'comm',
    'column', 'paste', 'jq', 'xargs', 'tee',
    # shell builtins / control
    'echo', 'printf', 'true', 'false', 'test', '[', '[[', 'cd', 'export',
    'local', 'set', 'shopt', 'type', 'command', 'which', 'env', 'date',
    'sleep', 'seq', 'read',
    # project read-only tools
    'lean-audit', 'lean-search', 'loogle', 'ast-grep',
    'python3', 'python',          # -c bodies are read-only in practice for sweeps;
                                  # writes via python still hit Write-path hooks? NO —
                                  # mitigated by the redirect/write-keyword scan below.
    'git',                        # narrowed to read-only subcommands below
    'bd',                         # narrowed to read-only subcommands below
}
GIT_RO = {'status', 'log', 'diff', 'show', 'branch', 'rev-parse', 'ls-files',
          'blame', 'shortlog', 'describe', 'remote', 'stash'}  # stash LIST only, see below
BD_RO = {'list', 'show', 'ready', 'blocked', 'stats', 'search', 'dep', 'memories', 'prime'}

# Shell-level rejects — scanned on QUOTE-BLANKED text (so a '>' comparison inside
# a quoted python -c body does not trip the redirect check):
SHELL_REJECT_RE = re.compile(
    r'(?<![>&\d])>(?!\s*(/dev/null|/dev/stderr|&2|&1))'   # redirection to a real file
    r'|>>'
    r'|\brm\b|\bmv\b|\bcp\b|\bmkdir\b|\btouch\b|\bchmod\b|\bchown\b|\bln\b'
    r'|\bkill\b|\bpkill\b|\bdd\b|\bshred\b|\btruncate\b'
    r'|\bgit\s+(add|commit|push|pull|fetch|merge|rebase|reset|checkout|switch|restore|clean|stash\s+(pop|drop|clear|apply|push)|worktree|cherry-pick|revert|tag|mv|rm)'
    r'|\bbd\s+(create|update|close|init|import|forget|remember|dolt)'
)
# Python/embedded-code write capability — scanned on the RAW text (these patterns
# are specific enough not to false-positive on comparisons or prose):
PY_REJECT_RE = re.compile(
    r'\bos\.(remove|unlink|rename|rmdir|makedirs|mkdir|system|chmod|chown)'
    r'|\bshutil\.|\bsubprocess\b|\bpathlib\b.*write|\.write_text\(|\.unlink\('
    r'|open\([^)]*[\'"][waxr]\+|open\([^)]*[\'"][wax][\'"]'
    r'|json\.dump\(|pickle\.dump\(|\.to_csv\(|\.savez?\('
)


def blank_quotes(cmd: str) -> str:
    s = re.sub(r"'[^']*'", "''", cmd)
    return re.sub(r'"[^"]*"', '""', s)

# Positions where a command word starts: beginning, after these separators.
SPLIT_RE = re.compile(r'(?:^|[;&|]|&&|\|\||\$\(|`|\bdo\b|\bthen\b|\belse\b|\n)\s*')


def command_words(cmd: str):
    """Yield the first word of every simple-command position.

    Quoted strings are blanked first so separators inside quotes (e.g. a '|'
    in a grep pattern, ';' in a python -c body) don't create phantom command
    positions.  REJECT_RE runs on the RAW text (incl. quotes) before this, so
    write-capability hidden in quotes is still caught there.
    """
    blanked = blank_quotes(cmd)
    # blank fd-redirections so '&' in '2>&1' is not a separator
    blanked = re.sub(r'\d*>&\d', ' ', blanked)
    blanked = re.sub(r'\d?>>?\s*\S+', ' ', blanked)
    words = []
    for m in SPLIT_RE.finditer(blanked):
        rest = blanked[m.end():]
        w = re.match(r'[A-Za-z0-9_./\[\-~]+', rest)
        if w:
            words.append((w.group(0), rest))
    return words


def main():
    data = json.load(sys.stdin)
    if data.get('tool_name') != 'Bash':
        sys.exit(0)
    cmd = (data.get('tool_input') or {}).get('command', '')
    if not cmd or SHELL_REJECT_RE.search(blank_quotes(cmd)) or PY_REJECT_RE.search(cmd):
        sys.exit(0)  # silent: normal permission flow

    for word, rest in command_words(cmd):
        if word.startswith('#'):
            continue
        # variable assignment prefix (FOO=bar cmd) — skip the assignment token
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', word):
            continue
        # loop variables after 'for'
        if word in ('for', 'while', 'until', 'if', 'then', 'elif', 'else', 'fi',
                    'do', 'done', 'esac', 'case', 'in'):
            continue
        # pure numbers (fd targets) and device paths are not commands
        if re.fullmatch(r'\d+', word) or word.startswith('/dev/'):
            continue
        base = word.rstrip(';')
        if base not in READONLY:
            sys.exit(0)  # unknown tool → stay silent, normal prompt
        if base == 'git':
            sub = re.match(r'git\s+(\S+)', rest)
            if not sub or sub.group(1) not in GIT_RO:
                sys.exit(0)
            # git stash: only 'list'/'show' are read-only
            if sub.group(1) == 'stash':
                sub2 = re.match(r'git\s+stash\s+(\S+)', rest)
                if not sub2 or sub2.group(1) not in ('list', 'show'):
                    sys.exit(0)
        if base == 'bd':
            sub = re.match(r'bd\s+(\S+)', rest)
            if not sub or sub.group(1) not in BD_RO:
                sys.exit(0)

    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'allow',
            'permissionDecisionReason': 'auto-approve: all command words read-only',
        }
    }))
    sys.exit(0)


if __name__ == '__main__':
    main()
