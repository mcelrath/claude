#!/usr/bin/env python3
"""E4: symbol-anchored search baseline.

NO LLM. For each of the 18 samples:
  1. Build input text (text=assistant_text, edit=new_string, read=first-30-lines)
  2. Extract identifiers via ast-grep (with typed+untyped variants) + regex fallback
  3. kb search per ident (-p mapped project, -n 3); bd search per ident (no -p flag)
  4. Pool, dedup by id, top-3 by occurrence count then by order seen.
"""
import json, re, os, sys, subprocess, tempfile, pathlib, collections, statistics, time

HERE = pathlib.Path(__file__).parent
PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
KB_PROJECT = {"braidinfer": "braidinfer",
              "exterior-algebra": "exterior_algebra",
              "llama-cpp": "llama.cpp"}

LANG_BY_EXT = {
    ".py": "python", ".pyi": "python",
    ".c": "c", ".h": "c",
    ".cpp": "cpp", ".cxx": "cpp", ".cc": "cpp", ".hpp": "cpp", ".hip": "cpp",
    ".cu": "cuda", ".cuh": "cuda",
    ".rs": "rust",
    ".lean": None,  # ast-grep doesn't ship lean; regex fallback only
    ".js": "javascript", ".ts": "typescript",
}

# ast-grep patterns per language. Both typed and untyped variants where applicable.
PATTERNS = {
    "python": [
        "def $F($$$): $$$",
        "def $F($$$) -> $R: $$$",
        "class $C: $$$",
        "class $C($$$): $$$",
        "$V = ($$$)",
    ],
    "c": [
        "static $T $X = $$$;",
        "$T $F($$$) { $$$ }",
        "struct $S { $$$ };",
    ],
    "cpp": [
        "static $T $X = $$$;",
        "$T $F($$$) { $$$ }",
        "struct $S { $$$ };",
        "class $C { $$$ };",
    ],
    "cuda": [
        "static $T $X = $$$;",
        "$T $F($$$) { $$$ }",
        "struct $S { $$$ };",
        "class $C { $$$ };",
    ],
    "rust": [
        "fn $F($$$) { $$$ }",
        "fn $F($$$) -> $R { $$$ }",
        "struct $S { $$$ }",
        "pub const $X: $T = $$$;",
    ],
    "javascript": [
        "function $F($$$) { $$$ }",
        "class $C { $$$ }",
        "const $X = $$$",
    ],
    "typescript": [
        "function $F($$$) { $$$ }",
        "class $C { $$$ }",
        "const $X: $T = $$$",
    ],
}

# Capture-name → meta-var of interest order; we just collect all non-trivial alnum tokens
META_VARS = ["F", "C", "X", "S", "V", "T", "R"]

# Generic identifier regex fallback patterns.
RE_CAMEL = re.compile(r"\b([A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+)\b")
RE_SNAKE_FUNC = re.compile(r"\b([a-z][a-z0-9]+(?:_[a-z0-9]+){1,})\b")
RE_ALLCAPS = re.compile(r"\b([A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+)\b")
RE_BACKTICK = re.compile(r"`([^`\n]{2,80})`")

# Skip common-noise words from regex fallback.
NOISE = {
    "true", "false", "none", "null", "self", "this", "return", "import",
    "from", "class", "struct", "static", "const", "void", "int", "char",
    "float", "double", "bool", "string", "list", "dict", "tuple", "set",
}


def ext_of(path: str) -> str:
    return pathlib.Path(path).suffix.lower()


def ast_grep_extract(content: str, lang: str) -> list:
    """Run ast-grep against content via stdin, collect metavar values."""
    patterns = PATTERNS.get(lang, [])
    found = []
    with tempfile.NamedTemporaryFile("w", suffix=f".{lang}", delete=False) as tf:
        tf.write(content)
        path = tf.name
    try:
        for pat in patterns:
            try:
                r = subprocess.run(
                    ["ast-grep", "--lang", lang, "--pattern", pat,
                     "--json=stream", path],
                    capture_output=True, text=True, timeout=10,
                )
            except subprocess.TimeoutExpired:
                continue
            if r.returncode not in (0, 1):
                continue
            for line in r.stdout.splitlines():
                try:
                    m = json.loads(line)
                except Exception:
                    continue
                mvs = m.get("metaVariables", {}).get("single", {})
                for k in META_VARS:
                    if k in mvs:
                        tok = mvs[k].get("text", "").strip()
                        if 2 < len(tok) < 60 and re.match(r"^[A-Za-z_][\w]*$", tok):
                            found.append(tok)
    finally:
        try: os.unlink(path)
        except OSError: pass
    return found


