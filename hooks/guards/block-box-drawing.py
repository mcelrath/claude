#!/usr/bin/env python3
"""PreToolUse(Edit/Write): block box-drawing characters in authored content.

CLAUDE.md anti-pattern + Output Discipline: tables/diagrams must use dashes +
spaces, NEVER box-drawing characters (┌┬┐├┼┤└┴┘│─ and the heavy/double variants).
This enforces the file-content half of that rule (kb-6hn step6) so the prose can
be retired: any NEW content (Edit new_string / Write content) containing a char
in the Unicode Box Drawing block (U+2500–U+257F) is blocked with the dashes fix.

Editing to REMOVE box-drawing is unaffected (the removed chars are in old_string,
not new_string). Reading files with box-drawing is unaffected (Read isn't gated).
"""
import json
import re
import sys

# Unicode Box Drawing block (U+2500–U+257F) ONLY. Deliberately excludes Block
# Elements (U+2580+: █ ░ ▒ ▓) which are used legitimately for the statusline
# context bar — the anti-pattern is box-drawing table/diagram lines, not bars.
BOX_RE = re.compile(r'[─-╿]')


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if data.get('tool_name') not in ('Edit', 'Write'):
        sys.exit(0)
    ti = data.get('tool_input') or {}
    content = ti.get('new_string')
    if content is None:
        content = ti.get('content') or ''
    if not isinstance(content, str) or not BOX_RE.search(content):
        sys.exit(0)

    chars = sorted({c for c in content if BOX_RE.match(c)})
    sample = ' '.join(chars[:12])
    fp = ti.get('file_path', '')
    sys.stderr.write(
        f"BLOCKED: box-drawing characters in content for {fp}\n"
        f"  found: {sample}\n\n"
        "Per CLAUDE.md Output Discipline / Anti-Patterns: tables and diagrams use\n"
        "DASHES + SPACES only — NEVER box-drawing characters (they render\n"
        "inconsistently and are unsearchable). Rewrite the table with '-' separators\n"
        "and plain spaces, e.g.\n"
        "  Col A    Col B\n"
        "  -----    -----\n"
        "  x        y\n"
    )
    sys.exit(2)


if __name__ == '__main__':
    main()
