#!/usr/bin/env python3
"""E6: session-topic drift.

Distill the per-fire topic strings (one per sample in results_v2.jsonl) for a
project into a single META-TOPIC + 3 conceptual search queries via ONE LLM call.
Run kb search per query. Compare hits to the UNION of per-fire kb hits across
results_v2.jsonl + results_e1.jsonl. Surface kb_ids that ONLY appear via the
meta-topic — these are the drift-level candidates.

3 LLM calls total (one per project).
"""
import json, pathlib, time, urllib.request, subprocess, re, sys

HERE = pathlib.Path(__file__).parent
ENDPOINT = "http://tardis:9510/v1/chat/completions"
PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
KB_PROJECT = {
    "braidinfer": "braidinfer",
    "exterior-algebra": "exterior_algebra",
    "llama-cpp": "llama.cpp",
}

SYSTEM = (
    "Given a list of one-line topic strings from an agent's recent activity, "
    "distill the META-TOPIC the agent is actually working on and produce 3 "
    "conceptual search queries for that meta-topic. Output strict JSON."
)

def llm(user_msg: str, timeout: int = 60) -> dict:
    req = json.dumps({
        "model": "qwen3.6",
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_msg},
        ],
        "temperature": 0.0,
        "max_tokens": 300,
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
        return {"_err": str(e), "_t": round(time.time() - t0, 2)}
    dt = round(time.time() - t0, 2)
    content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
    try:
        parsed = json.loads(content)
    except Exception as e:
        parsed = {"_err": str(e)}
    return {"raw": content, "parsed": parsed, "t": dt,
            "finish": body.get("choices", [{}])[0].get("finish_reason")}

KB_ID_RE = re.compile(r"kb-\d{8}-\d{6}-[0-9a-f]+")

def kb_search(query: str, project: str):
    """Return list of {kb_id, score} parsed from `kb search` output."""
    try:
        r = subprocess.run(["kb", "search", query, "-p", project, "-n", "5"],
                           capture_output=True, text=True, timeout=30)
        out = r.stdout
        if "Connection refused" in out + r.stderr:
            return {"_err": "embedding-server-down"}
        hits = []
        # Each result block starts with a head line containing kb-id and score.
        # Format example: "[DISCOVERY] kb-2026... (proj) (0.50)"
        for line in out.splitlines():
            m = KB_ID_RE.search(line)
            if not m:
                continue
            kbid = m.group(0)
            sm = re.search(r"\((\d\.\d{2})\)", line)
            score = float(sm.group(1)) if sm else None
            # dedupe (kb search may repeat ids if multiple chunks)
            if any(h["kb_id"] == kbid for h in hits):
                continue
            hits.append({"kb_id": kbid, "score": score})
        return hits
    except Exception as e:
        return {"_err": str(e)}

def load_jsonl(path: pathlib.Path):
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()]

def per_fire_kb_ids(proj: str, v2_rows, e1_rows):
    """Union of kb_ids that appeared in per-fire kb searches for this project."""
    ids = set()
    prefix = proj + "/"
    # v2: rec["kb_hits"][query] = list of {head, body}; kb-id embedded in head
    for rec in v2_rows:
        if not rec.get("label", "").startswith(prefix):
            continue
        for q, hits in (rec.get("kb_hits") or {}).items():
            if isinstance(hits, dict):
                continue
            for h in hits:
                m = KB_ID_RE.search(h.get("head", "") or "")
                if m:
                    ids.add(m.group(0))
    # e1: cosine_top3_pooled, cosine_top3_per_query, picked
    for rec in e1_rows:
        if rec.get("project") != proj:
            continue
        for kid in rec.get("cosine_top3_pooled") or []:
            ids.add(kid)
        for q, lst in (rec.get("cosine_top3_per_query") or {}).items():
            for kid in lst:
                ids.add(kid)
        for p in rec.get("picked") or []:
            if p.get("kb_id"):
                ids.add(p["kb_id"])
    return ids

