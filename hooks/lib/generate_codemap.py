#!/usr/bin/env python3
"""Generate compact code map showing Python module structure and docstrings."""
import ast
import os
import subprocess
import sys
from pathlib import Path


EXCLUDE_DIRS = {'tests', 'test', '__pycache__', 'archive', 'node_modules', '.git', '.venv', 'venv', 'env'}
SOURCE_DIRS = ['lib', 'src', 'app', 'pkg', 'core']


def first_line(docstring: str) -> str:
    for line in docstring.split('\n'):
        line = line.strip()
        if line:
            return line[:80]
    return ''


def find_source_dir() -> Path | None:
    try:
        root = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True, timeout=5
        ).stdout.strip()
        if root:
            for d in SOURCE_DIRS:
                p = Path(root) / d
                if p.is_dir():
                    return p
    except Exception:
        pass
    for d in SOURCE_DIRS:
        p = Path.cwd() / d
        if p.is_dir():
            return p
    return None


def generate_codemap(source_path: Path) -> str:
    source_path = source_path.resolve()
    if not source_path.is_dir():
        return f'Error: {source_path} is not a directory'

    groups: dict[str, list[tuple[str, str]]] = {}
    rel_name = source_path.name

    for root, dirs, files in os.walk(source_path):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
        rel = Path(root).relative_to(source_path)
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
            groups.setdefault(group, []).append((fname, summary))

    if not groups:
        return f'No Python modules found in {rel_name}/'

    lines = [f'{rel_name}/ Code Map']
    subdirs = sorted(k for k in groups if k)
    order = subdirs + ([''] if '' in groups else [])

    for group in order:
        entries = groups[group]
        header = f'{group}/' if group else 'top-level'
        lines.append(f'\n  {header}')
        for fname, summary in entries:
            lines.append(f'    {fname}: {summary}')

    return '\n'.join(lines)


if __name__ == '__main__':
    if len(sys.argv) >= 2:
        target = Path(sys.argv[1])
    else:
        target = find_source_dir()
        if not target:
            print('No source directory found (tried: ' + ', '.join(SOURCE_DIRS) + ')')
            sys.exit(1)
    print(generate_codemap(target))
