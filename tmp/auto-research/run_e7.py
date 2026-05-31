#!/usr/bin/env python3
"""E7: adversarial framing pass. Same 18 samples as results_v2.jsonl.

Asks the LLM for queries that surface WARN/CONTRADICT/TRAP-type prior findings
(failure/correction). For each query, run kb search -n 5 and tag hits with
their kb TYPE (parsed from the bracket prefix in search output).
"""
import json, sys, pathlib, time, urllib.request, subprocess, re

ENDPOINT = "http://tardis:9510/v1/chat/completions"
PROJECTS = ["braidinfer", "exterior-algebra", "llama-cpp"]
KB_PROJECT = {"braidinfer": "braidinfer", "exterior-algebra": "exterior_algebra",
              "llama-cpp": "llama.cpp"}
HERE = pathlib.Path(__file__).parent

SYSTEM = ("You suggest short search phrases to surface prior knowledge-base "
          "entries that WARN about, CONTRADICT, or describe a TRAP relevant to "
          "a coding agent's current activity. Bias toward correction-type "
          "entries, failure modes, and 'don't do X' findings. Output strict JSON only.")

USER_PREFIX = ("WHAT COULD GO WRONG with this work? Generate 2-4 short conceptual "
               "search queries that would surface prior findings describing "
               "similar mistakes, gotchas, or contradictions. Each query <50 "
               "chars, conceptual not verbatim. JSON: "
               "{\"kb_queries\":[...], \"topic\":\"...\"}\n\n")

ANSI = re.compile(r"\x1b\[[0-9;]*m")
KB_ID_RE = re.compile(r"(kb-\d{8}-\d{6}-[0-9a-f]+)")
TYPE_RE = re.compile(r"\[([A-Z]+)\]")
SCORE_RE = re.compile(r"\(([0-9.]+)\)\s*$")


def llm(user_msg: str, timeout: int = 60, retried: bool = False) -> dict:
    req = json.dumps({
        "model": "qwen3.6",
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_msg},
        ],
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
        if not retried:
            time.sleep(2)
            return llm(user_msg, timeout, retried=True)
        return {"_err": str(e), "_t": time.time() - t0}
    dt = time.time() - t0
    content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
    parsed = parse_json(content)
    return {"raw": content, "parsed": parsed, "t": round(dt, 2),
            "finish": body.get("choices", [{}])[0].get("finish_reason")}


def parse_json(s: str):
    s = s.strip()
    if s.startswith("```"):
        s = s.split("\n", 1)[1].rsplit("```", 1)[0]
    i, j = s.find("{"), s.rfind("}")
    if i < 0 or j <= i:
        return {"_err": "no-braces"}
    try:
        return json.loads(s[i:j+1])
    except Exception as e:
        return {"_err": str(e)}


def kb_search(query: str, project: str, retried: bool = False):
    """Return list of hits with kb_id, type, score, snippet — or {'_err': ...}."""
    try:
        r = subprocess.run(["kb", "search", query, "-p", project, "-n", "5"],
                           capture_output=True, text=True, timeout=20)
        combined = r.stdout + r.stderr
        if "Connection refused" in combined or "embedding" in combined.lower() and "down" in combined.lower():
            if not retried:
                time.sleep(2)
                return kb_search(query, project, retried=True)
            return {"_err": "embedding-server-down"}
        out = ANSI.sub("", r.stdout).strip()
        if not out or "No results" in out.split("\n")[0]:
            return []
        hits = []
        for chunk in out.split("\n\n"):
            lines = [l.strip() for l in chunk.strip().split("\n") if l.strip()]
            if not lines:
                continue
            head = lines[0]
            t_m = TYPE_RE.search(head)
            id_m = KB_ID_RE.search(head)
            sc_m = SCORE_RE.search(head)
            if not id_m:
                continue
            body = " ".join(lines[1:])[:200]
            hits.append({
                "kb_id": id_m.group(1),
                "type": (t_m.group(1).lower() if t_m else "unknown"),
                "score": (float(sc_m.group(1)) if sc_m else None),
                "snippet": body,
            })
        return hits
    except Exception as e:
        if not retried:
            time.sleep(2)
            return kb_search(query, project, retried=True)
        return {"_err": str(e)}


def read_head(fp: str, n: int = 30):
    try:
        with open(fp) as f:
            head = []
            for i, line in enumerate(f):
                if i >= n:
                    break
                head.append(line.rstrip())
            return "\n".join(head)
    except Exception:
        return ""


def fmt_edit(fp, ns):
    return f"[EDIT] {fp}\n--- new content (truncated) ---\n{ns[:1200]}"


def fmt_read(fp):
    head = read_head(fp, 30)
    if head:
        return f"[READ] {fp}\n--- first 30 lines ---\n{head[:1200]}"
    return f"[READ] {fp}"


def fmt_text(t):
    return f"[ASSISTANT OUTPUT]\n{t[:1500]}"


def main():
    out_path = HERE / "results_e7.jsonl"
    f = out_path.open("w")
    for proj in PROJECTS:
        samples = json.loads((HERE / f"samples-{proj}.json").read_text())
        kb_proj = KB_PROJECT[proj]
        cases = []
        for i, t in enumerate(samples["assistant_texts"][:2]):
            cases.append((f"{proj}/text/{i}", fmt_text(t)))
        for i, (fp, ns) in enumerate(samples["edits"][:2]):
            cases.append((f"{proj}/edit/{i}", fmt_edit(fp, ns)))
        for i, fp in enumerate(samples["reads"][:2]):
            cases.append((f"{proj}/read/{i}", fmt_read(fp)))
        for label, content in cases:
            res = llm(USER_PREFIX + content)
            parsed = res.get("parsed") or {}
            queries = parsed.get("kb_queries", [])[:4] if isinstance(parsed, dict) else []
            results = []
            for q in queries:
                hits = kb_search(q, kb_proj)
                results.append({"q": q, "hits": hits})
            rec = {
                "label": label,
                "topic": parsed.get("topic") if isinstance(parsed, dict) else None,
                "adversarial_queries": queries,
                "llm_t": res.get("t"),
                "llm_err": res.get("_err"),
                "results": results,
            }
            f.write(json.dumps(rec) + "\n")
            f.flush()
            print(f"{label} t={res.get('t')}s queries={len(queries)}", file=sys.stderr)
    f.close()


if __name__ == "__main__":
    main()
