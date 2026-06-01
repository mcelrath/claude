#!/usr/bin/env python3
"""Backfill missing summary column for kb findings.

Iterates `findings` rows where summary IS NULL or empty (status='current'),
calls ContentAnalyzer.generate_summary, writes back. Idempotent.

Usage:
    python3 backfill_summaries.py            # process all missing
    python3 backfill_summaries.py --limit 5  # process first 5 (test)
    python3 backfill_summaries.py --project llama.cpp
    python3 backfill_summaries.py --dry-run  # show what would be done, no writes
"""
import argparse
import os
import sys
import time

# Use the kb package's venv to access ContentAnalyzer + LLMClient.
sys.path.insert(0, "/home/mcelrath/Projects/ai/kb")
os.environ.setdefault("KB_EMBEDDING_URL", "http://ash:8081/embedding")
os.environ.setdefault("KB_LLM_URL", "http://tardis:9510/completion")

import json
import re
import sqlite3
import urllib.request

DB_PATH = "/home/mcelrath/.cache/kb/knowledge.db"
CHAT_URL = "http://tardis:9510/v1/chat/completions"
SYSTEM = ("You write concise one-line summaries of knowledge-base findings. "
          "Output STRICT JSON only: {\"summary\":\"...\"}. "
          "The summary is one technical sentence, max 90 chars, no leading "
          "punctuation, no markdown, no quotes inside.")


def llm_summary(content: str, evidence: str | None) -> str | None:
    text = content[:1200]
    text = re.sub(r"^(?:CRITICAL\s+)?(?:CORRECTION|ERROR|FATAL\s+FLAW|WARNING|NOTE|IMPORTANT):\s*",
                  "", text, flags=re.IGNORECASE)
    text = text.encode("ascii", "ignore").decode("ascii")
    if evidence:
        text += "\nEvidence: " + evidence[:200].encode("ascii", "ignore").decode("ascii")
    body = {
        "model": "qwen3.6",
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": "Summarize in ONE technical line (<=90 chars):\n" + text},
        ],
        "temperature": 0.2,
        "max_tokens": 200,
        "response_format": {"type": "json_object"},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        CHAT_URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as fp:
            resp = json.loads(fp.read())
    except Exception:
        return None
    raw = resp.get("choices", [{}])[0].get("message", {}).get("content", "") or ""
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    i, j = raw.find("{"), raw.rfind("}")
    if i < 0 or j <= i:
        return None
    try:
        obj = json.loads(raw[i:j+1])
    except Exception:
        return None
    s = obj.get("summary") or obj.get("text") or ""
    if not isinstance(s, str):
        return None
    s = s.strip().strip('"').strip("'")
    s = re.sub(r"[\x00-\x1f\x7f]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    words = re.findall(r"[a-zA-Z]{3,}", s)
    letter_ratio = sum(1 for c in s if c.isalpha()) / max(len(s), 1)
    if len(s) < 10 or len(words) < 3 or letter_ratio < 0.5:
        return None
    return s[:120]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0,
                    help="Max rows to process (0 = all)")
    ap.add_argument("--project", default=None,
                    help="Only this project (None = all)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would be summarized, no DB writes")
    args = ap.parse_args()

    conn = sqlite3.connect(DB_PATH)
    sql = ("SELECT id, project, content, evidence FROM findings "
           "WHERE (summary IS NULL OR summary = '') AND status = 'current'")
    params = []
    if args.project:
        sql += " AND project = ?"
        params.append(args.project)
    sql += " ORDER BY created_at DESC"
    if args.limit:
        sql += f" LIMIT {args.limit}"

    rows = conn.execute(sql, params).fetchall()
    print(f"Found {len(rows)} rows missing summary "
          f"(project={args.project or 'ALL'})", file=sys.stderr)
    if not rows:
        return 0

    t0 = time.time()
    ok = 0
    fail = 0
    err = None
    for i, (fid, project, content, evidence) in enumerate(rows, 1):
        summary = llm_summary(content, evidence)
        if summary and len(summary) >= 10:
            if args.dry_run:
                print(f"[DRY] {fid} ({project}): {summary}")
            else:
                conn.execute("UPDATE findings SET summary=?, updated_at=datetime('now') WHERE id=?",
                             (summary, fid))
                conn.commit()
            ok += 1
        else:
            fail += 1
            print(f"FAIL {fid} ({project}): err={err} content_head={content[:60]!r}",
                  file=sys.stderr)
        if i % 10 == 0 or i == len(rows):
            dt = time.time() - t0
            print(f"  {i}/{len(rows)}  ok={ok} fail={fail}  "
                  f"rate={i/dt:.2f}/s  elapsed={dt:.0f}s", file=sys.stderr)

    conn.close()
    print(f"DONE. ok={ok} fail={fail} total={len(rows)} "
          f"elapsed={time.time()-t0:.1f}s", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
