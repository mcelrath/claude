#!/usr/bin/env python3
"""UserPromptSubmit: SEMANTIC kb surfacing on the incoming prompt (kb-mrl / kb-7lp).

The old surfacing was recency (kb-context.sh: `kb list --limit 3`) or token-overlap
(open_issues_surface.py) — never a vector query, despite the user expecting one.
This hook vector-queries the actual prompt text against the kb (semantic, via
ash:8081) and injects the top relevant findings as additionalContext.

Cheap win: reuses the existing `kb search --json` engine. No new infra.
- similarity floor filters cross-domain noise (kb-mrl's hybrid-workspace concern)
- dedup: kb search auto-excludes session-seen ids; we also _seen-gate by kbq:<id>
  so a finding isn't re-surfaced on every prompt.
- graceful: any failure / embed-down / timeout -> exit 0 (no output, no block).
"""
import sys, os, json, subprocess

sys.path.insert(0, os.path.expanduser('~/.claude/hooks/lib'))
try:
    from _seen import filter_unseen  # noqa: E402
except Exception:
    def filter_unseen(keys):
        return keys

KB_SCRIPT = os.environ.get('KB_SCRIPT', os.path.expanduser('~/Projects/ai/kb/kb.py'))
KB_VENV = os.environ.get('KB_VENV', os.path.expanduser('~/Projects/ai/kb/.venv/bin/python'))
SIM_FLOOR = 0.42      # cosine similarity floor; below this is cross-domain noise
                      # (tuned: 0.55 on-topic hit passed, ~0.40 weak matches dropped)
MAX_SURFACE = 3
MIN_PROMPT_LEN = 25


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    prompt = (data.get('prompt') or '').strip()
    if len(prompt) < MIN_PROMPT_LEN:
        return
    if not (os.path.isfile(KB_SCRIPT) and os.path.isfile(KB_VENV)):
        return

    # Cap query length: long prompts dilute the embedding; first ~600 chars carry intent.
    query = prompt[:600]

    env = dict(os.environ)
    env.setdefault('KB_EMBEDDING_URL', 'http://ash:8081/embedding')
    env.setdefault('KB_EMBEDDING_DIM', '4096')
    try:
        r = subprocess.run(
            [KB_VENV, KB_SCRIPT, 'search', query, '-n', '8', '--json'],
            capture_output=True, text=True, timeout=8, env=env,
        )
    except Exception:
        return  # timeout / embed down -> silent
    if r.returncode != 0 or not r.stdout.strip():
        return
    try:
        results = json.loads(r.stdout)
    except Exception:
        return
    if not isinstance(results, list):
        return

    hits = []
    for rec in results:
        try:
            sim = float(rec.get('similarity') or 0)
        except (TypeError, ValueError):
            sim = 0.0
        if sim < SIM_FLOOR:
            continue
        hits.append((sim, rec))
    if not hits:
        return
    hits.sort(key=lambda x: -x[0])

    keys = [f'kbq:{rec["id"]}' for _, rec in hits[:MAX_SURFACE * 2]]
    fresh = set(filter_unseen(keys))

    lines = []
    for sim, rec in hits:
        if len(lines) >= MAX_SURFACE:
            break
        key = f'kbq:{rec["id"]}'
        if key not in fresh:
            continue
        rid = rec.get('id', '?')
        proj = rec.get('project', '?')
        summ = (rec.get('summary') or rec.get('content') or '')[:80]
        lines.append(f'[KB ~{sim:.2f} {rid} ({proj}): {summ}]')

    if not lines:
        return
    lines.insert(0, 'Possibly-relevant prior findings (semantic match to your prompt — '
                    '`kb get <id>` to read before reimplementing):')
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "\n".join(lines),
        }
    }))


if __name__ == '__main__':
    main()
