#!/usr/bin/env python3
"""Build e7_summary.md comparing neutral (results_v2.jsonl) vs adversarial (results_e7.jsonl)."""
import json, pathlib, re
HERE = pathlib.Path(__file__).parent
ANSI = re.compile(r"\x1b\[[0-9;]*m")
TYPE_RE = re.compile(r"\[([A-Z]+)\]")

WARN = {"correction", "failure"}


def type_from_v2_head(head: str) -> str:
    h = ANSI.sub("", head)
    m = TYPE_RE.search(h)
    return m.group(1).lower() if m else "unknown"


def load_v2():
    recs = {}
    with (HERE / "results_v2.jsonl").open() as f:
        for line in f:
            r = json.loads(line)
            recs[r["label"]] = r
    return recs


def load_e7():
    recs = {}
    with (HERE / "results_e7.jsonl").open() as f:
        for line in f:
            r = json.loads(line)
            recs[r["label"]] = r
    return recs


def neutral_stats(v2rec):
    queries = []
    types = []
    parsed = v2rec.get("llm", {}).get("parsed", {})
    if isinstance(parsed, dict):
        queries = parsed.get("kb_queries", []) or []
    for q, hits in (v2rec.get("kb_hits") or {}).items():
        if isinstance(hits, dict):  # _err
            continue
        for h in hits or []:
            head = h.get("head", "")
            if "No results" in head or not head:
                continue
            t = type_from_v2_head(head)
            if t == "unknown":
                # fragment of a wrapped body line, not a real hit head
                continue
            types.append(t)
    return queries, types


def adv_stats(e7rec):
    queries = e7rec.get("adversarial_queries") or []
    types = []
    for r in e7rec.get("results", []) or []:
        hits = r.get("hits")
        if isinstance(hits, dict):
            continue
        for h in hits or []:
            types.append(h.get("type", "unknown"))
    return queries, types


def warn_frac(types):
    if not types:
        return 0.0, 0, 0
    w = sum(1 for t in types if t in WARN)
    return (w / len(types)), w, len(types)


def main():
    v2 = load_v2()
    e7 = load_e7()
    labels = sorted(set(v2) & set(e7))

    rows = []
    n_total = 0
    n_warn = 0
    a_total = 0
    a_warn = 0
    for lbl in labels:
        nq, ntypes = neutral_stats(v2[lbl])
        aq, atypes = adv_stats(e7[lbl])
        nf, nw, nt = warn_frac(ntypes)
        af, aw, at = warn_frac(atypes)
        n_total += nt; n_warn += nw
        a_total += at; a_warn += aw
        rows.append((lbl, len(nq), nt, nw, nf, len(aq), at, aw, af))

    lines = []
    lines.append("# E7: Adversarial vs Neutral Framing — KB hit-type distribution\n")
    lines.append("Comparison of neutral framing (results_v2.jsonl, top-3 hits per query) "
                 "vs adversarial framing (results_e7.jsonl, top-5 hits per query) for the "
                 "auto-surface query-extract step. WARN = kb hits with TYPE in "
                 "{correction, failure}.\n")
    lines.append("Note: neutral baseline used -n 3 per query; adversarial used -n 5 per "
                 "task spec. This means absolute hit counts are NOT directly comparable, "
                 "but the FRACTION of WARN-type hits IS.\n")
    lines.append("## Per-sample table\n")
    lines.append("label | neutral_q | neutral_hits | neutral_warn | neutral_warn_frac | adv_q | adv_hits | adv_warn | adv_warn_frac")
    lines.append("--- | --- | --- | --- | --- | --- | --- | --- | ---")
    for (lbl, nq, nt, nw, nf, aq, at, aw, af) in rows:
        lines.append(f"{lbl} | {nq} | {nt} | {nw} | {nf:.2f} | {aq} | {at} | {aw} | {af:.2f}")

    nfrac = (n_warn / n_total) if n_total else 0.0
    afrac = (a_warn / a_total) if a_total else 0.0
    lines.append("")
    lines.append("## Overall")
    lines.append("")
    lines.append(f"- Neutral framing: {n_warn}/{n_total} = {nfrac*100:.1f}% of hits are correction/failure")
    lines.append(f"- Adversarial framing: {a_warn}/{a_total} = {afrac*100:.1f}% of hits are correction/failure")
    if nfrac > 0:
        lines.append(f"- Ratio adv/neutral = {afrac/nfrac:.2f}x")
    delta = (afrac - nfrac) * 100
    lines.append(f"- Absolute delta: {delta:+.1f} percentage points")
    lines.append("")
    verdict = ("Adversarial framing biased the kb-query generation toward WARN-type "
               "(correction/failure) hits." if afrac > nfrac else
               "Adversarial framing did NOT increase the fraction of WARN-type hits "
               "over neutral.")
    lines.append(f"## Verdict\n\n{verdict}")
    (HERE / "e7_summary.md").write_text("\n".join(lines) + "\n")
    print(f"neutral warn-frac: {nfrac*100:.1f}% ({n_warn}/{n_total})")
    print(f"adv     warn-frac: {afrac*100:.1f}% ({a_warn}/{a_total})")


if __name__ == "__main__":
    main()
