#!/usr/bin/env python3
"""Generate compact code map from lib/ module docstrings."""
import ast
import os
import sys
from pathlib import Path


EXCLUDE_DIRS = {'tests', '__pycache__', 'archive'}


def first_line(docstring: str) -> str:
    """Extract first meaningful line from docstring, truncate to 80 chars."""
    for line in docstring.split('\n'):
        line = line.strip()
        if line:
            return line[:80]
    return ''


def generate_codemap(lib_path: str) -> str:
    lib = Path(lib_path).resolve()
    if not lib.is_dir():
        return f'# Error: {lib_path} is not a directory'

    # Collect modules grouped by subdirectory
    groups: dict[str, list[tuple[str, str]]] = {}

    for root, dirs, files in os.walk(lib):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        rel = Path(root).relative_to(lib)
        group = str(rel) if str(rel) != '.' else ''

        for fname in sorted(files):
            if not fname.endswith('.py') or fname == '__init__.py':
                continue
            fpath = Path(root) / fname
            try:
                tree = ast.parse(fpath.read_text())
                doc = ast.get_docstring(tree) or ''
                summary = first_line(doc) if doc else '(no docstring)'
            except Exception:
                summary = '(parse error)'
            if group not in groups:
                groups[group] = []
            groups[group].append((fname, summary))

    # Build output
    lines = [f'# lib/ Code Map (auto-generated)']

    # Order: named subdirectories first (sorted), then top-level last
    subdirs = sorted(k for k in groups if k)
    order = subdirs + ([''] if '' in groups else [])

    for group in order:
        entries = groups[group]
        if group:
            lines.append(f'\n## {group}/')
        else:
            lines.append(f'\n## Top-level')
        for fname, summary in entries:
            lines.append(f'{fname}: {summary}')

    return '\n'.join(lines)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: generate_codemap.py <lib_path>', file=sys.stderr)
        sys.exit(1)
    print(generate_codemap(sys.argv[1]))
