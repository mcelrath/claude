#!/bin/bash
# team-cleanup.sh - Reconnect or clean up teams on SessionStart
#
# On /clear: PPID stays the same, but session ID changes.
# This hook runs BEFORE history-isolation.sh, so we can read the OLD
# session ID from /tmp and the NEW one from hook input JSON.
#
# 1. Teams owned by our OLD session → update leadSessionId to NEW (reconnect)
# 2. Teams owned by other live sessions → leave alone
# 3. Teams owned by dead sessions → delete (orphan cleanup)
set -euo pipefail

input=$(cat)
NEW_SESSION=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)

TEAMS_DIR="$HOME/.claude/teams"
TASKS_DIR="$HOME/.claude/tasks"
STATE_DIR="/tmp/claude-kb-state"

[[ -d "$TEAMS_DIR" ]] || exit 0
[[ -n "$NEW_SESSION" ]] || exit 0

OLD_SESSION=""
if [[ -f "$STATE_DIR/session-$PPID" ]]; then
    OLD_SESSION=$(cat "$STATE_DIR/session-$PPID")
fi

collect_active_sessions() {
    for f in "$STATE_DIR"/session-*; do
        [[ -f "$f" ]] || continue
        local pid="${f##*session-}"
        if ps -p "$pid" -o comm= &>/dev/null; then
            cat "$f"
        else
            rm -f "$f"
        fi
    done
}

ACTIVE_SESSIONS=$(collect_active_sessions)

dump_team_state() {
    local config="$1"
    local team_dir=$(dirname "$config")
    local team_name=$(basename "$team_dir")

    python3 - "$config" "$TASKS_DIR" "$team_name" << 'PYEOF'
import json, sys, glob, os

config_path, tasks_base, team_name = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(config_path))
lines = []

lines.append(f"TEAM_RECONNECTED: {team_name}")
lines.append(f"  Description: {cfg.get('description', 'none')}")
lines.append(f"  Members:")
for m in cfg.get('members', []):
    lines.append(f"    - {m['name']} ({m.get('agentType','?')}, {m.get('model','?')})")

task_dir = None
for candidate in [os.path.join(tasks_base, team_name)]:
    if os.path.isdir(candidate):
        task_dir = candidate
        break

if task_dir:
    tasks = []
    for tf in sorted(glob.glob(os.path.join(task_dir, '*.json'))):
        try:
            t = json.load(open(tf))
            tasks.append(t)
        except Exception:
            pass
    if tasks:
        lines.append(f"  Tasks ({len(tasks)}):")
        for t in tasks:
            owner = t.get('owner', '')
            owner_str = f" [{owner}]" if owner else ""
            lines.append(f"    {t['id']}. [{t.get('status','?')}]{owner_str} {t.get('subject','?')}")

inbox_dir = os.path.join(os.path.dirname(config_path), 'inboxes')
if os.path.isdir(inbox_dir):
    unread = []
    for inbox_file in glob.glob(os.path.join(inbox_dir, '*.json')):
        member = os.path.basename(inbox_file).replace('.json', '')
        try:
            msgs = json.load(open(inbox_file))
            if not isinstance(msgs, list):
                continue
            for msg in msgs:
                if not msg.get('read', True):
                    text = msg.get('text', '')[:150]
                    if text.startswith('{'):
                        try:
                            parsed = json.loads(msg['text'])
                            mtype = parsed.get('type', '')
                            if mtype in ('shutdown_approved', 'shutdown_request', 'idle'):
                                continue
                            text = parsed.get('content', text)[:150]
                        except Exception:
                            pass
                    unread.append(f"    → {member}: {text}")
        except Exception:
            pass
    if unread:
        lines.append(f"  Unread messages ({len(unread)}):")
        for u in unread[-5:]:
            lines.append(u)

lines.append("  Action: Read team config, check TaskList, send messages to idle teammates")
print('\n'.join(lines))
PYEOF
}

reconnected=0
cleaned=0
for config in "$TEAMS_DIR"/*/config.json; do
    [[ -f "$config" ]] || continue
    team_dir=$(dirname "$config")
    team_name=$(basename "$team_dir")

    lead_session=$(python3 -c "import json; print(json.load(open('$config')).get('leadSessionId',''))" 2>/dev/null)
    [[ -z "$lead_session" ]] && continue

    if [[ -n "$OLD_SESSION" && "$lead_session" == "$OLD_SESSION" ]]; then
        python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
c['leadSessionId'] = '$NEW_SESSION'
with open('$config', 'w') as f:
    json.dump(c, f, indent=2)
"
        dump_team_state "$config"
        reconnected=$((reconnected + 1))
        continue
    fi

    if echo "$ACTIVE_SESSIONS" | grep -qF "$lead_session"; then
        continue
    fi

    rm -rf "$team_dir"
    rm -rf "$TASKS_DIR/$team_name"
    cleaned=$((cleaned + 1))
done

if [[ $cleaned -gt 0 ]]; then
    echo "Cleaned $cleaned orphaned team(s)"
fi

exit 0
