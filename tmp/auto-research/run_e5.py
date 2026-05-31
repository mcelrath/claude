#!/usr/bin/env python3
"""E5: beads cross-reference — for each sample's file path(s), grep bd issues
referencing those paths in title/description/notes. NO LLM. Pure text match."""
import json, subprocess, pathlib, os, sys, re, time

HERE = pathlib.Path(__file__).parent
PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
# bd is per-repo. We are in ~/Projects/ai/claude — bd_.claude-xxx issues are here.
# For each project we need to bd-search in THAT project's repo.
PROJECT_ROOTS = {
    "braidinfer": pathlib.Path("/home/mcelrath/Projects/ai/braidinfer"),
    "exterior-algebra": pathlib.Path("/home/mcelrath/Projects/ai/exterior_algebra"),
    "llama-cpp": pathlib.Path("/home/mcelrath/Projects/ai/llama.cpp"),
}

def bd_dump(repo: pathlib.Path):
    """Return list of bd issues for a repo as dicts."""
    try:
        r = subprocess.run(["bd", "list", "--status=open", "--json", "-n", "0"],
                           cwd=str(repo), capture_output=True, text=True, timeout=120)
        data = json.loads(r.stdout) if r.stdout else []
        return data if isinstance(data, list) else data.get("issues", [])
    except Exception as e:
        return {"_err": str(e)}

def extract_paths(sample: dict, kind: str, item):
    """Return list of file paths and basenames mentioned in the sample item."""
    paths = []
    if kind == "edit":
        fp, ns = item
        paths.append(fp)
        # also pick out other paths referenced inside the new_string
        for m in re.findall(r"[/\w.-]+\.(?:cu|cuh|cpp|c|h|py|rs|lean|md|cuh|jinja|service)", ns):
            paths.append(m)
    elif kind == "read":
        paths.append(item)
    elif kind == "text":
        for m in re.findall(r"[/\w.-]+\.(?:cu|cuh|cpp|c|h|py|rs|lean|md|cuh|jinja|service)", item):
            paths.append(m)
        # also: bd-IDs and kb-IDs the text already cites — useful cross-refs too
    # dedupe
    seen = set(); out = []
    for p in paths:
        if p in seen: continue
        seen.add(p); out.append(p)
    return out[:6]

def search_issues(issues, paths):
    """Find issues whose title/description/notes contain any of the basenames or full paths."""
    if isinstance(issues, dict) and "_err" in issues:
        return {"_err": issues["_err"]}
    matches = []
    needles = set()
    for p in paths:
        needles.add(p)
        needles.add(os.path.basename(p))
        parent = os.path.basename(os.path.dirname(p))
        if parent:
            needles.add(parent + "/" + os.path.basename(p))
    needles = [n for n in needles if len(n) >= 4]
    for issue in issues:
        if not isinstance(issue, dict): continue
        hay = " ".join([
            issue.get("title", ""),
            issue.get("description", "") or "",
            issue.get("notes", "") or "",
            issue.get("design", "") or "",
        ]).lower()
        hits = [n for n in needles if n.lower() in hay]
        if hits:
            matches.append({"id": issue.get("id"),
                            "title": (issue.get("title") or "")[:120],
                            "status": issue.get("status"),
                            "matched": hits[:5]})
    # rank: open status first, then by number of matched needles
    matches.sort(key=lambda m: (m["status"] != "open", -len(m["matched"])))
    return matches[:3]

def main():
    out_lines = []
    summary_rows = []
    for proj in PROJECTS:
        samples = json.loads((HERE / f"samples-{proj}.json").read_text())
        repo = PROJECT_ROOTS[proj]
        issues = bd_dump(repo) if repo.exists() else {"_err": "repo-missing"}
        n_issues = len(issues) if isinstance(issues, list) else 0
        cases = []
        for i, t in enumerate(samples["assistant_texts"][:2]):
            cases.append((f"{proj}/text/{i}", "text", t))
        for i, (fp, ns) in enumerate(samples["edits"][:2]):
            cases.append((f"{proj}/edit/{i}", "edit", (fp, ns)))
        for i, fp in enumerate(samples["reads"][:2]):
            cases.append((f"{proj}/read/{i}", "read", fp))
        for label, kind, item in cases:
            paths = extract_paths({}, kind, item)
            picks = search_issues(issues, paths)
            rec = {"label": label, "n_issues_scanned": n_issues,
                   "paths": paths, "bd_picks": picks}
            out_lines.append(rec)
            n_picks = len(picks) if isinstance(picks, list) else 0
            summary_rows.append((label, len(paths), n_picks))
    # write
    with (HERE / "results_e5.jsonl").open("w") as f:
        for r in out_lines:
            f.write(json.dumps(r) + "\n")
    md = ["# E5 results: beads cross-reference (no LLM)\n",
          "Per-sample: paths extracted from input, bd picks found.\n",
          "| sample | paths | bd_picks |", "|---|---|---|"]
    for label, np, nb in summary_rows:
        md.append(f"| {label} | {np} | {nb} |")
    md.append("")
    md.append(f"Total samples: {len(summary_rows)}")
    md.append(f"Samples with at least 1 bd pick: {sum(1 for _,_,n in summary_rows if n)}")
    (HERE / "e5_summary.md").write_text("\n".join(md))
    print(f"E5 done: {len(out_lines)} samples, "
          f"{sum(1 for _,_,n in summary_rows if n)} with bd picks")

if __name__ == "__main__":
    main()