def regex_extract(content: str) -> list:
    out = []
    for rx in (RE_CAMEL, RE_SNAKE_FUNC, RE_ALLCAPS):
        for m in rx.findall(content):
            if m.lower() not in NOISE:
                out.append(m)
    return out


def backtick_camel_extract(content: str) -> list:
    """For text/prose: backtick-quoted idents + CamelCase tokens."""
    out = []
    for bt in RE_BACKTICK.findall(content):
        # Only keep ident-like backticked content.
        bt = bt.strip()
        if re.match(r"^[A-Za-z_][\w\.:]*(?:\(\))?$", bt) and bt.lower() not in NOISE:
            out.append(bt.rstrip("()"))
    for m in RE_CAMEL.findall(content):
        if m.lower() not in NOISE:
            out.append(m)
    return out


def top_idents(toks: list, k: int = 5) -> list:
    """Top-k by frequency, preserving first-seen order on ties."""
    if not toks:
        return []
    counter = collections.Counter(toks)
    # stable by (-count, first-seen-index)
    order = {}
    for i, t in enumerate(toks):
        order.setdefault(t, i)
    ranked = sorted(counter.items(), key=lambda kv: (-kv[1], order[kv[0]]))
    return [t for t, _ in ranked[:k]]


def extract_for_text(content: str) -> list:
    return top_idents(backtick_camel_extract(content), 5)


def extract_for_source(path: str, content: str) -> list:
    ext = ext_of(path)
    lang = LANG_BY_EXT.get(ext)
    toks = []
    if lang:
        toks = ast_grep_extract(content, lang)
    if not toks:
        toks = regex_extract(content)
    return top_idents(toks, 5)


# ----- KB / BD search -----

KB_DOWN = False  # sticky flag after retry


def kb_search(query: str, project: str) -> list:
    """Returns list of {kb_id, head}. Empty on no-results. Skip-marker on server down."""
    global KB_DOWN
    if KB_DOWN:
        return [{"_skip": "kb-server-down"}]
    for attempt in (1, 2):
        try:
            r = subprocess.run(
                ["kb", "search", query, "-p", project, "-n", "3"],
                capture_output=True, text=True, timeout=20,
            )
        except subprocess.TimeoutExpired:
            if attempt == 2:
                KB_DOWN = True
                return [{"_skip": "kb-server-down"}]
            time.sleep(1)
            continue
        combined = r.stdout + r.stderr
        if "Connection refused" in combined or "connection refused" in combined.lower():
            if attempt == 2:
                KB_DOWN = True
                return [{"_skip": "kb-server-down"}]
            time.sleep(1)
            continue
        out = r.stdout.strip()
        if not out or "No results" in out:
            return []
        # Each result block starts with a header line containing kb-YYYYMMDD-HHMMSS-hash
        # Parse out kb-id and head.
        results = []
        # split on double newline
        for chunk in re.split(r"\n\s*\n", out):
            chunk = chunk.strip()
            if not chunk:
                continue
            mid = re.search(r"(kb-\d{8}-\d{6}-[0-9a-f]+)", chunk)
            if not mid:
                continue
            head_line = chunk.split("\n", 1)[0]
            # strip ANSI
            head_clean = re.sub(r"\x1b\[[0-9;]*m", "", head_line)[:160]
            results.append({"kb_id": mid.group(1), "head": head_clean})
        return results
    return []


BD_DOWN = False


def bd_search(query: str, project: str) -> list:
    """bd search; returns list of {id, title}. bd has no project filter; we post-filter on project tag in id prefix when possible."""
    global BD_DOWN
    if BD_DOWN:
        return [{"_skip": "bd-down"}]
    try:
        r = subprocess.run(
            ["bd", "search", query, "-n", "5", "--json"],
            capture_output=True, text=True, timeout=15,
        )
    except subprocess.TimeoutExpired:
        BD_DOWN = True
        return [{"_skip": "bd-down"}]
    if r.returncode != 0 and not r.stdout.strip():
        return []
    try:
        data = json.loads(r.stdout)
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    out = []
    for it in data:
        if not isinstance(it, dict):
            continue
        bid = it.get("id", "")
        title = it.get("title", "")[:140]
        out.append({"id": bid, "title": title})
    return out


# ----- main -----

def read_head(fp: str, n: int = 30) -> str:
    try:
        with open(fp) as f:
            return "".join([line for _, line in zip(range(n), f)])
    except Exception:
        return ""


def build_input(kind: str, sample) -> tuple:
    """Returns (text_for_extraction, source_path_or_None, is_source)."""
    if kind == "text":
        return (sample, None, False)
    if kind == "edit":
        fp, ns = sample
        return (ns, fp, True)
    if kind == "read":
        fp = sample
        head = read_head(fp, 30)
        if not head:
            return (None, fp, True)
        return (head, fp, True)
    return (None, None, False)


