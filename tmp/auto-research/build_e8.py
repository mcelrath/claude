#!/usr/bin/env python3
"""Build E8 bake-off markdown + jsonl from existing experiment outputs."""
import json, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).parent
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
KBID = re.compile(r"kb-\d{8}-\d{6}-[a-f0-9]+")

PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
LABELS = []
for p in PROJECTS:
    for kind in ("text", "edit", "read"):
        for i in (0, 1):
            LABELS.append(f"{p}/{kind}/{i}")

def strip_ansi(s): return ANSI.sub("", s or "")

_title_cache = {}
def kb_title(kb_id):
    if kb_id in _title_cache: return _title_cache[kb_id]
    try:
        r = subprocess.run(["kb", "get", kb_id], capture_output=True, text=True, timeout=10)
        out = strip_ansi(r.stdout)
        t = ""
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("Summary:"):
                t = line[len("Summary:"):].strip()
                break
        if not t:
            for line in out.splitlines():
                line = line.strip()
                if line and not line.startswith("[") and not line.startswith("Project:") and not line.startswith("Content") and line != "...":
                    t = line; break
    except Exception as e:
        t = f"<kb get failed: {e}>"
    _title_cache[kb_id] = t
    return t

# Load all inputs
def load_jsonl(name):
    out = {}
    for line in (HERE / name).read_text().splitlines():
        if not line.strip(): continue
        o = json.loads(line)
        out[o.get("label") or o.get("project")] = o
    return out

v2 = load_jsonl("results_v2.jsonl")
e1 = load_jsonl("results_e1.jsonl")
e3 = load_jsonl("results_e3_relaxed32k.jsonl")
e4 = load_jsonl("results_e4.jsonl")
e5 = load_jsonl("results_e5.jsonl")
e6 = load_jsonl("results_e6.jsonl")
e7 = load_jsonl("results_e7.jsonl")

# samples
samples = {}
for p in PROJECTS:
    samples[p] = json.loads((HERE / f"samples-{p}.json").read_text())

def get_input_snippet(label):
    proj, kind, idx = label.split("/")
    idx = int(idx)
    s = samples[proj]
    if kind == "text":
        return s["assistant_texts"][idx][:200]
    if kind == "edit":
        fp, ns = s["edits"][idx]
        return f"[EDIT {fp}] " + ns[:180]
    if kind == "read":
        fp = s["reads"][idx]
        return f"[READ {fp}]"
    return ""

def b0_top3(label):
    """Pooled cosine top-3 from results_v2 kb_hits (dedup, in pool order)."""
    rec = v2.get(label) or {}
    hits = rec.get("kb_hits") or {}
    seen = []
    for q, lst in hits.items():
        for h in lst:
            head = strip_ansi(h.get("head", ""))
            m = KBID.search(head)
            if not m: continue
            kid = m.group(0)
            if kid in seen: continue
            seen.append(kid)
            if len(seen) >= 3: return seen, hits
    return seen, hits

def b1_top3(label):
    rec = e1.get(label) or {}
    return rec.get("picked") or []

def b3_top3(label):
    rec = e3.get(label) or {}
    if rec.get("_skip"):
        return None, rec["_skip"]
    return rec.get("picks") or [], None

def b4_top3(label):
    rec = e4.get(label) or {}
    return rec.get("kb_picks") or [], rec.get("identifiers") or []

def b5_top3(label):
    rec = e5.get(label) or {}
    return rec.get("bd_picks") or []

def b7_top3(label):
    """Pooled top-3 hits across adversarial queries, in appearance order, dedup."""
    rec = e7.get(label) or {}
    seen = {}
    order = []
    for r in rec.get("results", []):
        for h in r.get("hits", []):
            kid = h.get("kb_id")
            if not kid or kid in seen: continue
            seen[kid] = h
            order.append(kid)
            if len(order) >= 3: break
        if len(order) >= 3: break
    return [seen[k] for k in order]

# Build per-sample data + markdown
md = ["# E8 Bake-off (user-scoring table)",
      "",
      "For each of 18 samples, side-by-side top picks from each baseline.",
      "Score each cell as RELEVANT (R) / TANGENT (T) / NOISE (N) inline. Replace each cell's `_` with R/T/N.",
      "",
      "## Per-sample table",
      ""]

data_lines = []
fill = {b: 0 for b in ("B0","B1","B3","B4","B5","B7")}

def topic_of(label):
    rec = v2.get(label) or {}
    parsed = ((rec.get("llm") or {}).get("parsed")) or {}
    t = parsed.get("topic")
    if t: return t
    # fall back to e7 topic
    return (e7.get(label) or {}).get("topic") or ""

skip_labels = set()

