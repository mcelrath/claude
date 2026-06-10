#!/bin/bash
# PreToolUse hook (Bash). Blocks the recurring `bridge watch ... &` antipattern and any
# non-standalone / foreground `bridge watch` launch.
#
# WHY: the agent-bridge watcher is single-shot -- it must be relaunched on every wake. Agents
# batch the relaunch with other commands to save a tool call, and `&` is the only shell way to
# background ONE process within a foreground Bash call. But a &-backgrounded `bridge watch`
# fires NO task-notification and is reaped when the call returns -- silently breaking the watcher
# protocol (the agent stops getting peer-message wakes). The watcher MUST be launched as its OWN
# Bash call with run_in_background=true (the harness param): never with `&`, never chained, never
# foreground.
#
# The verdict is computed by _bridge_watch_detector.py, which strips heredoc bodies + quoted
# strings first so a `bridge send` whose body mentions "bridge watch" is NOT a false positive.
# Fail-open (exit 0) on any parser error.

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

VERDICT=$(printf '%s' "$INPUT" | python3 "$HOME/.claude/hooks/bridge/_bridge_watch_detector.py" 2>/dev/null)

case "$VERDICT" in
  AMP)   WHY="a trailing/background '&' -- a &-backgrounded process fires NO task-notification and is reaped when the call returns, silently breaking the watcher protocol." ;;
  CHAIN) WHY="other commands chained with it (;, |, &&, or multiple lines) -- the watcher must be launched ALONE." ;;
  FG)    WHY="run_in_background is not true -- a foreground 'bridge watch' blocks the entire turn (it is a blocking call)." ;;
  *)     exit 0 ;;
esac

{
  echo "BLOCKED: \`bridge watch\` must be its OWN Bash call with run_in_background=true."
  echo "Found: $WHY"
  echo
  echo "Correct -- one dedicated call, nothing else in it:"
  echo "  Bash(command=\"~/.agent-bridge/bridge watch <your-id>\", run_in_background=true)"
  echo
  echo "Do NOT use \`&\`, do NOT chain (;, &&, |, extra lines), do NOT run it foreground."
  echo "Put recv / builds / bd / sends in SEPARATE calls. Relaunch the watcher this way after"
  echo "every wake and at turn end. (Hook: block-bridge-watch-background.sh)"
} >&2
exit 2