def main():
    v2_rows = load_jsonl(HERE / "results_v2.jsonl")
    e1_rows = load_jsonl(HERE / "results_e1.jsonl")
    out_rows = []
    summary = ["# E6 results: meta-topic drift surfacing",
               "",
               "One LLM call per project distills 6 per-fire topics into a meta-topic + 3 queries.",
               "kb-ids found via meta-queries are compared against the union of per-fire kb-ids",
               "(results_v2.jsonl kb_hits + results_e1.jsonl cosine/picked).",
               "",
               "| project | meta_topic | meta_hits | new_vs_per_fire |",
               "|---|---|---|---|"]
    for proj in PROJECTS:
        prefix = proj + "/"
        topics = []
        for rec in v2_rows:
            if not rec.get("label", "").startswith(prefix):
                continue
            t = ((rec.get("llm") or {}).get("parsed") or {}).get("topic")
            if t:
                topics.append(t)
        topics = topics[:6]
        user = ("Recent topics:\n" + "\n".join(f"- {t}" for t in topics) +
                '\nWhat is the agent ACTUALLY working on? Output JSON '
                '{"meta_topic":"...", "queries":["...","...","..."]}.')
        res = llm(user)
        parsed = res.get("parsed") or {}
        meta_topic = parsed.get("meta_topic", "")
        queries = parsed.get("queries", []) or []
        kb_proj = KB_PROJECT[proj]
        meta_hits_per_query = {}
        meta_hit_ids = set()
        for q in queries[:3]:
            hits = kb_search(q, kb_proj)
            meta_hits_per_query[q] = hits
            if isinstance(hits, list):
                for h in hits:
                    meta_hit_ids.add(h["kb_id"])
        per_fire_ids = per_fire_kb_ids(proj, v2_rows, e1_rows)
        new_ids = sorted(meta_hit_ids - per_fire_ids)
        # Flatten meta_hits for jsonl output
        meta_hits_flat = []
        for q, hits in meta_hits_per_query.items():
            if isinstance(hits, list):
                for h in hits:
                    meta_hits_flat.append({"query": q, **h})
        rec = {
            "project": proj,
            "topics": topics,
            "meta_topic": meta_topic,
            "queries": queries,
            "llm_t": res.get("t"),
            "llm_err": res.get("_err"),
            "meta_hits": meta_hits_flat,
            "per_fire_kb_ids_count": len(per_fire_ids),
            "new_vs_per_fire": new_ids,
        }
        out_rows.append(rec)
        summary.append(
            f"| {proj} | {meta_topic[:80]} | {len(meta_hit_ids)} | {len(new_ids)} |"
        )
        print(f"{proj}: meta_topic={meta_topic!r} hits={len(meta_hit_ids)} "
              f"new={len(new_ids)} llm_t={res.get('t')}s",
              file=sys.stderr)

    with (HERE / "results_e6.jsonl").open("w") as f:
        for r in out_rows:
            f.write(json.dumps(r) + "\n")
    # qualitative section
    summary += ["", "## Qualitative: are new meta-topic entries drift-level?", ""]
    for rec in out_rows:
        summary.append(f"### {rec['project']}")
        summary.append(f"- meta_topic: {rec['meta_topic']}")
        summary.append(f"- queries: {rec['queries']}")
        summary.append(f"- per-fire ids surfaced (union v2+e1): {rec['per_fire_kb_ids_count']}")
        summary.append(f"- meta-only kb-ids ({len(rec['new_vs_per_fire'])}): "
                       + ", ".join(rec["new_vs_per_fire"]) if rec["new_vs_per_fire"]
                       else "- meta-only kb-ids: (none)")
        summary.append("")
    (HERE / "e6_summary.md").write_text("\n".join(summary))
    print(f"E6 done: {len(out_rows)} projects", file=sys.stderr)

if __name__ == "__main__":
    main()
