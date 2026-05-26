#!/bin/bash
# Stop hook: reject unprompted-deferral language in Claude's last turn.
#
# Failure mode this fixes: Claude proposes pausing ("next session", "for
# tonight", "since context is low", "good stopping point") when the user
# hasn't asked to pause. This is performative and subverts the user's
# workflow. The user decides when work stops; Claude does not propose it.
#
# Mechanism: when Claude tries to end a turn, scan the last assistant
# message for defer phrases. If found AND the user's recent messages
# don't contain stop signals ("stop", "pause", "done", "quit", "good
# night", etc.), exit 2 with a directive to continue. The
# stop_hook_active flag prevents infinite loops — if we've already
# blocked once for this stop, the harness will let it through.

INPUT=$(cat)

# Don't loop: if stop hook already fired for this stop, let it through.
# Accept truthy in any form (Python True repr, JSON true string, '1').
STOP_HOOK_ACTIVE=$(echo "$INPUT" | python3 -c "
import sys, json
v = json.load(sys.stdin).get('stop_hook_active', False)
# Normalise to '1' / '0'
if v is True or (isinstance(v, str) and v.lower() == 'true'):
    print('1')
else:
    print('0')
" 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "1" ] && exit 0

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$TRANSCRIPT_PATH" ] && exit 0
[ ! -f "$TRANSCRIPT_PATH" ] && exit 0

# Scan the last assistant turn for defer language. Also look at the last
# 1-2 user messages for explicit stop signals — if user said stop, allow
# the stop.
RESULT=$(python3 - "$TRANSCRIPT_PATH" <<'PY'
import sys, json, re

path = sys.argv[1]

# Tail-read the transcript. Each line is a JSON object representing a
# transcript event. We want the most recent assistant message and any
# user messages from the last few exchanges.
def tail_lines(path, n=400):
    try:
        with open(path, 'rb') as f:
            f.seek(0, 2)
            size = f.tell()
            # Read up to ~2MB tail
            read_back = min(size, 2 * 1024 * 1024)
            f.seek(size - read_back)
            data = f.read()
        text = data.decode('utf-8', errors='replace')
        return text.splitlines()[-n:]
    except Exception:
        return []

lines = tail_lines(path)
if not lines:
    sys.exit(0)

# Walk backward through events to find:
#   - last assistant text content
#   - user messages within the last ~5 turns
last_assistant_text = ''
recent_user_texts = []
turns_seen = 0
for raw in reversed(lines):
    raw = raw.strip()
    if not raw:
        continue
    try:
        ev = json.loads(raw)
    except Exception:
        continue
    role = ev.get('type') or ev.get('role')
    msg = ev.get('message') or ev
    # Handle nested .message.content structure used by Claude Code transcripts
    content_blocks = []
    if isinstance(msg, dict):
        c = msg.get('content', [])
        if isinstance(c, list):
            content_blocks = c
        elif isinstance(c, str):
            content_blocks = [{'type': 'text', 'text': c}]
    role_val = msg.get('role', role) if isinstance(msg, dict) else role
    if role_val == 'assistant' and not last_assistant_text:
        parts = []
        for blk in content_blocks:
            if isinstance(blk, dict) and blk.get('type') == 'text':
                parts.append(blk.get('text', ''))
        last_assistant_text = '\n'.join(parts)
    elif role_val == 'user':
        parts = []
        for blk in content_blocks:
            if isinstance(blk, dict) and blk.get('type') == 'text':
                parts.append(blk.get('text', ''))
            elif isinstance(blk, str):
                parts.append(blk)
        if parts:
            recent_user_texts.append('\n'.join(parts))
            turns_seen += 1
            if turns_seen >= 5:
                break

if not last_assistant_text:
    sys.exit(0)

# Defer language in assistant output (case-insensitive)
defer_rx = re.compile(
    r"(?i)\b("
    r"next\s+session|"
    r"in\s+(?:a\s+|the\s+)?(?:next|another|future)\s+session|"
    r"for\s+tonight|"
    r"call\s+it\s+(?:a\s+day|a\s+night|done\s+for\s+(?:today|tonight))|"
    r"wrap\s+up\s+for\s+(?:now|tonight|today)|"
    r"pick\s+(?:this|it|that)\s+up\s+(?:later|tomorrow|next\s+session|next\s+time)|"
    r"good\s+(?:stopping\s+point|place\s+to\s+(?:stop|pause|break))|"
    r"natural\s+(?:stopping\s+point|place\s+to\s+(?:stop|pause|break))|"
    r"since\s+(?:context|we['']?re|we\s+are)\s+(?:is\s+)?(?:low|running\s+low|getting\s+tight)|"
    r"(?:to|in\s+order\s+to)\s+save\s+context|"
    r"(?:running|getting)\s+low\s+on\s+context|"
    r"context\s+is\s+(?:low|tight|getting\s+tight|running\s+low)|"
    r"we\s+can\s+(?:pick\s+this\s+up|continue|resume)\s+(?:later|tomorrow|next\s+session|next\s+time)|"
    r"(?:until|come\s+back)\s+tomorrow|"
    r"continue\s+(?:in\s+)?(?:the\s+)?next\s+session"
    r")\b"
)

m = defer_rx.search(last_assistant_text)
if not m:
    sys.exit(0)

# Stop-signals from user (allow the stop if any recent user message contains these)
user_stop_rx = re.compile(
    r"(?i)\b("
    r"stop|pause|hold\s+on|wait|"
    r"good\s+night|"
    r"that['']?s\s+enough|enough\s+for\s+(?:today|tonight|now)|"
    r"call\s+it\s+a\s+day|"
    r"bye|see\s+you\s+(?:later|tomorrow)|talk\s+(?:later|tomorrow)|"
    r"i['']?m\s+(?:done|tired|out)|"
    r"let['']?s\s+(?:stop|pause|come\s+back|continue\s+(?:later|tomorrow))|"
    r"resume\s+(?:later|tomorrow|next\s+session)"
    r")\b"
)

for utxt in recent_user_texts:
    if user_stop_rx.search(utxt):
        sys.exit(0)

# Found unprompted defer language. Print the offending phrase and exit 2.
phrase = m.group(0)
# Take a small window around the match for context
start = max(0, m.start() - 60)
end = min(len(last_assistant_text), m.end() + 60)
excerpt = last_assistant_text[start:end].strip().replace('\n', ' ')
# Write structured output to stdout so the bash wrapper can capture it
print(phrase)
print('---')
print(excerpt)
sys.exit(2)
PY
)
RC=$?

if [ "$RC" -eq 2 ]; then
    MATCHED_PHRASE=$(echo "$RESULT" | head -1)
    MATCHED_EXCERPT=$(echo "$RESULT" | sed -n '3p')
    cat >&2 <<EOF
BLOCKED: your last response contains unprompted deferral language.

Matched phrase: $MATCHED_PHRASE
Context:        $MATCHED_EXCERPT

Per CLAUDE.md "Don't propose pauses":
- Compaction is a checkpoint, not a stop. Continue the work.
- Low context is a 'kb add' trigger, not a quit signal.
- The user decides when work stops. You do not propose it.

Continue the work that was in flight. If you have unfinished tasks,
finish them. If you need to checkpoint because of low context, run
'~/.local/bin/kb add' and then keep going. Do not greet the user as
if a new session began, and do not propose to resume later.

If your in-flight work is genuinely blocked by external state (GPU
wedged, missing data, error you cannot diagnose), state the block
plainly without suggesting deferral — the user will tell you to wait
or pivot. Reporting a block is fine; proposing to pause yourself is
not.

This hook fired once. It will not fire again for this stop attempt.
EOF
    exit 2
fi

exit 0
