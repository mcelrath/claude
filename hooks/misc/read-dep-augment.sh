#!/bin/bash
# PostToolUse(Read) dependency augmentation. MAIN SESSION + source files only:
# on a partial read, surface the in-file defs the slice skipped + cross-file
# producers/consumers. Sub-agents exit early (they read whole files). Never blocks.
# See lib/read_dep_augment.py.
exec python3 "$HOME/.claude/hooks/lib/read_dep_augment.py"
