# PLAN: auto-surface-related hook

## Goal

Replace ceremonial agent-driven kb-research with an automatic, **lazy** background
process that surfaces related kb entries, beads issues, and files at the
agent's NEXT tool call after a Read/Edit/Write/Stop.

Hard requirements:
- Never block the agent's current tool call.
- Output ≤3 items per surface, each with an LLM-written one-line "why related" reason.
- Cosine similarity from vector search is NOT trusted on its own — LLM re-ranks all candidates.
- Per-session id-cache prevents re-surfacing the same kb_id/bd_id twice in one session.
- Hook must fail-open: kb embedding server (ash:8081) is flaky; LLM endpoint (tardis:9510) may go down; neither breaks the agent.

## Background (what we already know)

Initial experiment (`~/Projects/ai/claude/tmp/auto-research/`) ran 18 samples
across braidinfer / exterior_algebra / llama.cpp transcripts through
qwen3.6:27b @ tardis:9510. Findings:

- `chat_template_kwargs.enable_thinking=false` cuts latency 60s → 1.3s. The
  existing `llm-query` script strips `<think>` but Qwen3 puts reasoning in a
  separate `reasoning_content` field, so all 200 max_tokens get burned and
  `content` is empty. New hook must call the API directly, not via `llm-query`.
- `response_format: {type: "json_object"}` is supported by llama-server and
  guarantees parseable output.
- The `qwen3.5_chat.jinja` template at `tardis:/home/mcelrath/Projects/ai/llama.cpp/`
  correctly implements the `enable_thinking` kwarg (lines 42–60) — verified.
- tardis:9510 service already bumped to `--parallel 4`.
- Subjective relevance hit-rate from cosine-top-3 alone: ~12/18 cases had at
  least one entry at score ≥ 0.50. BUT many cases returned 50–130 cosine hits
  at scores 0.00–0.40 (noise floor). This is why LLM re-rank is the gate.
- Filename-only Read inputs produce hallucinated generic queries. Read events
  must include first 30 lines of file content in the LLM prompt.

## Architecture (lazy queue)

```
~/.cache/auto-surface/
  queue/<session_id>/<seq>.req.json     pending work
  pending/<session_id>.surfaces.jsonl   ready-to-inject results
  cache/<session_id>.json               seen kb_ids, bd_ids, file fire counters
```

Four hook entry points (review fix #6 — Stop is a separate lifecycle hook in
Claude Code, NOT a tool name matched by PostToolUse):

