#!/bin/bash
# Returns a stable, unique terminal identifier by walking the process tree
# using POSIX ps (works on Linux + macOS). Output: e.g. "pts-2" or "ttys003"
# Falls back to CLAUDE_SESSION env var, then empty string.

_get_terminal_id() {
    local result
    result=$(python3 -c "
import subprocess, os
pid = os.getppid()
for _ in range(15):
    r = subprocess.run(['ps', '-p', str(pid), '-o', 'comm=,ppid=,tty='],
                       capture_output=True, text=True)
    parts = r.stdout.strip().split()
    if len(parts) < 3:
        break
    comm, ppid, tty = parts[0], parts[1], parts[2]
    if comm == 'claude' and tty not in ('?', '??'):
        print(tty.replace('/', '-'))
        break
    pid = int(ppid)
" 2>/dev/null)

    if [[ -n "$result" ]]; then
        echo "$result"
    elif [[ -n "$CLAUDE_SESSION" ]]; then
        echo "$CLAUDE_SESSION"
    fi
}
