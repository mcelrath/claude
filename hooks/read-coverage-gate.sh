#!/bin/bash
# PreToolUse(Read) coverage gate. Sub-agents must read whole files (partial reads
# blocked except top-down paging of >2000-line files); the main session is recorded
# only (it gets read-dep-augment.sh instead). See lib/read_coverage_gate.py.
exec python3 "$HOME/.claude/hooks/lib/read_coverage_gate.py"
