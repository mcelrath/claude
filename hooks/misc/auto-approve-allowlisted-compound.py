#!/usr/bin/env python3
"""PreToolUse/Bash: auto-approve a COMPOUND command when every command-word in it
is already covered by the user's static Bash(...) allow rules (or is a read-only
diagnostic binary), EXCEPT a hard denylist of catastrophic/irreversible verbs.

Why: Claude Code's analyzer prompts on any compound/expansion-bearing command
(simple_expansion `$v`, arithmetic `$((v))`, `$(...)`, loops) even when every
tool is allowlisted — the static allowlist only matches SIMPLE commands. This
generalizes the allowlist to compounds (agents' infra/test loops: systemctl
--user start/stop, curl probes, launch-gpu --status, pgrep, oracle test-loops).

Safety:
 - Catastrophic verbs (rm, dd, mkfs, shred, truncate, recursive chmod/chown,
   fork-bomb) NEVER auto-approve here — they still prompt.
 - Every command-word must match an allow prefix; one unknown tool -> stay silent
   (normal prompt).
 - DENY hooks (guard-destructive-git, block-text-search, block-markdown, ...)
   still run and can BLOCK regardless of this allow.
This only removes the PROMPT for compounds built from already-trusted tools.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from bash_words import (  # noqa: E402
    blank_quotes, command_words, is_diagnostic, load_allow_prefixes,
    matches_allow, SKIP_WORDS,
)

# Irreversible / catastrophic verbs: never auto-approve in a compound even if the
# tool is allowlisted — these still get the prompt. (git's destructive verbs are
# separately hard-blocked by guard-destructive-git.)
CATASTROPHIC_RE = re.compile(
    r'\brm\b|\bdd\b|\bmkfs\b|\bshred\b|\btruncate\b'
    r'|\bchmod\s+-[A-Za-z]*R|\bchown\s+-[A-Za-z]*R'
    r'|:\s*\(\s*\)\s*\{'          # fork bomb  :(){ ...
)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if data.get('tool_name') != 'Bash':
        sys.exit(0)
    cmd = (data.get('tool_input') or {}).get('command', '')
    if not cmd:
        sys.exit(0)

    blanked = blank_quotes(cmd)
    if CATASTROPHIC_RE.search(blanked):
        sys.exit(0)  # catastrophic verb -> prompt, never auto-approve

    prefixes = load_allow_prefixes()
    if not prefixes:
        sys.exit(0)  # couldn't read allowlist -> don't approve blind

    saw_word = False
    for word, rest in command_words(cmd):
        if word.startswith('#'):
            continue
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', rest):  # FOO=bar / n=$((n+1))
            continue
        if word in SKIP_WORDS:
            continue
        if re.fullmatch(r'\d+', word) or word.startswith('/dev/'):
            continue
        base = word.rstrip(';')
        if is_diagnostic(base):
            saw_word = True
            continue
        if matches_allow(base, rest, prefixes):
            saw_word = True
            continue
        sys.exit(0)  # an un-allowlisted command word -> normal prompt

    if not saw_word:
        sys.exit(0)  # nothing concrete matched -> let normal flow handle it

    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'allow',
            'permissionDecisionReason': 'auto-approve: all command words are allowlisted (compound); no catastrophic verb',
        }
    }))
    sys.exit(0)


if __name__ == '__main__':
    main()
