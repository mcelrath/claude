---
description: Show Python module structure and docstrings for a source directory
allowed-tools: Bash(python3:*)
argument-hint: [directory-path]
---

# Code Map

Generate a compact map of Python modules with their docstrings.

```
!`python3 $HOME/.claude/hooks/lib/generate_codemap.py $ARGUMENTS 2>&1`
```

Show the output above to the user. If a path argument was provided, it maps that directory. Otherwise it auto-detects lib/, src/, app/, pkg/, or core/ from the project root.
