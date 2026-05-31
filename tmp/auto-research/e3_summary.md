# E3 results: whole-file + recent titles -> LLM picks

Samples: 6 (qualified <8KB: 0)
Total picks across qualified: 0
Overlap with cosine top-3 (results_e1): 0

## Per-sample table

label                       size   nT  picks  llm_t  skip
------------------------------------------------------------------------
braidinfer/read/0               -    -      0    0.0  missing
braidinfer/read/1           10153    -      0    0.0  too-large
exterior-algebra/read/0    238276    -      0    0.0  too-large
exterior-algebra/read/1    100177    -      0    0.0  too-large
llama-cpp/read/0            20656    -      0    0.0  too-large
llama-cpp/read/1            24834    -      0    0.0  too-large

## Comparison vs cosine top-3 (from results_e1.jsonl)

No samples qualified at the spec's 8KB gate, so no LLM call was made; cosine
top-3 from results_e1 stands unchallenged at this gate. CONCLUSION: the 8KB
threshold is too tight for the available read-event corpus — all real reads
in samples-* are 10KB-238KB (PLAN-braidinfer.md missing on disk).

---

# E3 relaxed diagnostic pass (FILE_MAX = 32KB)

Run with `E3_FILE_MAX=32768` for diagnostic purposes. Persisted to
`results_e3_relaxed32k.jsonl`. Same script, same prompt, same titles, same model.

Qualified: 3 / 6  (braidinfer/read/0 still missing; the two amdgpu files
remain >32KB)

label                       size   nT  picks  llm_t
--------------------------------------------------------
braidinfer/read/1           10153   50    2    5.73
llama-cpp/read/0            20656   50    3    8.27
llama-cpp/read/1            24834   50    3   10.09

Median llm_t = 8.27s. n_titles_offered = 50 across the board.

## Per-qualified detail (relaxed pass)

### braidinfer/read/1  (build.rs, 10 KB)
- cosine top-3:  kb-20260522-103625-77facd, kb-20260512-040353-98fe0a, kb-20260526-065811-891a48
- e3 picks:       kb-20260529-205833-8944af, kb-20260512-040353-98fe0a
- overlap:        {kb-20260512-040353-98fe0a}    (1/2 overlap with cos3)
- (A) BraidInfer megakernel architecture — high signal: this build.rs compiles HIP kernels for that architecture.
- (B) MROPE non-determinism / -ffp-contract H1 — high signal: build.rs lines 84,134 set -ffp-contract=fast, EXACTLY what the kb names. Title-based pick was right.

### llama-cpp/read/0  (kimi-linear.cpp, 20 KB)
- cosine top-3:  []   (cosine pipeline returned no hits)
- e3 picks:       kb-20260528-081153-a9fb38, kb-20260327-192713-13bff5, kb-20260327-140136-ab3525
- overlap:        {}
- Picks center on SSM math-path divergence and SP matmul NaNs — kimi-linear is delta-net-style linear attention; signal plausible.
- Title-based picks SURFACED 3 entries cosine missed entirely.

### llama-cpp/read/1  (qwen35.cpp, 24 KB)
- cosine top-3:  []   (cosine pipeline returned no hits)
- e3 picks:       kb-20260528-081153-a9fb38, kb-20260529-020501-95e962, kb-20260528-075834-8ea310
- overlap:        {}
- All three picks name qwen3.5/35B-A3B regressions, MTP/spec-decode bugs — direct relevance to qwen35.cpp model file. High signal.

## Summary signal (relaxed)

- Total picks: 8 across 3 qualified samples (≈2.7/sample, target ≤3).
- Cosine top-3 overlap: 1/8 picks = 12.5% overlap. Title-based and cosine surface DIFFERENT entries.
- For 2/3 cases cosine returned NOTHING; title-based produced 6 plausibly-relevant picks. Strong signal that whole-file + titles can succeed where cosine fails.
- Per-call latency: 5.7-10.1s, dominated by file size (more input tokens = more time). 8KB gate would give ~3-5s; 24KB tops out near 10s.

## Caveat

User has not yet judged relevance. "Plausibly relevant by inspection of title
+ body snippet" is what's claimed; final precision goes to E8 bake-off.