for label in LABELS:
    md.append(f"### {label}")
    topic = topic_of(label)
    md.append(f"Activity: {topic}")
    snippet = get_input_snippet(label).replace("\n", " ")
    md.append(f"Input snippet: {snippet}")
    md.append("")

    sample_data = {"label": label, "topic": topic, "input_snippet": snippet}

    # Skip detection: no v2 kb_queries
    v2rec = v2.get(label) or {}
    v2_parsed = ((v2rec.get("llm") or {}).get("parsed")) or {}
    if not v2_parsed.get("kb_queries"):
        md.append("**skip: no v2 queries**")
        md.append("")
        sample_data["skip"] = "no v2 queries"
        data_lines.append(json.dumps(sample_data))
        skip_labels.add(label)
        continue

    md.append("|     | id | title/why | score |")
    md.append("|---|---|---|---|")

    # B0
    b0_ids, _ = b0_top3(label)
    sample_data["B0"] = b0_ids
    for i in range(3):
        if i < len(b0_ids):
            kid = b0_ids[i]
            md.append(f"| B0 cos top-3 #{i+1} | {kid} | {kb_title(kid)} | _ |")
        else:
            md.append(f"| B0 cos top-3 #{i+1} | — | (no hit) | _ |")
    if b0_ids: fill["B0"] += 1

    # B1
    picked = b1_top3(label)
    sample_data["B1"] = picked
    for i in range(3):
        if i < len(picked):
            p = picked[i]
            why = (p.get("why") or "").replace("|", "\\|")
            md.append(f"| B1 LLM rerank #{i+1} | {p['kb_id']} | {why} | _ |")
        else:
            md.append(f"| B1 LLM rerank #{i+1} | — | (no pick) | _ |")
    if picked: fill["B1"] += 1

    # B3
    b3_picks, b3_skip = b3_top3(label)
    sample_data["B3"] = {"skip": b3_skip, "picks": b3_picks if b3_picks else []}
    if b3_skip:
        for i in range(3):
            md.append(f"| B3 whole-file #{i+1} | — | n/a ({b3_skip}) | _ |")
    else:
        for i in range(3):
            if i < len(b3_picks):
                p = b3_picks[i]
                why = (p.get("why") or "").replace("|", "\\|")
                md.append(f"| B3 whole-file #{i+1} | {p['kb_id']} | {why} | _ |")
            else:
                md.append(f"| B3 whole-file #{i+1} | — | (no pick) | _ |")
        if b3_picks: fill["B3"] += 1

    # B4
    kb_picks, idents = b4_top3(label)
    sample_data["B4"] = {"identifiers": idents, "kb_picks": kb_picks}
    for i in range(3):
        if i < len(kb_picks):
            p = kb_picks[i]
            mi = ", ".join(p.get("matched_idents", []))
            title = kb_title(p["kb_id"]).replace("|", "\\|")
            md.append(f"| B4 symbol #{i+1} | {p['kb_id']} | {title} matched=[{mi}] | _ |")
        else:
            md.append(f"| B4 symbol #{i+1} | — | (no pick; idents={idents}) | _ |")
    if kb_picks: fill["B4"] += 1

    # B5
    bd_picks = b5_top3(label)
    sample_data["B5"] = bd_picks
    for i in range(3):
        if i < len(bd_picks):
            p = bd_picks[i]
            mi = ", ".join(p.get("matched", []))
            title = (p.get("title") or "").replace("|", "\\|")
            md.append(f"| B5 beads #{i+1} | {p['id']} | {title} matched=[{mi}] | _ |")
        else:
            md.append(f"| B5 beads #{i+1} | — | (no pick) | _ |")
    if bd_picks: fill["B5"] += 1

    # B7
    adv = b7_top3(label)
    sample_data["B7"] = adv
    for i in range(3):
        if i < len(adv):
            h = adv[i]
            sn = (h.get("snippet") or "").replace("|", "\\|").replace("\n", " ")[:120]
            md.append(f"| B7 adversarial #{i+1} | {h['kb_id']} | {sn} | _ |")
        else:
            md.append(f"| B7 adversarial #{i+1} | — | (no hit) | _ |")
    if adv: fill["B7"] += 1

    md.append("")
    data_lines.append(json.dumps(sample_data))

# Per-project meta (B6)
md.append("## Per-project meta (B6)")
md.append("")
md.append("| project | meta_topic | meta-only kb_ids | score |")
md.append("|---|---|---|---|")
for p in PROJECTS:
    rec = e6.get(p) or {}
    mt = (rec.get("meta_topic") or "").replace("|", "\\|")
    new_ids = rec.get("new_vs_per_fire") or []
    if not new_ids:
        ids_str = "(0 — meta collapsed onto per-fire)"
    else:
        ids_str = ", ".join(new_ids)
    md.append(f"| {p} | {mt} | {ids_str} | _ |")
md.append("")

md += ["## Tally (to be filled after user scoring)",
       "",
       "| baseline | R | T | N | total | precision = R/(R+T+N) |",
       "|---|---|---|---|---|---|",
       "| B0 | _ | _ | _ | _ | _ |",
       "| B1 | _ | _ | _ | _ | _ |",
       "| B3 | _ | _ | _ | _ | _ |",
       "| B4 | _ | _ | _ | _ | _ |",
       "| B5 | _ | _ | _ | _ | _ |",
       "| B6 | _ | _ | _ | _ | _ |",
       "| B7 | _ | _ | _ | _ | _ |",
       "",
       "## Gate for E9",
       "",
       "Plan requires >=70% precision on winner baseline. Lowest cell in the",
       "Precision column wins/blocks E9.",
       ""]

(HERE / "e8_bakeoff.md").write_text("\n".join(md))
(HERE / "e8_data.jsonl").write_text("\n".join(data_lines) + "\n")

# Print fill summary for caller
summary = {"fill_counts_out_of_18": fill, "skipped": sorted(skip_labels)}
sys.stdout.write(json.dumps(summary, indent=2) + "\n")
