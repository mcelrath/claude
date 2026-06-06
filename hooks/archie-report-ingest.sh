#!/bin/bash
# SubagentStop hook: Archie auto-kb-search on agent reports.
#
# Fires on SubagentStop for the archie persona. Reads the subagent's final
# message, runs kb search against it, and emits [ARCHIE-KB] annotated results
# to stdout (injected as a system-reminder by Claude Code).
#
# Improvements over v1:
#  1. Tags + age + type on each line (from kb --json output + _fmt_one_line changes)
#  2. ⚠ CONTESTS flag: corrections/failures with high similarity to message claims
#  3. Paragraph-split search: query each paragraph separately, merge by best score
#  4. Session dedup: write shown IDs to kb-seen file so next search skips them
#  5. Supersedes chain: when a result corrects another entry, show both with arrow
#  6. Score-gap cutoff: drop tail when score gap signals rank-truncation

KB="$HOME/.local/bin/kb"
MAX_CHARS=128000

INPUT=$(cat)

EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)
[[ "$EVENT" != "SubagentStop" ]] && exit 0

SID="${CLAUDE_SESSION_ID:-}"
PERSONA_BASE=""
if [[ -n "$SID" ]]; then
    for d in \
        "$(pwd -P)/.claude/.persona" \
        "$HOME/Physics/secular-constraints/.claude/.persona" \
        "$HOME/Physics/claude/.claude/.persona"; do
        pin="$d/session-$SID"
        if [[ -f "$pin" ]]; then
            full_id=$(tr -d '[:space:]' < "$pin")
            PERSONA_BASE="${full_id%%-*}"
            break
        fi
    done
fi
[[ "$PERSONA_BASE" != "archie" ]] && exit 0

TRANSCRIPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null)

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# All work done in Python for clarity
python3 - "$TRANSCRIPT" "$KB" <<'PYEOF'
import sys, json, os, re, subprocess
from pathlib import Path

TRANSCRIPT = sys.argv[1]
KB = sys.argv[2]
MAX_CHARS = 128000
MAX_RESULTS = 10
MIN_SCORE = 0.55

# --- Read last assistant text from transcript ---
entries = []
with open(TRANSCRIPT) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try: entries.append(json.loads(line))
        except: pass

report = ""
for entry in reversed(entries):
    if entry.get('type') == 'assistant':
        for block in entry.get('message', {}).get('content', []):
            if isinstance(block, dict) and block.get('type') == 'text':
                report = block['text'][:MAX_CHARS]
                break
    if report:
        break

if not report:
    sys.exit(0)

# --- Build queries: full text + each non-trivial paragraph (item 3) ---
paragraphs = [p.strip() for p in re.split(r'\n{2,}', report) if len(p.strip()) > 60]
queries = [report[:2000]]  # full-message query first
queries += [p[:500] for p in paragraphs[:4] if p not in queries]

# --- Run kb search --json --no-dedup for each query; merge by best score ---
merged: dict[str, dict] = {}

for q in queries:
    try:
        proc = subprocess.run(
            [KB, 'search', '--json', '--no-dedup', '-n', '12', q],
            capture_output=True, text=True, timeout=15
        )
        if proc.returncode != 0:
            continue
        results = json.loads(proc.stdout)
        for r in results:
            rid = r['id']
            if rid not in merged or r['score'] > merged[rid]['score']:
                merged[rid] = r
    except Exception:
        pass

if not merged:
    sys.exit(0)

# --- Sort by score, apply score-gap cutoff (item 6) ---
ranked = sorted(merged.values(), key=lambda x: x['score'], reverse=True)
ranked = [r for r in ranked if r['score'] >= MIN_SCORE]

# Drop tail after the largest score gap below rank 3
if len(ranked) > 3:
    gaps = [(ranked[i]['score'] - ranked[i+1]['score'], i) for i in range(2, len(ranked)-1)]
    if gaps:
        max_gap, cut_at = max(gaps)
        if max_gap > 0.08:
            ranked = ranked[:cut_at + 1]

ranked = ranked[:MAX_RESULTS]
if not ranked:
    sys.exit(0)

