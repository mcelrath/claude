#!/usr/bin/env python3
"""E1: cosine top-10 fan-out per kb_query, LLM re-rank with full bodies, top-3 RELEVANT.

Compares against the cosine-top-3 baseline implicit in results_v2.jsonl.
Reuses kb_queries from results_v2.jsonl (apples-to-apples).
"""
import json, sys, re, time, pathlib, subprocess, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).parent
ENDPOINT = "http://tardis:9510/v1/chat/completions"
PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
KB_PROJECT = {"braidinfer": "braidinfer",
              "exterior-algebra": "exterior_algebra",
              "llama-cpp": "llama.cpp"}

ANSI = re.compile(r"\x1b\[[0-9;]*m")

SYSTEM = "You judge whether prior knowledge-base entries are RELEVANT to a coding agent's current activity. Output strict JSON only."

# --- cosine retrieval --------------------------------------------------------

KB_ID_RE = re.compile(r"(kb-\d{8}-\d{6}-[0-9a-f]+)")
SCORE_RE = re.compile(r"\(([01]\.\d{2})\)")

def kb_search_top10(query, project):
    """Returns list of {kb_id, score, position} ordered by cosine rank."""
    try:
        r = subprocess.run(
            ["kb", "search", query, "-p", project, "-n", "10"],
            capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired:
        return {"_err": "timeout"}
    out = ANSI.sub("", r.stdout)
    if "Connection refused" in out or "Connection refused" in r.stderr:
        return {"_err": "embedding-server-down"}
    if "No results" in out or not out.strip():
        return []
    hits = []
    pos = 0
    for chunk in out.split("\n\n"):
        head = chunk.strip().split("\n", 1)[0]
        mid = KB_ID_RE.search(head)
        if not mid:
            continue
        ms = SCORE_RE.search(head)
        score = float(ms.group(1)) if ms else 0.0
        hits.append({"kb_id": mid.group(1), "score": score, "position": pos})
        pos += 1
    return hits

def kb_get_body(kb_id):
    """Returns (title, body) or (None, None) on failure."""
    try:
        r = subprocess.run(["kb", "get", kb_id, "--raw"],
                           capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        return None, None
    if r.returncode != 0:
        return None, None
    text = r.stdout
    title, body = "", ""
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("**Summary:**"):
            title = s[len("**Summary:**"):].strip()
        elif s.startswith("### Content"):
            continue
    # Body = the paragraph after '### Content' header.
    parts = text.split("### Content", 1)
    if len(parts) == 2:
        tail = parts[1].strip()
        # Strip trailing **Tags:** and *Created* metadata
        cuts = []
        for marker in ("\n**Tags:**", "\n*Created:"):
            i = tail.find(marker)
            if i >= 0: cuts.append(i)
        if cuts:
            tail = tail[:min(cuts)].strip()
        body = tail
    return title or kb_id, body

def _loose_json(s):
    """Strip ```json fences, locate outermost {...}, tolerate trailing truncation."""
    s = (s or "").strip()
    if s.startswith("```"):
        s = s.split("\n", 1)[1] if "\n" in s else s[3:]
        if s.rstrip().endswith("```"):
            s = s.rsplit("```", 1)[0]
    i = s.find("{")
    if i < 0:
        return None
    s = s[i:]
    # Try as-is, then progressive close-brace recovery for truncation.
    try: return json.loads(s)
    except Exception: pass
    for n_close in range(1, 6):
        for n_brack in range(0, 4):
            cand = s.rstrip().rstrip(",") + ("]" * n_brack) + ("}" * n_close)
            try: return json.loads(cand)
            except Exception: pass
    # Last resort: find last valid object end by trimming.
    for end in range(len(s), 0, -1):
        try: return json.loads(s[:end])
        except Exception: continue
    return None

# --- LLM rerank --------------------------------------------------------------

def llm_rerank(activity, candidates, timeout=60):
    """candidates: list of dicts {kb_id, title, body}.

    Returns (parsed_json, dt, raw, err).
    """
    if not candidates:
        return None, 0.0, "", "no-candidates"
    cand_lines = []
    for i, c in enumerate(candidates):
        tag = chr(ord("A") + i)
        snippet = (c.get("body") or c.get("title") or "")[:600]
        cand_lines.append(f"[{tag}] {c['kb_id']}: {snippet}")
    user = (
        "Agent activity:\n" + activity[:800] +
        "\n\nCandidates:\n" + "\n\n".join(cand_lines) +
        "\n\nFor each candidate, return JSON "
        '{"results":[{"id":"A","verdict":"RELEVANT|TANGENT|UNRELATED","why":"<=15 words"}, ...]}. '
        "Only include items with verdict RELEVANT in your final picks; max 3 RELEVANT."
    )
    req = json.dumps({
        "model": "qwen3.6",
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": user}],
        "temperature": 0.0,
        "max_tokens": 900,
        "response_format": {"type": "json_object"},
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    r = urllib.request.Request(ENDPOINT, data=req,
                               headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(r, timeout=timeout) as fp:
            body = json.loads(fp.read())
    except Exception as e:
        return None, time.time() - t0, "", str(e)
    dt = time.time() - t0
    content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
    parsed = _loose_json(content)
    if parsed is None:
        return None, dt, content, "parse"
    return parsed, dt, content, None

# --- activity reconstruction (mirrors run_v2) --------------------------------

def read_head(fp, n=30):
    try:
        with open(fp) as f:
            return "\n".join(line.rstrip() for i, line in enumerate(f) if i < n)
    except Exception:
        return ""

def fmt_edit(fp, ns): return f"[EDIT] {fp}\n--- new content (truncated) ---\n{ns[:1200]}"
def fmt_read(fp):
    h = read_head(fp, 30)
    return f"[READ] {fp}\n--- first 30 lines ---\n{h[:1200]}" if h else f"[READ] {fp}"
def fmt_text(t): return f"[ASSISTANT OUTPUT]\n{t[:1500]}"

def build_samples():
    """Returns list of (label, project, activity, kb_queries_from_v2)."""
    v2 = {}
    for line in (HERE / "results_v2.jsonl").read_text().splitlines():
        r = json.loads(line)
        parsed = (r.get("llm") or {}).get("parsed") or {}
        v2[r["label"]] = parsed.get("kb_queries", []) if isinstance(parsed, dict) else []
    samples_out = []
    for proj in PROJECTS:
        s = json.loads((HERE / f"samples-{proj}.json").read_text())
        for i, t in enumerate(s["assistant_texts"][:2]):
            samples_out.append((f"{proj}/text/{i}", proj, fmt_text(t)))
        for i, (fp, ns) in enumerate(s["edits"][:2]):
            samples_out.append((f"{proj}/edit/{i}", proj, fmt_edit(fp, ns)))
        for i, fp in enumerate(s["reads"][:2]):
            samples_out.append((f"{proj}/read/{i}", proj, fmt_read(fp)))
    return [(lbl, proj, act, v2.get(lbl, [])) for lbl, proj, act in samples_out]

# --- per-sample pipeline -----------------------------------------------------

def process(label, project, activity, queries, ex):
    kb_proj = KB_PROJECT[project]
    if not queries:
        return {"label": label, "_skip": "no-queries-in-v2"}
    # Fan out cosine top-10 in parallel (kb is i/o bound on embedding server).
    fut = {q: ex.submit(kb_search_top10, q, kb_proj) for q in queries[:4]}
    pool = {}        # kb_id -> {score, position, query}
    cosine_top3_per_q = {}
    for q, f in fut.items():
        hits = f.result()
        if isinstance(hits, dict) and hits.get("_err"):
            cosine_top3_per_q[q] = {"_err": hits["_err"]}
            continue
        cosine_top3_per_q[q] = [h["kb_id"] for h in hits[:3]]
        for h in hits:
            cur = pool.get(h["kb_id"])
            if cur is None or h["score"] > cur["score"]:
                pool[h["kb_id"]] = {"kb_id": h["kb_id"], "score": h["score"],
                                    "position": h["position"], "query": q}
    if not pool:
        return {"label": label, "_skip": "no-cosine-hits",
                "queries": queries, "cosine_per_query": cosine_top3_per_q}
    # Order pool by best (score, -position) and cap at 15.
    ranked = sorted(pool.values(), key=lambda x: (-x["score"], x["position"]))[:15]
    # Fetch bodies in parallel.
    bodies = list(ex.map(kb_get_body, [r["kb_id"] for r in ranked]))
    candidates = []
    for r, (title, body) in zip(ranked, bodies):
        if title is None:
            continue
        candidates.append({"kb_id": r["kb_id"], "title": title, "body": body,
                           "cosine_score": r["score"],
                           "position_in_cosine": r["position"],
                           "query": r["query"]})
    if not candidates:
        return {"label": label, "_skip": "all-kb-get-failed",
                "queries": queries, "cosine_per_query": cosine_top3_per_q}
    parsed, dt, raw, err = llm_rerank(activity, candidates)
    # Pooled cosine-top-3 (highest-score-first across all queries) for comparison.
    pooled_top3 = [c["kb_id"] for c in candidates[:3]]
    rec = {
        "label": label,
        "project": project,
        "n_queries": len(queries[:4]),
        "n_candidates": len(candidates),
        "llm_t": round(dt, 2),
        "cosine_top3_pooled": pooled_top3,
        "cosine_top3_per_query": cosine_top3_per_q,
    }
    if err:
        rec["_skip"] = f"llm-err:{err}"
        rec["llm_raw"] = raw[:500]
        return rec
    # Map id letter -> kb_id
    letter_map = {chr(ord("A") + i): c for i, c in enumerate(candidates)}
    picks = []
    for r in (parsed.get("results") or [])[:15]:
        if r.get("verdict") != "RELEVANT":
            continue
        c = letter_map.get(r.get("id"))
        if not c:
            continue
        picks.append({
            "kb_id": c["kb_id"],
            "why": r.get("why", "")[:120],
            "cosine_score": c["cosine_score"],
            "position_in_cosine": c["position_in_cosine"],
            "query": c["query"],
        })
        if len(picks) >= 3:
            break
    rec["picked"] = picks
    rec["llm_rejected_all_cosine_top3"] = not any(
        p["kb_id"] in pooled_top3 for p in picks)
    return rec

def main():
    out = (HERE / "results_e1.jsonl").open("w")
    summary_rows = []
    samples = build_samples()
    with ThreadPoolExecutor(max_workers=4) as ex:
        for lbl, proj, act, qs in samples:
            t0 = time.time()
            rec = process(lbl, proj, act, qs, ex)
            out.write(json.dumps(rec) + "\n"); out.flush()
            picks = rec.get("picked", [])
            cos3 = rec.get("cosine_top3_pooled", [])
            new = sum(1 for p in picks if p["kb_id"] not in cos3)
            rej = sum(1 for k in cos3 if not any(p["kb_id"] == k for p in picks))
            summary_rows.append({
                "label": lbl,
                "n_cand": rec.get("n_candidates", 0),
                "n_picked": len(picks),
                "llm_t": rec.get("llm_t", 0.0),
                "new_vs_cos3": new,
                "rej_from_cos3": rej,
                "skip": rec.get("_skip", ""),
            })
            print(f"{lbl}: n={rec.get('n_candidates',0)} picked={len(picks)} "
                  f"new={new} rej={rej} t={time.time()-t0:.1f}s "
                  f"skip={rec.get('_skip','')}", file=sys.stderr)
    out.close()
    write_summary(summary_rows)

def write_summary(rows):
    median_t = sorted(r["llm_t"] for r in rows if r["llm_t"])[len(rows)//2] if rows else 0.0
    total_new = sum(r["new_vs_cos3"] for r in rows)
    total_picked = sum(r["n_picked"] for r in rows)
    all_rejected = sum(1 for r in rows
                       if r["n_picked"] > 0 and r["new_vs_cos3"] == r["n_picked"])
    lines = [
        "# E1 results: cosine top-10 -> LLM re-rank",
        "",
        f"Samples: {len(rows)}",
        f"Median LLM re-rank time: {median_t:.2f}s",
        f"Total picks: {total_picked}  |  New (not in cosine top-3): {total_new}",
        f"Samples where LLM picked NOTHING from cosine top-3: {all_rejected}",
        "",
        "## Per-sample table",
        "",
        "label                          n_cand  n_pick  llm_t  new  rej  skip",
        "-" * 78,
    ]
    for r in rows:
        lines.append(f"{r['label']:<30} {r['n_cand']:>6}  {r['n_picked']:>6}  "
                     f"{r['llm_t']:>5.2f}  {r['new_vs_cos3']:>3}  "
                     f"{r['rej_from_cos3']:>3}  {r['skip']}")
    lines.append("")
    lines.append("Columns:")
    lines.append("  n_cand = pooled cosine candidates fed to LLM (dedup, cap 15)")
    lines.append("  n_pick = RELEVANT verdicts in LLM output (cap 3)")
    lines.append("  new    = picks NOT present in pooled cosine top-3")
    lines.append("  rej    = pooled cosine top-3 entries the LLM did NOT pick")
    (HERE / "e1_summary.md").write_text("\n".join(lines))

if __name__ == "__main__":
    main()
