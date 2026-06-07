#!/usr/bin/env python3
"""Pipeline-aware analyzer for block-text-search-on-source.sh.

Decides whether a Bash command performs a text-search over SOURCE-FILE CONTENT
(which must be blocked → forces a full Read / ast-grep / loogle) versus a
text-search over COMMAND OUTPUT (which is fine).

Blocks when a text-search stage (grep/rg/egrep/fgrep, or awk/sed search-form)
either:
  (a) takes a source file as a direct argument:        grep PAT file.py
  (b) is fed by a file-reader on a source file:         cat file.py | grep PAT
Also blocks file-content searches:  find ... -exec grep,  ... | xargs grep.

ALLOWS text-search piped from any non-file-reader command (the key fix):
  bd show … | grep …      git log … | grep …      ls … | grep …

Prints the first detected source extension (→ caller blocks) or "ALLOW".
Command is read from argv[1] if present, else stdin.
"""
import sys
import re
import shlex

BLOCKED = set((
    "c cc cpp cxx h hpp hh hxx ipp tpp cu cuh hip py pyi rs js mjs cjs jsx ts tsx "
    "go java kt kts swift scala rb sh bash zsh lua php dart ex exs hs html htm css "
    "scss json yaml yml md markdown toml xml xsd xsl xslt plist svg sql csv tsv "
    "rst tex latex lean"
    # NOTE: 'log' is intentionally NOT blocked -- log files are unstructured text
    # and grep IS the right tool for them (user-directed 2026-05-30). .txt/.ini/
    # .cfg/.conf/.lock are likewise grep-allowed (never in this set).
).split())

READERS = {"cat", "head", "tail", "less", "more", "tac", "nl", "strings", "xxd", "od", "bat"}
SEARCH = {"grep", "rg", "ripgrep", "egrep", "fgrep"}
BUILD_CACHE = (".lake/", "/build/", "/dist/", "/node_modules/", "/target/",
               "/.venv/", "/.cache/", "/.git/")

_EXT_RE = re.compile(r'(?:[\w/~$.+\-]|\*)\.([A-Za-z0-9]+)$')


def src_ext(tok):
    """Return the blocked source extension if tok is a source-file path token, else None."""
    t = tok.strip('"\'')
    if any(b in t for b in BUILD_CACHE):
        return None  # build/cache dirs are text-search-allowed
    m = _EXT_RE.search(t)
    if not m:
        return None
    e = m.group(1)
    return e if e in BLOCKED else None


def split_pipe_stages(cmd):
    """Split on single | (stdin pipe), respecting quotes; || is NOT a pipe."""
    stages, cur, q, i = [], "", None, 0
    while i < len(cmd):
        ch = cmd[i]
        if q:
            cur += ch
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            cur += ch
        elif ch == '|' and i + 1 < len(cmd) and cmd[i + 1] == '|':
            cur += '||'
            i += 1
        elif ch == '|':
            stages.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    stages.append(cur)
    return stages


def lead(stage):
    try:
        toks = shlex.split(stage)
    except Exception:
        toks = stage.split()
    base = toks[0].split('/')[-1] if toks else ""
    return base, toks


def is_search_stage(base, stage):
    if base in SEARCH:
        return True
    if base == "awk" and re.search(r"/[^/\n]+/", stage):
        return True  # awk '/PAT/'
    if base == "sed" and re.search(r"/[^/\n]+/[pd]\b", stage):
        return True  # sed -n '/PAT/p'  (not substitution s///)
    return False


def first_source_arg(toks):
    for t in toks[1:]:
        if t.startswith('-'):
            continue
        e = src_ext(t)
        if e:
            return e
    return None


_HEREDOC_RE = re.compile(
    r'<<-?\s*["\']?(\w+)["\']?.*?\n.*?\n\1\n?',
    re.DOTALL,
)


def strip_heredocs(cmd: str) -> str:
    """Remove heredoc bodies (stdin data, not commands) before analysis.

    A heredoc body can contain arbitrary text including source file names and
    pipe characters, which the analyzer would otherwise misinterpret as command
    structure.  Strip everything between the << marker line and the closing
    sentinel.

    Replaces the heredoc body with a placeholder so the surrounding command
    structure (e.g. '2>&1' after the closing sentinel) is preserved.
    """
    # Match << 'EOF' or << EOF or <<- EOF, and everything up to and including
    # the closing sentinel on its own line.
    result = _HEREDOC_RE.sub(lambda m: f'<< {m.group(1)}_STRIPPED\n{m.group(1)}_STRIPPED\n', cmd)
    return result


def analyze(cmd):
    cmd = strip_heredocs(cmd)
    stages = split_pipe_stages(cmd)
    parsed = [lead(s) for s in stages]
    for idx, (base, toks) in enumerate(parsed):
        # find/fd ... -exec grep  → file-content search
        if base in ("find", "fd") and "-exec" in toks:
            ei = toks.index("-exec")
            if ei + 1 < len(toks) and toks[ei + 1].split('/')[-1] in SEARCH:
                e = next((src_ext(t) for t in toks if src_ext(t)), None)
                if e:
                    return e
        # ... | xargs grep  → file-content search; check the preceding stage's files
        if base == "xargs" and any(t.split('/')[-1] in SEARCH for t in toks):
            if idx > 0:
                e = next((src_ext(t) for t in parsed[idx - 1][1] if src_ext(t)), None)
                if e:
                    return e
        # grep/rg/awk-search/sed-search stage
        if is_search_stage(base, stages[idx]):
            e = first_source_arg(toks)          # (a) direct source-file arg
            if e:
                return e
            if idx > 0:                          # (b) fed by a file-reader on source
                pbase, ptoks = parsed[idx - 1]
                if pbase in READERS:
                    e = first_source_arg(ptoks)
                    if e:
                        return e
    return None


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    ext = analyze(cmd)
    print(ext if ext else "ALLOW")


if __name__ == "__main__":
    main()
