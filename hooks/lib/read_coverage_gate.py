#!/usr/bin/env python3
"""PreToolUse(Read) coverage gate -- sub-agent vs main-session asymmetry.

Closes the gap the grep ban leaves: Read(offset=, limit=) is grep-by-another-name
(jump to the region you think matters, miss the side-concerns elsewhere in the SAME
file). Policy (user-directed 2026-05-30; Claude Code 2.1.145+ fires hooks for
sub-agents, distinguished by the input's `agent_id` field -- verified on 2.1.154):

  SUB-AGENT (hook input has agent_id): must read the WHOLE FILE. Any partial Read
    (offset/limit) of a source/doc file is BLOCKED, EXCEPT strict top-down
    contiguous paging of a > WINDOW-line file (the only mechanical way to read a
    big file whole). Small-file slices, spot-reads and mid-file jumps are blocked.

  MAIN SESSION (no agent_id): NOT blocked -- the orchestrator may slice, and the
    companion PostToolUse augmentation (read_dep_augment.py) surfaces the cross-file
    producers/consumers + the in-file side-concerns the slice skipped. This hook
    only RECORDS coverage (shared state the augmentation + meter read) and meters.

Only gates source/doc files (coverage->understanding); logs/data/binaries fail open.
Fail-open on ANY error -- a bug here must never block all Reads. State:
$STATE_DIR/<session>-readcov/<sha1(path)> holds the max CONTIGUOUS line reached.
Exit 0 = allow (optional NOTE on stderr). Exit 2 = block (sub-agent only).
"""
import sys, json, os, hashlib

WINDOW = 2000  # Read returns up to this many lines with no `limit`
STATE_DIR = "/tmp/claude-kb-state"
SRC = {
    ".py", ".pyi", ".lean", ".md", ".markdown", ".tex", ".rst", ".rs", ".c",
    ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hh", ".hxx", ".cu", ".cuh", ".go",
    ".java", ".kt", ".kts", ".swift", ".scala", ".rb", ".sh", ".bash", ".zsh",
    ".lua", ".php", ".hs", ".ex", ".exs", ".js", ".mjs", ".cjs", ".ts", ".tsx",
    ".jsx", ".json", ".yaml", ".yml", ".toml", ".html", ".htm", ".css", ".scss",
}


def _session_id():
    try:
        return open(f"{STATE_DIR}/session-{os.getppid()}").read().strip()
    except Exception:
        return str(os.getppid())


def _covdir():
    d = f"{STATE_DIR}/{_session_id()}-readcov"
    os.makedirs(d, exist_ok=True)
    return d


def _slot(covdir, fp):
    return os.path.join(covdir, hashlib.sha1(fp.encode()).hexdigest())


def _get_maxend(covdir, fp):
    try:
        return int(open(_slot(covdir, fp)).read().strip())
    except Exception:
        return 0


def _set_maxend(covdir, fp, v):
    try:
        with open(_slot(covdir, fp), "w") as f:
            f.write(str(int(v)))
    except Exception:
        pass


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0
    if d.get("tool_name") != "Read":
        return 0
    ti = d.get("tool_input", {}) or {}
    fp = ti.get("file_path", "") or ""
    if not fp or not os.path.isfile(fp):
        return 0
    if os.path.splitext(fp)[1].lower() not in SRC:
        return 0
    try:
        nlines = sum(1 for _ in open(fp, "rb"))
    except Exception:
        return 0
    if nlines <= 0:
        return 0

    agent_id = d.get("agent_id")  # truthy => this Read is from a sub-agent
    offset = ti.get("offset")
    limit = ti.get("limit")
    partial = (offset is not None) or (limit is not None)

    covdir = _covdir()
    prior = _get_maxend(covdir, fp)

    if not partial:
        start, end = 1, min(nlines, WINDOW)
    else:
        start = max(1, int(offset) if offset else 1)
        end = min(nlines, start + int(limit) - 1) if limit else min(nlines, start + WINDOW - 1)

    # ---- SUB-AGENT: whole-file enforcement (block slicing) ----
    if partial and agent_id:
        if nlines <= WINDOW:
            sys.stderr.write(
                f"BLOCKED (sub-agent): partial Read (offset/limit) of {fp} "
                f"({nlines} lines). Agents must read the WHOLE file -- it fits in "
                f"ONE full Read (<= {WINDOW}); drop offset/limit. There are always "
                f"side-concerns elsewhere in the same file you are not looking for, "
                f"and slicing misses them.\n")
            return 2
        if start > prior + 1:
            sys.stderr.write(
                f"BLOCKED (sub-agent): spot-read of {fp} -- starting at line {start} "
                f"leaves lines [{prior + 1}, {start}) unread. To read this {nlines}-"
                f"line file WHOLE, page top-down with NO gaps: Read offset={prior + 1} "
                f"next. Agents read the whole file; no jumping to a region.\n")
            return 2
        # else: strict top-down page of a big file -> allowed (reading it whole)

    # ---- record CONTIGUOUS coverage (a gap below `start` does not advance it) ----
    if start <= prior + 1:
        _set_maxend(covdir, fp, max(prior, end))

    # ---- meter (both sessions): big file not yet fully covered ----
    new_max = _get_maxend(covdir, fp)
    if nlines > WINDOW and new_max < nlines:
        pct = 100 * new_max // nlines
        sys.stderr.write(
            f"NOTE: {fp} [{nlines} lines]: contiguous 1-{new_max} read ({pct}%). "
            f"Next page: Read offset={new_max + 1}. Full coverage required before a "
            f"coverage/structure/behavior claim about this file.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
