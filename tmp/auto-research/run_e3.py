#!/usr/bin/env python3
"""E3: whole-file ingestion + recent kb TITLES only -> LLM picks 0-3 relevant.

For each Read event whose file exists and is <8KB:
  - LLM sees full file + ~50 recent kb titles for that project
  - returns {"picks":[{"id":"A","why":"<=12 words"}, ...]} <=3
  - we then kb-get the picked bodies to verify
"""
import json, sys, re, time, pathlib, subprocess, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).parent
ENDPOINT = "http://tardis:9510/v1/chat/completions"
PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
KB_PROJECT = {"braidinfer": "braidinfer",
              "exterior-algebra": "exterior_algebra",
              "llama-cpp": "llama.cpp"}
import os
FILE_MAX = int(os.environ.get("E3_FILE_MAX", 8 * 1024))
N_TITLES = 50

ANSI = re.compile(r"\x1b\[[0-9;]*m")
KB_ID_RE = re.compile(r"(kb-\d{8}-\d{6}-[0-9a-f]+)")

SYSTEM = ("You decide which prior findings (by title) might be relevant to a "
          "coding agent reading a source file. Output strict JSON.")


def kb_list_titles(project, n=N_TITLES):
    """Returns list of {kb_id, title}. Title = first non-empty content line."""
    try:
        r = subprocess.run(["kb", "list", "-p", project, "-n", str(n)],
                           capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return []
    out = ANSI.sub("", r.stdout)
    entries = []
    cur_id = None
    cur_title_lines = []
    def flush():
        if cur_id and cur_title_lines:
            entries.append({"kb_id": cur_id,
                            "title": " ".join(cur_title_lines)[:200]})
    for line in out.splitlines():
        s = line.rstrip()
        m = KB_ID_RE.search(s)
        if m and (s.lstrip().startswith("[") or "(" in s):
            # header line
            flush()
            cur_id = m.group(1)
            cur_title_lines = []
        elif s.strip() and cur_id and not cur_title_lines:
            cur_title_lines.append(s.strip())
    flush()
    return entries


def kb_get_body(kb_id):
    try:
        r = subprocess.run(["kb", "get", kb_id, "--raw"],
                           capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        return None
    if r.returncode != 0:
        return None
    parts = r.stdout.split("### Content", 1)
    if len(parts) != 2:
        return r.stdout[:800]
    tail = parts[1].strip()
    for marker in ("\n**Tags:**", "\n*Created:"):
        i = tail.find(marker)
        if i >= 0:
            tail = tail[:i].strip()
    return tail[:800]


def llm_pick(file_path, file_content, titles, timeout=90):
    cand_lines = []
    for i, t in enumerate(titles):
        tag = chr(ord("A") + i) if i < 26 else f"Z{i}"
        cand_lines.append(f"[{tag}] {t['kb_id']}: {t['title']}")
    user = (
        f"File: {file_path}\n===\n{file_content}\n===\n"
        "Recent findings:\n" + "\n".join(cand_lines) +
        '\n\nReturn JSON {"picks":[{"id":"A","why":"<=12 words"}, ...]} with '
        "at most 3 picks. Only include findings whose TITLE suggests genuine "
        "relevance to the file's purpose, behavior, or bugs. Skip if nothing "
        "relevant."
    )
    req = json.dumps({
        "model": "qwen3.6",
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": user}],
        "temperature": 0.0,
        "max_tokens": 400,
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
        return None, time.time() - t0, str(e)
    dt = time.time() - t0
    content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
    try:
        return json.loads(content), dt, None
    except Exception as e:
        return None, dt, f"parse:{e}: {content[:200]}"


def build_read_samples():
    out = []
    for proj in PROJECTS:
        s = json.loads((HERE / f"samples-{proj}.json").read_text())
        for i, fp in enumerate(s["reads"][:2]):
            out.append((f"{proj}/read/{i}", proj, fp))
    return out


def load_cosine_top3_for_reads():
    """From results_v2.jsonl, extract cosine top-3 if present; else fall back
    to results_e1.jsonl which has cosine_top3_pooled."""
    cos = {}
    e1_path = HERE / "results_e1.jsonl"
    if e1_path.exists():
        for line in e1_path.read_text().splitlines():
            r = json.loads(line)
            if "/read/" in r.get("label", ""):
                cos[r["label"]] = r.get("cosine_top3_pooled", [])
    return cos


def process(label, project, file_path, ex):
    rec = {"label": label, "file_path": file_path}
    p = pathlib.Path(file_path)
    if not p.exists():
        rec["_skip"] = "missing"
        return rec
    sz = p.stat().st_size
    rec["file_size"] = sz
    if sz > FILE_MAX:
        rec["_skip"] = "too-large"
        return rec
    try:
        content = p.read_text(errors="replace")
    except Exception as e:
        rec["_skip"] = f"read-err:{e}"
        return rec
    kb_proj = KB_PROJECT[project]
    titles = kb_list_titles(kb_proj, N_TITLES)
    rec["n_titles_offered"] = len(titles)
    if not titles:
        rec["_skip"] = "no-titles"
        return rec
    parsed, dt, err = llm_pick(file_path, content, titles)
    rec["llm_t"] = round(dt, 2)
    if err or not isinstance(parsed, dict):
        rec["_skip"] = f"llm-err:{err}"
        return rec
    letter = {chr(ord("A") + i) if i < 26 else f"Z{i}": t
              for i, t in enumerate(titles)}
    picks_in = (parsed.get("picks") or [])[:3]
    picks_out = []
    for pk in picks_in:
        t = letter.get(pk.get("id", ""))
        if not t:
            continue
        picks_out.append({"kb_id": t["kb_id"], "title": t["title"],
                          "why": (pk.get("why") or "")[:120]})
    # Body-fetch verify
    bodies = list(ex.map(kb_get_body, [p["kb_id"] for p in picks_out]))
    for p_, b in zip(picks_out, bodies):
        p_["body_snippet"] = (b or "")[:300]
    rec["picks"] = picks_out
    return rec


def main():
    samples = build_read_samples()
    cos_lookup = load_cosine_top3_for_reads()
    out_f = (HERE / "results_e3.jsonl").open("w")
    rows = []
    with ThreadPoolExecutor(max_workers=4) as ex:
        for lbl, proj, fp in samples:
            t0 = time.time()
            rec = process(lbl, proj, fp, ex)
            out_f.write(json.dumps(rec) + "\n"); out_f.flush()
            rows.append(rec)
            print(f"{lbl}: size={rec.get('file_size','?')} "
                  f"picks={len(rec.get('picks', []))} "
                  f"t={time.time()-t0:.1f}s "
                  f"skip={rec.get('_skip','')}", file=sys.stderr)
    out_f.close()
    write_summary(rows, cos_lookup)


def write_summary(rows, cos_lookup):
    qualified = [r for r in rows if "_skip" not in r]
    total_picks = sum(len(r.get("picks", [])) for r in qualified)
    overlap_total = 0
    for r in qualified:
        cos3 = cos_lookup.get(r["label"], [])
        picks = {p["kb_id"] for p in r.get("picks", [])}
        overlap_total += len(picks & set(cos3))
    lines = [
        "# E3 results: whole-file + recent titles -> LLM picks",
        "",
        f"Samples: {len(rows)} (qualified <8KB: {len(qualified)})",
        f"Total picks across qualified: {total_picks}",
        f"Overlap with cosine top-3 (results_e1): {overlap_total}",
        "",
        "## Per-sample table",
        "",
        "label                       size   nT  picks  llm_t  skip",
        "-" * 72,
    ]
    for r in rows:
        lines.append(
            f"{r['label']:<26} {r.get('file_size','-'):>6}  "
            f"{r.get('n_titles_offered','-'):>3}  "
            f"{len(r.get('picks', [])):>5}  "
            f"{r.get('llm_t', 0.0):>5}  {r.get('_skip','')}"
        )
    lines += ["", "## Comparison vs cosine top-3 (from results_e1.jsonl)", ""]
    for r in qualified:
        cos3 = cos_lookup.get(r["label"], [])
        picks = [p["kb_id"] for p in r.get("picks", [])]
        lines.append(f"### {r['label']}")
        lines.append(f"  cosine top-3: {cos3}")
        lines.append(f"  e3 picks:     {picks}")
        lines.append(f"  overlap:      {sorted(set(picks) & set(cos3))}")
        for p in r.get("picks", []):
            lines.append(f"    - {p['kb_id']}: {p['title'][:80]}")
            lines.append(f"        why: {p['why']}")
        lines.append("")
    (HERE / "e3_summary.md").write_text("\n".join(lines))


if __name__ == "__main__":
    main()
