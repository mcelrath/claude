#!/usr/bin/env python3
"""E2: corpus probe - does cosine kb-search top-10 surface known-related pairs?

Mining strategy: for each project (braidinfer, exterior_algebra, llama.cpp),
list entries; for each entry, get full body and scan for `kb-YYYYMMDD-HHMMSS-hex`
references. Pair (referring -> referenced) is a gold-standard related pair.

Then for 5 such pairs (A, B) in the same project:
  - Query kb search with A's title, project-filtered, n=10.
  - Position of B in results (or -1).
  - If not found, try alt queries (distinctive phrases / symbols from A's body).
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

KB = os.path.expanduser("~/.local/bin/kb")
OUT_DIR = Path(os.path.expanduser("~/Projects/ai/claude/tmp/auto-research"))
PROJECTS = ["braidinfer", "exterior_algebra", "llama.cpp"]
ANSI = re.compile(r"\x1b\[[0-9;]*m")
KB_ID_RE = re.compile(r"kb-\d{8}-\d{6}-[a-f0-9]+")
ENTRY_LINE_RE = re.compile(
    r"\[(?:DISCOVERY|EXPERIMENT|SUCCESS|FAILURE|CORRECTION)\]\s+(kb-\d{8}-\d{6}-[a-f0-9]+)\s+\(([^)]+)\)"
)


def run(cmd, retries=1):
    for attempt in range(retries + 1):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            return r.stdout, r.stderr, r.returncode
        except subprocess.TimeoutExpired:
            if attempt < retries:
                time.sleep(5)
                continue
            return "", "TIMEOUT", -1


def strip_ansi(s):
    return ANSI.sub("", s)


def list_project(project, n=200):
    out, _, _ = run([KB, "list", "-p", project, "-n", str(n)])
    out = strip_ansi(out)
    ids = []
    for line in out.splitlines():
        m = ENTRY_LINE_RE.search(line)
        if m:
            ids.append((m.group(1), m.group(2)))
    return ids


def get_entry(kb_id):
    out, err, rc = run([KB, "get", kb_id, "--raw"])
    if rc != 0:
        return None
    out = strip_ansi(out)
    # Real title lives in "**Summary:** ## <title>" or first ### Content heading line.
    title = None
    m = re.search(r"\*\*Summary:\*\*\s*#*\s*(.+)", out)
    if m:
        title = m.group(1).strip()[:160]
    if not title:
        # Fallback: first markdown H1/H2 line after "### Content"
        in_content = False
        for ln in out.splitlines():
            if "### Content" in ln:
                in_content = True
                continue
            if in_content and ln.strip().startswith("#"):
                title = ln.strip().lstrip("# ").strip()[:160]
                break
    if not title:
        # Last fallback: first non-meta, non-header content line
        for ln in out.splitlines():
            s = ln.strip()
            if not s or s.startswith("#") or s.startswith("**") or s.startswith("---"):
                continue
            title = s[:160]
            break
    return {"id": kb_id, "title": title or kb_id, "body": out}


def mine_pairs(projects):
    """Return list of (referring_id, referenced_id, project) tuples."""
    pairs = []
    for proj in projects:
        print(f"[mine] listing {proj}", file=sys.stderr)
        entries = list_project(proj, n=200)
        ids_in_proj = {e[0] for e in entries}
        for kid, _ in entries:
            ent = get_entry(kid)
            if not ent:
                continue
            refs = set(KB_ID_RE.findall(ent["body"]))
            refs.discard(kid)
            for ref in refs:
                if ref in ids_in_proj:
                    pairs.append((kid, ref, proj))
    return pairs


def kb_search(query, project, n=10):
    out, err, rc = run([KB, "search", query, "-p", project, "-n", str(n)], retries=1)
    if rc != 0 and "Connection refused" in err:
        return None, "kb-down"
    if rc != 0:
        return None, err.strip()[:200]
    out = strip_ansi(out)
    ids = []
    for line in out.splitlines():
        m = ENTRY_LINE_RE.search(line)
        if m:
            ids.append(m.group(1))
    return ids, None


def position_of(target, results):
    if results is None:
        return -1
    try:
        return results.index(target) + 1  # 1-indexed
    except ValueError:
        return -1


# Hand-curated alt queries per A id, crafted from reading A's body for the
# distinctive content that points at B (per-pair, not generic).
MANUAL_ALT_QUERIES = {
    "kb-20260325-172118-4af24f": [
        "Pre-RoPE K quantization 4-bit residual_pc PPL",
        "residual_pc lossless K cache Qwen3",
        "per_token K quantization catastrophic QK-norm",
    ],
    "kb-20260530-233610-08705d": [
        "MES SCH PASID slot leak cold-start",
        "mode1_reset MES microcontroller reset",
        "amdgpu page fault WALKER_ERROR pasid:0",
    ],
    "kb-20260324-131543-ce20a5": [
        "row_expert expert split mode decode slower",
        "SP Flash Attention KV replication P2P",
        "Expert_TP tensor parallel attention broken",
    ],
    "kb-20260325-090425-b99cca": [
        "Q cache staleness residual_pc per_channel 8-bit",
        "KIVI PolarQuant K V cache quantization",
        "argmax flip rate staleness scoring",
    ],
    "kb-20260530-231850-d60d42": [
        "MES v0x88 IB-fence elision queue scheduler",
        "GFX1100 wedge class taxonomy recovery",
        "SDMA F32 107-page host-read cap",
    ],
}


def distinctive_phrases(body, max_phrases=3):
    """Heuristic alt-query generator from A's body.
    Pick: (1) first ALL-CAPS multi-word phrase, (2) function/identifier-looking tokens,
    (3) longest distinctive noun phrase from first 500 chars.
    """
    body_clean = strip_ansi(body)
    candidates = []
    # CamelCase / snake_case identifiers >= 8 chars
    idents = re.findall(r"\b[A-Za-z_][A-Za-z0-9_]{7,}\b", body_clean)
    seen = set()
    for i in idents:
        low = i.lower()
        if low in seen:
            continue
        if i.lower() in {"discovery", "experiment", "evidence", "findings", "kb-"}:
            continue
        seen.add(low)
        candidates.append(i)
        if len(candidates) >= 6:
            break
    # Quoted strings
    quoted = re.findall(r'"([^"\n]{6,60})"', body_clean) + re.findall(r"`([^`\n]{6,60})`", body_clean)
    for q in quoted[:3]:
        if q not in candidates:
            candidates.append(q)
    # First sentence of body (after title)
    lines = [l.strip() for l in body_clean.splitlines() if l.strip() and not l.strip().startswith("#")]
    if len(lines) >= 2:
        first_sent = re.split(r"[.!?]", lines[1])[0][:120].strip()
        if first_sent and len(first_sent.split()) >= 3:
            candidates.append(first_sent)
    # Dedup, keep top max_phrases
    out = []
    seen2 = set()
    for c in candidates:
        cl = c.lower()
        if cl in seen2:
            continue
        seen2.add(cl)
        out.append(c)
        if len(out) >= max_phrases:
            break
    return out


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("[e2] mining pairs", file=sys.stderr)
    pairs = mine_pairs(PROJECTS)
    print(f"[e2] mined {len(pairs)} candidate pairs", file=sys.stderr)
    # Pick 5 diverse, spanning >=2 projects
    by_proj = {}
    for p in pairs:
        by_proj.setdefault(p[2], []).append(p)
    selected = []
    # Round-robin across projects
    projs_with_pairs = [p for p in PROJECTS if by_proj.get(p)]
    if not projs_with_pairs:
        print("[e2] no pairs mined; aborting", file=sys.stderr)
        return 1
    idx = 0
    used_referring = set()
    while len(selected) < 5 and any(by_proj.get(p) for p in projs_with_pairs):
        proj = projs_with_pairs[idx % len(projs_with_pairs)]
        bucket = by_proj.get(proj, [])
        picked = None
        for cand in bucket:
            if cand[0] not in used_referring:
                picked = cand
                break
        if picked:
            selected.append(picked)
            used_referring.add(picked[0])
            bucket.remove(picked)
        idx += 1
        if idx > 100:
            break
    print(f"[e2] selected {len(selected)} pairs", file=sys.stderr)

    results_path = OUT_DIR / "results_e2.jsonl"
    summary_path = OUT_DIR / "e2_summary.md"
    kb_down = False
    rows = []
    with results_path.open("w") as f:
        for a_id, b_id, proj in selected:
            ent_a = get_entry(a_id)
            ent_b = get_entry(b_id)
            if not ent_a or not ent_b:
                rec = {"_err": "missing-entry", "A_id": a_id, "B_id": b_id}
                f.write(json.dumps(rec) + "\n")
                continue
            print(f"[e2] pair A={a_id} B={b_id} proj={proj}", file=sys.stderr)
            results, err = kb_search(ent_a["title"], proj, n=10)
            if err == "kb-down":
                kb_down = True
                rec = {"_err": "kb-down", "A_id": a_id, "B_id": b_id}
                f.write(json.dumps(rec) + "\n")
                continue
            pos = position_of(b_id, results)
            alt_results = []
            if pos == -1:
                phrases = list(MANUAL_ALT_QUERIES.get(a_id, []))
                # Backfill with auto-generated if no manual set
                if not phrases:
                    phrases = distinctive_phrases(ent_a["body"])
                for q in phrases:
                    r2, err2 = kb_search(q, proj, n=10)
                    if err2 == "kb-down":
                        kb_down = True
                        break
                    p2 = position_of(b_id, r2)
                    alt_results.append({"q": q, "B_position": p2})
            rec = {
                "A": {"id": a_id, "title": ent_a["title"], "project": proj},
                "B": {"id": b_id, "title": ent_b["title"]},
                "B_in_topk_for_A_title": pos,
                "alt_queries": alt_results,
            }
            f.write(json.dumps(rec) + "\n")
            rows.append(rec)

    # Summary
    with summary_path.open("w") as f:
        f.write("# E2 corpus probe — cosine recall for known-related pairs\n\n")
        if kb_down:
            f.write("NOTE: kb embedding server (ash:8081) returned Connection refused on at least one query. Affected rows marked `_err: kb-down`.\n\n")
        f.write(f"Pairs tested: {len(rows)}\n\n")
        hits = sum(1 for r in rows if r.get("B_in_topk_for_A_title", -1) > 0)
        f.write(f"B in top-10 of A's title query: {hits}/{len(rows)}\n\n")
        f.write("| pair | proj | A title (truncated) | B title (truncated) | pos(title) | best alt | best alt pos |\n")
        f.write("|------|------|---------------------|---------------------|------------|----------|--------------|\n")
        for i, r in enumerate(rows, 1):
            at = r["A"]["title"][:50].replace("|", "/")
            bt = r["B"]["title"][:50].replace("|", "/")
            pos = r["B_in_topk_for_A_title"]
            best_alt = "-"
            best_alt_pos = "-"
            for alt in r.get("alt_queries", []):
                if alt["B_position"] > 0 and (best_alt_pos == "-" or alt["B_position"] < best_alt_pos):
                    best_alt = alt["q"][:40].replace("|", "/")
                    best_alt_pos = alt["B_position"]
            f.write(f"| {i} | {r['A']['project']} | {at} | {bt} | {pos} | {best_alt} | {best_alt_pos} |\n")
    print(f"[e2] wrote {results_path} and {summary_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
