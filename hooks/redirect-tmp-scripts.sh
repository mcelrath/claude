#!/bin/bash
# PreToolUse(Write, Bash): redirect script creation from system /tmp to the project's
# committed scratch ./tmp/. Agents keep scratch; /tmp (lost on reboot, uncommitted,
# non-promotable) is redirected to ./tmp/. Reads + non-script /tmp files + /tmp/claude-*
# stay allowed. See lib/redirect_tmp_scripts.py.
exec python3 "$HOME/.claude/hooks/lib/redirect_tmp_scripts.py"