# --- Load already-seen IDs from session state (item 4 read side) ---
seen_ids: set[str] = set()
try:
    state_dir = '/tmp/claude-kb-state'
    pid = os.getpid()
    for _ in range(6):
        try:
            with open(f'/proc/{pid}/status') as f:
                for line in f:
                    if line.startswith('PPid:'):
                        pid = int(line.split()[1])
                        break
                else:
                    break
        except OSError:
            break
        session_file = f'{state_dir}/session-{pid}'
        if os.path.exists(session_file):
            with open(session_file) as f:
                session_id = f.read().strip()
            seen_file = f'{state_dir}/{session_id}-kb-seen'
            if os.path.exists(seen_file):
                with open(seen_file) as f:
                    seen_ids = {ln.strip() for ln in f if ln.strip().startswith('kb-')}
            break
except Exception:
    pass

# Filter out already-seen; if that would leave nothing, show anyway
unseen = [r for r in ranked if r['id'] not in seen_ids]
if unseen:
    ranked = unseen

# --- Build ID → entry map for supersedes lookup (item 5) ---
id_map = {r['id']: r for r in ranked}

# --- Format output (items 1, 2, 5) ---
TYPE_ABBREV = {'correction':'COR','discovery':'DIS','success':'SUC',
               'failure':'FAI','experiment':'EXP'}
SKIP_TAGS = {'discovery','success','failure','experiment','correction',
             'core-result','technique','detail','proven','heuristic','open-problem'}

def fmt_age(created_at):
    if not created_at: return ''
    try:
        from datetime import datetime, timezone
        # normalise offset-aware ISO strings
        s = str(created_at).replace('Z', '+00:00')
        created = datetime.fromisoformat(s)
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        days = (datetime.now(timezone.utc) - created).days
        if days < 1:   return 'today'
        if days < 14:  return f'{days}d'
        if days < 60:  return f'{days//7}w'
        if days < 365: return f'{days//30}m'
        return f'{days//365}y'
    except Exception:
        return ''

def fmt_line(r, flag=''):
    abbr  = TYPE_ABBREV.get(r.get('type',''), '???')
    age   = fmt_age(r.get('created_at'))
    tags  = [t for t in (r.get('tags') or []) if t not in SKIP_TAGS]
    sim   = r.get('similarity', r.get('score', 0))
    text  = (r.get('summary') or r.get('content','')[:100]).split('\n')[0]
    meta_parts = [abbr]
    if age: meta_parts.append(age)
    if tags: meta_parts.append(','.join(tags[:3]))
    meta = '[' + ' '.join(meta_parts) + ']'
    flag_str = f'  {flag}' if flag else ''
    return f"  {r['id']} ({sim:.2f}) {meta}{flag_str}  {text}"

lines = ['[ARCHIE-KB] Related kb entries:']
shown_ids = []

for r in ranked:
    # Item 2: flag corrections/failures that likely contest a message claim
    flag = ''
    rtype = r.get('type','')
    sim = r.get('similarity', r.get('score', 0))
    if rtype in ('correction', 'failure') and sim >= 0.65:
        flag = '⚠ CONTESTS message claim'
    elif rtype == 'correction':
        flag = '⚠ CORRECTION'

    # Item 5: if this entry supersedes another, show the arrow
    sup_id = r.get('supersedes_id')
    if sup_id:
        flag = (flag + ' ' if flag else '') + f'→ corrects {sup_id}'

    lines.append(fmt_line(r, flag))
    shown_ids.append(r['id'])

    # Item 5: if the superseded entry is also in our result set, mark it
    if sup_id and sup_id in id_map:
        lines.append(f'    (superseded original: {sup_id})')

print('\n'.join(lines))

# --- Write shown IDs to session seen file (item 4 write side) ---
try:
    state_dir = '/tmp/claude-kb-state'
    pid = os.getpid()
    for _ in range(6):
        try:
            with open(f'/proc/{pid}/status') as f:
                for line in f:
                    if line.startswith('PPid:'):
                        pid = int(line.split()[1])
                        break
                else:
                    break
        except OSError:
            break
        session_file = f'{state_dir}/session-{pid}'
        if os.path.exists(session_file):
            with open(session_file) as f:
                session_id = f.read().strip()
            seen_file = f'{state_dir}/{session_id}-kb-seen'
            with open(seen_file, 'a') as f:
                for sid in shown_ids:
                    f.write(sid + '\n')
            break
except Exception:
    pass

PYEOF

exit 0