def process_sample(label, kind, sample, kb_proj) -> dict:
    text, fp, is_source = build_input(kind, sample)
    rec = {"label": label, "identifiers": [], "kb_picks": [], "bd_picks": []}
    if not text:
        rec["_skip"] = "no-content"
        return rec
    # Extract idents
    if is_source and fp:
        idents = extract_for_source(fp, text)
    else:
        idents = extract_for_text(text)
    rec["identifiers"] = idents

    # Search per ident; pool with occurrence counts.
    kb_pool = collections.OrderedDict()  # kb_id -> {head, matched_idents:set, count}
    bd_pool = collections.OrderedDict()  # bd_id -> {title, matched_idents, count}
    for ident in idents:
        for hit in kb_search(ident, kb_proj):
            if "_skip" in hit:
                rec.setdefault("_kb_skip", hit["_skip"])
                break
            kid = hit["kb_id"]
            entry = kb_pool.get(kid)
            if entry is None:
                entry = {"kb_id": kid, "head": hit["head"], "matched_idents": [], "count": 0}
                kb_pool[kid] = entry
            if ident not in entry["matched_idents"]:
                entry["matched_idents"].append(ident)
            entry["count"] += 1
        for hit in bd_search(ident, kb_proj):
            if "_skip" in hit:
                rec.setdefault("_bd_skip", hit["_skip"])
                break
            bid = hit["id"]
            entry = bd_pool.get(bid)
            if entry is None:
                entry = {"id": bid, "title": hit["title"], "matched_idents": [], "count": 0}
                bd_pool[bid] = entry
            if ident not in entry["matched_idents"]:
                entry["matched_idents"].append(ident)
            entry["count"] += 1

    # Top-3 each, by count desc, preserving order.
    kb_ranked = sorted(kb_pool.values(), key=lambda e: -e["count"])[:3]
    bd_ranked = sorted(bd_pool.values(), key=lambda e: -e["count"])[:3]
    rec["kb_picks"] = [{"kb_id": e["kb_id"], "head": e["head"],
                        "matched_idents": e["matched_idents"]} for e in kb_ranked]
    rec["bd_picks"] = [{"id": e["id"], "title": e["title"],
                        "matched_idents": e["matched_idents"]} for e in bd_ranked]
    return rec


def main():
    out_path = HERE / "results_e4.jsonl"
    summary_path = HERE / "e4_summary.md"
    rows = []
    with out_path.open("w") as f:
        for proj in PROJECTS:
            samples = json.loads((HERE / f"samples-{proj}.json").read_text())
            kb_proj = KB_PROJECT[proj]
            cases = []
            for i, t in enumerate(samples["assistant_texts"][:2]):
                cases.append((f"{proj}/text/{i}", "text", t))
            for i, e in enumerate(samples["edits"][:2]):
                cases.append((f"{proj}/edit/{i}", "edit", e))
            for i, r in enumerate(samples["reads"][:2]):
                cases.append((f"{proj}/read/{i}", "read", r))
            for label, kind, sample in cases:
                rec = process_sample(label, kind, sample, kb_proj)
                f.write(json.dumps(rec) + "\n")
                f.flush()
                rows.append(rec)
                print(f"{label}: idents={len(rec['identifiers'])} "
                      f"kb={len(rec['kb_picks'])} bd={len(rec['bd_picks'])}",
                      file=sys.stderr)

    # Summary
    with summary_path.open("w") as g:
        g.write("# E4 (symbol-anchored, NO LLM) summary\n\n")
        g.write("| label | idents | kb_picks | bd_picks | top idents |\n")
        g.write("| --- | --- | --- | --- | --- |\n")
        for rec in rows:
            g.write(f"| {rec['label']} | {len(rec['identifiers'])} | "
                    f"{len(rec['kb_picks'])} | {len(rec['bd_picks'])} | "
                    f"{', '.join(rec['identifiers'][:5])} |\n")
        ic = [len(r['identifiers']) for r in rows]
        kc = [len(r['kb_picks']) for r in rows]
        bc = [len(r['bd_picks']) for r in rows]
        def med(xs): return statistics.median(xs) if xs else 0
        g.write(f"\n**Medians**: idents/sample={med(ic)}, kb_picks/sample={med(kc)}, "
                f"bd_picks/sample={med(bc)}\n")
        if KB_DOWN: g.write("\n_(kb embedding server was down for some queries.)_\n")
        if BD_DOWN: g.write("\n_(bd search was unresponsive for some queries.)_\n")

    print(f"wrote {out_path} ({len(rows)} rows) and {summary_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
