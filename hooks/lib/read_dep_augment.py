#!/usr/bin/env python3
"""PostToolUse(Read) dependency augmentation -- MAIN SESSION, source files only.

User-directed (2026-05-30): the main session (orchestrator) is allowed to slice a
source file, but when it does, surface what the slice hides so the side-concerns
are not silently missed:

  1. IN-FILE: the top-level definitions OUTSIDE the read slice (the side-concerns
     in the SAME file the slice skipped).
  2. CROSS-FILE: producers (where a name the slice references is defined) and
     consumers (where a name the slice defines is used), via ast-grep across the
     repo source tree -- bounded and best-effort.

Sub-agents NEVER reach here (they are forced to read whole files by
read_coverage_gate.py, so there is nothing to augment) -- this hook exits 0 if
`agent_id` is present. Only fires on PARTIAL reads (offset/limit) of source files,
once per file per session (deduped). Fail-open + time-bounded everywhere: a slow
or broken augmentation must never disrupt a Read.

Emits a compact note to stderr. Exit 0 always (PostToolUse, never blocks).
"""
import sys, json, os, re, hashlib, subprocess

WINDOW = 2000
STATE_DIR = "/tmp/claude-kb-state"
AST_TIMEOUT = 4  # seconds, total budget for ast-grep work
MAX_NAMES = 4    # cap cross-file lookups
MAX_HITS = 4     # cap hits reported per name

LANG = {
    ".py": "python", ".pyi": "python", ".rs": "rust", ".go": "go", ".java": "java",
    ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript", ".ts": "typescript",
    ".tsx": "tsx", ".jsx": "jsx", ".c": "c", ".h": "c", ".cpp": "cpp", ".cc": "cpp",
    ".cxx": "cpp", ".hpp": "cpp", ".hh": "cpp", ".rb": "ruby", ".lua": "lua",
    ".sh": "bash", ".bash": "bash", ".scala": "scala", ".swift": "swift", ".kt": "kotlin",
}
# def-site patterns per ast-grep language (return-annotated variants included --
# the plain `def $N($$$): $$$` misses annotated defs, per the project's ast-grep gotcha)
DEFPATS = {
    "python": ["def $N($$$): $$$", "def $N($$$) -> $R: $$$", "class $N: $$$",
               "class $N($$$): $$$"],
    "rust": ["fn $N($$$) $$$", "fn $N($$$) -> $R $$$", "struct $N $$$", "enum $N $$$",
             "trait $N $$$"],
    "go": ["func $N($$$) $$$", "type $N struct $$$"],
    "javascript": ["function $N($$$) { $$$ }", "const $N = $_"],
    "typescript": ["function $N($$$) { $$$ }", "class $N { $$$ }"],
    "c": ["$T $N($$$) { $$$ }"], "cpp": ["$T $N($$$) { $$$ }"],
    "ruby": ["def $N\n$$$\nend", "class $N\n$$$\nend"],
    "bash": ["$N() { $$$ }"], "lua": ["function $N($$$) $$$ end"],
}


def _run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True,
                              timeout=AST_TIMEOUT).stdout
    except Exception:
        return ""


def _defs_in_file(fp, lang):
    """Return list of (name, line) for definitions in fp, via ast-grep."""
    out = []
    for pat in DEFPATS.get(lang, []):
        txt = _run(["ast-grep", "--lang", lang, "--pattern", pat, "--json", fp])
        try:
            for m in json.loads(txt or "[]"):
                meta = m.get("metaVariables", {}).get("single", {})
                name = (meta.get("N") or {}).get("text")
                line = m.get("range", {}).get("start", {}).get("line")
                if name and line is not None:
                    out.append((name, line + 1))  # ast-grep line is 0-based
        except Exception:
            continue
    # dedupe by name keeping first line
    seen, res = set(), []
    for n, l in sorted(out, key=lambda x: x[1]):
        if n not in seen:
            seen.add(n); res.append((n, l))
    return res


def _consumers(name, lang, root, exclude_fp):
    """file:line of usages of `name` elsewhere in the tree (bounded)."""
    txt = _run(["ast-grep", "--lang", lang, "--pattern", f"{name}($$$)",
                "--json", root])
    hits = []
    try:
        for m in json.loads(txt or "[]"):
            f = m.get("file", "")
            ln = m.get("range", {}).get("start", {}).get("line", 0) + 1
            if f and os.path.abspath(f) != os.path.abspath(exclude_fp):
                hits.append(f"{f}:{ln}")
            if len(hits) >= MAX_HITS:
                break
    except Exception:
        pass
    return hits


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0
    if d.get("tool_name") != "Read":
        return 0
    if d.get("agent_id"):          # sub-agents read whole files -> nothing to augment
        return 0
    ti = d.get("tool_input", {}) or {}
    fp = ti.get("file_path", "") or ""
    if not fp or not os.path.isfile(fp):
        return 0
    ext = os.path.splitext(fp)[1].lower()
    lang = LANG.get(ext)
    if not lang:                   # only augment languages ast-grep can parse for defs
        return 0
    offset, limit = ti.get("offset"), ti.get("limit")
    if offset is None and limit is None:
        return 0                   # whole read -> no slice -> nothing skipped

    try:
        nlines = sum(1 for _ in open(fp, "rb"))
    except Exception:
        return 0
    if nlines <= 0:
        return 0
    start = max(1, int(offset) if offset else 1)
    end = min(nlines, start + int(limit) - 1) if limit else min(nlines, start + WINDOW - 1)

    # dedupe: augment each file once per session
    try:
        covdir = f"{STATE_DIR}/{open(f'{STATE_DIR}/session-{os.getppid()}').read().strip()}-readcov"
    except Exception:
        covdir = f"{STATE_DIR}/{os.getppid()}-readcov"
    os.makedirs(covdir, exist_ok=True)
    marker = os.path.join(covdir, "aug-" + hashlib.sha1(fp.encode()).hexdigest())
    if os.path.exists(marker):
        return 0
    open(marker, "w").write("1")

    defs = _defs_in_file(fp, lang)
    skipped = [(n, l) for (n, l) in defs if not (start <= l <= end)]
    in_slice = [n for (n, l) in defs if start <= l <= end]

    lines = []
    if skipped:
        lst = ", ".join(f"{n}(L{l})" for n, l in skipped[:12])
        more = "" if len(skipped) <= 12 else f" (+{len(skipped) - 12} more)"
        lines.append(
            f"DEP-AUGMENT {os.path.basename(fp)} [{nlines} lines]: you read {start}-{end}; "
            f"the REST of this file also defines: {lst}{more}. Read the whole file for "
            f"these side-concerns.")

    root = os.path.dirname(fp)
    for p in (os.path.dirname(root), root):  # try the package dir then the file's dir
        if os.path.basename(p) == "cl44" or os.path.isdir(os.path.join(p, "cl44")):
            root = os.path.join(p, "cl44") if os.path.isdir(os.path.join(p, "cl44")) else p
            break
    cons = []
    for n in in_slice[:MAX_NAMES]:
        hits = _consumers(n, lang, root, fp)
        if hits:
            cons.append(f"{n} -> {', '.join(hits)}")
    if cons:
        lines.append("  consumers of names in your slice: " + "; ".join(cons))

    if lines:
        sys.stderr.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
