#!/bin/bash
# Returns a stable, unique terminal identifier by walking /proc to find the claude
# process and reading its PTY. Output: e.g. "dev-pts-2"
# Falls back to CLAUDE_SESSION env var, then empty string.

_get_terminal_id() {
    local result
    result=$(python3 -c "
import os
pid = os.getppid()
for _ in range(15):
    try:
        comm = open(f'/proc/{pid}/comm').read().strip()
        if comm == 'claude':
            pts = os.readlink(f'/proc/{pid}/fd/0')
            print(pts.replace('/', '-').lstrip('-'))
            break
        pid = int(open(f'/proc/{pid}/stat').read().split()[3])
    except:
        break
" 2>/dev/null)

    if [[ -n "$result" && "$result" != "dev-null" ]]; then
        echo "$result"
    elif [[ -n "$CLAUDE_SESSION" ]]; then
        echo "$CLAUDE_SESSION"
    fi
}
