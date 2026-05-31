# E7: Adversarial vs Neutral Framing — KB hit-type distribution

Comparison of neutral framing (results_v2.jsonl, top-3 hits per query) vs adversarial framing (results_e7.jsonl, top-5 hits per query) for the auto-surface query-extract step. WARN = kb hits with TYPE in {correction, failure}.

Note: neutral baseline used -n 3 per query; adversarial used -n 5 per task spec. This means absolute hit counts are NOT directly comparable, but the FRACTION of WARN-type hits IS.

## Per-sample table

label | neutral_q | neutral_hits | neutral_warn | neutral_warn_frac | adv_q | adv_hits | adv_warn | adv_warn_frac
--- | --- | --- | --- | --- | --- | --- | --- | ---
braidinfer/edit/0 | 3 | 6 | 0 | 0.00 | 4 | 11 | 1 | 0.09
braidinfer/edit/1 | 4 | 13 | 0 | 0.00 | 4 | 7 | 1 | 0.14
braidinfer/read/0 | 0 | 0 | 0 | 0.00 | 4 | 10 | 0 | 0.00
braidinfer/read/1 | 4 | 6 | 0 | 0.00 | 4 | 8 | 0 | 0.00
braidinfer/text/0 | 4 | 1 | 0 | 0.00 | 4 | 1 | 0 | 0.00
braidinfer/text/1 | 4 | 2 | 0 | 0.00 | 4 | 10 | 0 | 0.00
exterior-algebra/edit/0 | 4 | 13 | 0 | 0.00 | 4 | 21 | 0 | 0.00
exterior-algebra/edit/1 | 3 | 9 | 0 | 0.00 | 4 | 21 | 0 | 0.00
exterior-algebra/read/0 | 3 | 9 | 0 | 0.00 | 4 | 20 | 0 | 0.00
exterior-algebra/read/1 | 3 | 9 | 1 | 0.11 | 4 | 21 | 3 | 0.14
exterior-algebra/text/0 | 4 | 15 | 1 | 0.07 | 4 | 22 | 2 | 0.09
exterior-algebra/text/1 | 4 | 13 | 0 | 0.00 | 4 | 23 | 0 | 0.00
llama-cpp/edit/0 | 4 | 2 | 0 | 0.00 | 4 | 2 | 0 | 0.00
llama-cpp/edit/1 | 4 | 1 | 0 | 0.00 | 4 | 2 | 0 | 0.00
llama-cpp/read/0 | 4 | 7 | 0 | 0.00 | 4 | 8 | 0 | 0.00
llama-cpp/read/1 | 4 | 9 | 0 | 0.00 | 4 | 18 | 0 | 0.00
llama-cpp/text/0 | 4 | 3 | 0 | 0.00 | 4 | 4 | 0 | 0.00
llama-cpp/text/1 | 4 | 5 | 0 | 0.00 | 4 | 7 | 0 | 0.00

## Overall

- Neutral framing: 2/123 = 1.6% of hits are correction/failure
- Adversarial framing: 7/216 = 3.2% of hits are correction/failure
- Ratio adv/neutral = 1.99x
- Absolute delta: +1.6 percentage points

## Verdict

Adversarial framing biased the kb-query generation toward WARN-type (correction/failure) hits.
