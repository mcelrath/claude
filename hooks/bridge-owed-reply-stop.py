#!/usr/bin/env python3
"""Stop hook: surface INBOUND --needs-reply messages I have NOT replied to.

Fills the gap left by bridge-unread-stop.sh, which only tracks UNREAD messages +
my OUTBOUND pending-replies. A message I've already READ but not REPLIED to falls
through BOTH (it's no longer unread; it isn't something I sent) — the exact way a
busy agent juggling 3+ peers silently drops a reply.

An "owed reply" = a message in ~/.agent-bridge/messages.jsonl where:
  - I am in `to`            (directed to me; broadcasts to 'all' excluded),
  - needs_reply == True     (sender explicitly flagged --needs-reply),
  - it isn't superseded,    (no later msg with supersedes == its id),
  - and NO message from me has reply_to == its id   (I haven't answered it).
It persists across reads and clears only when I `bridge send … --reply <id>`.

Default ADVISORY (exit 0): re-surfaces every Stop until replied — loop-safe.
Set BRIDGE_OWED_HARD_BLOCK=1 to make it a HARD gate (exit 2) that prevents idle
while any reply is owed AND not deliberately deferred.

DEFER ESCAPE (so the hard gate forces TRIAGE, not infinite reply): an owed item
can be consciously deferred for DEFER_TTL by appending one line to
~/.claude/state/owed-deferred:  "<epoch> <id> <reason>".  Deferred items stop
BLOCKING but stay LISTED (advisory) and re-block automatically after the TTL, so
deferral is a logged, time-boxed choice — never a silent drop. Replying
(`bridge send … --reply <id>`) clears an item entirely.
"""
import sys, os, json, subprocess, time

MSGS = os.path.expanduser('~/.agent-bridge/messages.jsonl')
BRIDGE = os.path.expanduser('~/.agent-bridge/bridge')
DEFER_FILE = '/tmp/claude-kb-state/owed-deferred'   # sandbox-writable (no escalation prompt)
DEFER_TTL = 6 * 3600   # deferred items re-block after 6h


def my_id() -> str:
    aid = os.environ.get('AGENT_ID', '').strip()
    if aid:
        return aid
    try:
        out = subprocess.run([BRIDGE, 'whoami'], capture_output=True,
                             text=True, timeout=5).stdout
        for line in out.splitlines():
            if line.startswith('Effective identity:'):
                return line.split(':', 1)[1].strip().split()[0]
    except Exception:
        pass
    return ''


def parse_to(s) -> list:
    s = (str(s) if s is not None else '').strip()
    if not s or s == 'None':
        return []
    s = s.strip('[]')
    return [p.strip().strip("'\"") for p in s.split(',') if p.strip().strip("'\"")]


def main():
    # Consume stdin (Stop hook payload) — we don't need it, but drain it.
    try:
        sys.stdin.read()
    except Exception:
        pass
    me = my_id()
    if not me or not os.path.exists(MSGS):
        return
    msgs = []
    for line in open(MSGS):
        line = line.strip()
        if not line:
            continue
        try:
            msgs.append(json.loads(line))
        except Exception:
            pass

    replied = set()      # ids I have replied to
    superseded = set()   # ids superseded by a later message
    for m in msgs:
        if m.get('sender') == me:
            rt = m.get('reply_to')
            if rt not in (None, 'None', ''):
                replied.add(str(rt))
        sup = m.get('supersedes')
        if sup not in (None, 'None', ''):
            superseded.add(str(sup))

    owed = []
    for m in msgs:
        nr = m.get('needs_reply')          # JSON bool true, or legacy string "True"
        if not (nr is True or str(nr) == 'True'):
            continue
        if m.get('sender') == me:
            continue
        if me not in parse_to(m.get('to')):
            continue
        mid = str(m.get('id'))
        if mid in replied or mid in superseded:
            continue
        owed.append(m)

    if not owed:
        return

    # Deferred ids still within TTL (time-boxed, logged conscious deferrals).
    deferred = {}
    try:
        now = time.time()
        for line in open(DEFER_FILE):
            parts = line.split(None, 2)
            if len(parts) < 2:
                continue
            ep, did = parts[0], parts[1]
            reason = parts[2].strip() if len(parts) > 2 else ''
            try:
                if now - float(ep) < DEFER_TTL:
                    deferred[did] = reason
            except ValueError:
                pass
    except FileNotFoundError:
        pass

    def fmt(m):
        d = ' [deferred]' if str(m.get('id')) in deferred else ''
        return f"  #{m.get('id')} from {m.get('sender')}: {str(m.get('subject'))[:70]}{d}"

    blocking = [m for m in owed if str(m.get('id')) not in deferred]
    hard = os.environ.get('BRIDGE_OWED_HARD_BLOCK') == '1'

    if hard and blocking:
        out = [f"⛔ BRIDGE_OWED_REPLIES — {len(blocking)} unanswered --needs-reply "
               f"message(s) BLOCK idle. For EACH, either:",
               f"  reply:  bridge send <sender> \"<subj>\" --reply <id>",
               f"  defer:  echo \"$(date +%s) <id> <why>\" >> /tmp/claude-kb-state/owed-deferred"
               f"   (re-blocks in {DEFER_TTL//3600}h)"]
        out += [fmt(m) for m in blocking]
        if len(blocking) < len(owed):
            out.append("deferred (still owed, will re-surface):")
            out += [fmt(m) for m in owed if str(m.get('id')) in deferred]
        sys.stderr.write("\n".join(out) + "\n")
        sys.exit(2)

    # Advisory: re-inject every Stop until replied (deferred ones flagged).
    lines = [f"⚠ BRIDGE_OWED_REPLIES ({len(owed)}) — peer --needs-reply messages "
             f"you have NOT answered. Close with `bridge send <sender> \"<subj>\" "
             f"--reply <id>`:"]
    lines += [fmt(m) for m in owed]
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "Stop", "additionalContext": "\n".join(lines)}}))
    sys.exit(0)


if __name__ == '__main__':
    main()