1. **PostToolUse (Write|Edit|Read)** — enqueue only:
   - Gate (extension allow-list, dedup, per-file rate-limit).
   - Build payload (file content for Read, diff for Edit).
   - Append `.req.json` to queue dir using `O_APPEND` (atomic on Linux).
   - Kick detached worker if none running. **Locking**: `flock` per-session
     lockfile at `~/.cache/auto-surface/locks/<session>.worker.lock` before
     spawning; if already locked, assume worker alive and skip spawn (review fix #2).
     Fallback: write worker PID to session cache, check via `/proc/<pid>`.
   - Return `{"continue": true}` in <10 ms.

2. **Stop hook** — enqueue last-assistant-text payload using same enqueue
   path as PostToolUse. Separate entry point because Claude Code's Stop is a
   distinct hook lifecycle, not `PostToolUse` with `tool_name=Stop`.

3. **auto-surface-worker.py** (one detached process per session):
   - Drain queue oldest-first.
   - LLM extract → cosine fan-out → LLM re-rank → dedupe vs session-cache → append to pending.
   - Exit after queue empty for ≥30 s. Releases flock on exit.

4. **PreToolUse (any tool)** — drain & inject:
   - **Atomic drain** (review fix #1): `rename(pending.jsonl, pending.jsonl.draining)`,
     then read the renamed file, then `unlink`. Worker always appends to the
     canonical name; any record written between the rename and the unlink lands
     in a fresh pending.jsonl and is picked up on the NEXT PreToolUse — never dropped.
   - If non-empty: emit as `additionalContext`.
   - Return.

## Relevance pipeline

```
agent activity
  ├── ast-grep extract symbols (introduced defs/classes/static vars)
  ├── LLM extract topic + 2-4 concept queries (json_object, thinking off)
  └── file paths referenced
        ▼
  parallel fan-out:
    kb search × N        (semantic; ash:8081)
    bd search × N        (textual)
    bd list | grep <file>  (no LLM, file-anchored issues)
        ▼  ~10-30 candidates
  LLM re-rank pass:
    feed each candidate body + agent activity in one batch
    classify RELEVANT | TANGENT | UNRELATED + ≤15 words why
    return ≤3 RELEVANT
        ▼
  filter: drop seen ids, format, inject
```

LLM-written "why" is the user-facing artifact; cosine score is internal-only
(never shown — it's misleading at scores 0.30–0.50).

## Experiments (tasks)

E1–E7 below. E1+E4+E5 are the core "which pipeline wins" bake-off; the rest
refine. Each is a bd task child of the epic.

### E1. Cosine→LLM re-rank
Take cosine top-10 per query, batch into one LLM call with full bodies,
classify each. Compare against cosine-top-3 baseline on the 18 existing
samples. Acceptance: ≥80% of accepted entries (judged by user) are
ones the cosine-top-3 baseline missed OR mis-ranked.

### E2. What did cosine miss? (corpus probe)
Pick 5 known-related kb pairs from history. For each, take entry A as the
"edit" and check whether cosine surfaces B in top-10. If not, what query
would? Calibrates whether LLM-generated queries are too narrow.

### E3. Whole-file ingestion
For short source files the agent Reads, feed the whole file + project's
recent kb titles (just titles, ~50 lines), ask LLM to pick 0-3 interactions.
Test whether title-matching by LLM beats embedding search on long-form code.

**Gate revised to 32 KB after E3 ran**: at the original 8 KB threshold, 0/6
read samples qualified (build.rs=10KB, kimi-linear.cpp=20KB, qwen35.cpp=24KB,
amdgpu files 100KB+). At 32 KB, 3/6 qualify; per-call latency 5.7–10.1 s,
acceptable at parallel=4. Files >32 KB still skip (amdgpu kernel sources).

### E4. Symbol-anchored search baseline
Extract identifiers from the diff via ast-grep. Run kb/bd search per symbol.
No LLM extraction step. Establishes the cheap baseline E1 must beat.

### E5. Beads cross-reference (no LLM)
For Edit/Read of file X, grep all bd issues for X in description/notes.
Surface open issues touching the file. Likely high precision, near-zero
latency. Establishes the second cheap baseline.

### E6. Session-topic drift
Accumulate per-fire `topic` strings into per-session list. Every N fires,
distill into a meta-topic and search. Surfaces drift-level context the
per-edit queries miss. Test on full session transcripts.

### E7. Adversarial framing
Reframe LLM prompt as "what mistake might this agent make that prior
findings warn about?" Compare top-3 vs. neutral framing on same inputs.

### E8. Bake-off + threshold tuning
Run **FOUR baselines** together on the 18 samples (extensible to 50),
side-by-side, one row per sample, one column per baseline:

- **B0 (null hypothesis)**: pure cosine top-3, no LLM (review fix #3). This
  is the column E1 must beat for the LLM re-rank to justify its cost.
- **B1 (E1)**: cosine top-10 → LLM re-rank → top-3 RELEVANT.
- **B4 (E4)**: ast-grep symbols → kb/bd search per symbol → top-3.
- **B5 (E5)**: bd issues grep'd for file path → top-3.

User judges each cell relevant/irrelevant. Compute precision per baseline.
Tune similarity threshold, re-rank prompt, item cap.

**Gate for E9** (review fix #5): winner pipeline must achieve **≥70% precision**
(user-judged relevant / total surfaced) on the E8 corpus to proceed. If <70%,
iterate on the re-rank prompt before E9.

### E9. Prototype hook (post-bake-off)
Implement the 4-hook + worker architecture (PostToolUse Write|Edit|Read,
Stop, worker, PreToolUse). Wire into settings.json under a feature flag
(`AUTO_SURFACE=1`). Single-user smoke test for 2 days in the claude
project, then expand to one real project (braidinfer or llama.cpp).

**Entry gate**: E8 winner ≥70% precision (review fix #5).

**Smoke-test acceptance**: drop a `~/.cache/auto-surface/feedback/<session>.jsonl`
where the user can append `{kb_id: ..., verdict: "noise"|"useful"}` per
surfaced item. Ship only if ≤20% noise rate across the 2-day window.

### E10. Calibration logging
Hook writes raw scores + verdicts + (if available) "did the agent use this
information" signal (next-N-edits reference the surfaced kb_id?) to a
calibration log. Re-tune threshold weekly from the log.

## Follow-ups (in bd)

- bd_.claude-82u: kb embedding server (ash:8081) health monitoring — discovered during initial experiment (Connection refused mid-run; semantic kb search silently broken)
- bd_.claude-a6p: fix llm-query to support enable_thinking + reasoning_content fallback — discovered while diagnosing 60s timeouts on qwen3.6 calls

## Out of scope

- Re-implementing kb's semantic search.
- Modifying the qwen3.6 service further (already bumped to parallel 4).
- Cross-session surfacing (each session is isolated; cache is per-session).
- Surfacing to sub-agents (default off — sub-agents have narrow scope and
  extra context can throw them off; opt-in via agent_id).

## Files read in full

- `/home/mcelrath/.local/bin/llm-query` (verified `content`-only extraction)
- `tardis:/etc/systemd/system/llama-qwen3.6.service`
- `tardis:/home/mcelrath/Projects/ai/llama.cpp/qwen3.5_chat.jinja` (lines 42-60 verified)
- 18 sample json files in `~/Projects/ai/claude/tmp/auto-research/samples-*.json`
- `~/Projects/ai/claude/tmp/auto-research/results_v2.jsonl` (full v2 results)
- kb search --help, kb related --help
