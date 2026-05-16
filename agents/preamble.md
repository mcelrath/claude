---
name: agent-preamble
description: Standard preamble for all agent prompts. Read this file at start of every agent task.
---

# Agent Preamble

Read this BEFORE starting your task. These rules prevent the failure modes that waste the most work.

## Pre-flight assertion (secular-constraints)

This project is pure Cl(4,4) mathematics. Output is Cl(4,4)-intrinsic. Use canonical functions in cl44/; do not reimplement. Do not compare to external references.

## ALWAYS check the mathlib4 fork

Before declaring any Mathlib infrastructure missing or any Lean theorem unprovable:

- The sibling mathlib4 fork at `~/Physics/mathlib4` on branch `ag` contains in-flight upstream contributions not yet in any Mathlib release. **Read `~/Physics/secular-constraints/docs/reference/proofs.md` and `~/Physics/claude/docs/reference/mathlib-contributions.md`** for the inventory.
- Concrete files commonly forgotten by recon agents (all branch `ag` only):
  - `Mathlib/NumberTheory/LSeries/RiemannZetaBound.lean`
  - `Mathlib/NumberTheory/LSeries/LFunctionPolynomialBound.lean`
  - `Mathlib/NumberTheory/LSeries/OrderOfVanishing.lean` (uses `Mathlib.Analysis.Meromorphic.Order`)
  - `Mathlib/NumberTheory/LSeries/DirichletHadamard.lean`
  - `Mathlib/NumberTheory/LSeries/BorromeanTwist.lean`
  - `Mathlib/Complex/RectangleResidueFinset.lean` + `RectangleResidueTendsto.lean`
  - `Mathlib/Analysis/Matrix/TraceExponentialDecay.lean`
- `git log ag ^upstream/master --oneline | grep -i <topic>` is the canonical query for ag-only contributions.
- If recon claims "Mathlib has no X infrastructure", verify against the fork before declaring infeasibility.

## Prompt framing checklist

Before dispatching any sub-agent or writing any computation prompt, verify:

POSITIVE FRAMING — use these terms:
- shift-operator eigenvalue
- Q-sector mixing matrix (specify Q)
- auxiliary-field self-energy
- Gaussian aux-field saddle
- complex-parameter continuation
- scalar-saddle resonance
- spectral zeta / lattice theta / Hecke functional equation / Mellin transform
- phi-onset / large-phi limit / small-phi regime
- phi-rescaling or spectral rescaling
- Cl(4,4)-intrinsic eigenvalue
- Dimensionless numbers only

## Canonical-function map

Use these functions; do not reimplement saddle/SVD/extraction:

| Question | Canonical function |
|----------|-------------------|
| Q=-1 sector mixing matrix | cl44.q_minus1_mixing.q_minus1_mixing_at_phi(phi) |
| Q=+2/3 sector mixing matrix | cl44.q_plus2_3_mixing.q_plus2_3_mixing_at_phi(phi) |
| Shift-operator eigenvalues | cl44.shift_eigenvalues.shift_eigenvalues_at_phi(phi) |
| Auxiliary-field self-energy spectrum | cl44.aux_field_selfenergy.spectrum_at_phi(phi) |
| phi-onset value | cl44.cosmology.PHI_ONSET |
| beta <-> phi relation | cl44.cosmology.phi_to_beta(phi) |
| Cold-limit sigma_chi values | cl44.cold_limit.solve_saddle_cold(beta) |
| Multi-channel saddle | cl44.gaussian_aux_field.solve_multi_channel(beta, p) |
| Krein-aware Cl(8,0) joint saddle | cl44.joint_saddle.joint_saddle_fierz_krein(phi, N_max) |
| Cl(8,0) signed Fierz table | cl44.fierz_decomposition.fierz_table_signed_cl80() |
| Q-sector projectors | cl44.canonical_operators.q_sector_projectors() |
| Tree-level shift spectrum | cl44.tree_yukawa.tree_yukawa_spectrum() |

## Project mathematical framing (secular-constraints)

This project is Cl(4,4) Clifford algebra: 48-dim R-vector space with quaternionic structure {J_A, J_B, J_C}, shift operator M, centralizer gl(4). Tools: Gaussian integration over auxiliary scalars, analytic continuation, spectral zeta, lattice theta, Hecke functional equations. Output: Cl(4,4)-intrinsic eigenvalues and unitary mixings reported as exact rational/algebraic objects.

## Epistemological Rules (MOST IMPORTANT)

1. **"Not Found" ≠ "Doesn't Exist"**. If you search and find nothing, say "I found no evidence for X (searched: [queries])." Never say "X is open/untested/unknown."

2. **Code > Comments > KB > Your Assumptions**. When sources disagree: test assertions win, then code, then recent KB, then comments, then old KB. Your reasoning about what "should" be true is LAST.

3. **Shallow research = wrong conclusions**. The actual failure mode: you search KB, get 3 results, read summaries, and conclude "this is the state of knowledge." But 40+ findings exist under variant project names, the implementation lives in a different worktree, and a tex draft contradicts your conclusion. **A search is not complete until you have run all 5 rounds** of the kb-research protocol: seed queries → follow-up from results → cross-reference chasing → tex/code grep → contradiction check. Stopping after round 2 because you "have enough" is the #1 research failure mode.

4. **Verify, don't infer**. If you need to know whether Phase 6 was done, grep for the RESULTS, don't infer from a TODO comment. Comments go stale. Code and data don't.

5. **State your evidence**. Every claim must cite: file:line, kb-ID, or command output. "DISASSEMBLY.md:1362 shows BACKREF=1.01x" not "BACKREF is negligible."

## Operational Rules

6. **kb_add before returning**. Your work survives termination only if recorded. Checkpoint every 10 tool uses.

7. **Project tag = what's in the project CLAUDE.md**. For exterior_algebra, always use project="exterior_algebra". Don't invent project names.

8. **kb_search with project=None first** if your topic might span projects. Then narrow. Many findings are filed under variant project names.

9. **Don't duplicate the parent's work**. If the parent gave you KB IDs or findings, start from those. Don't re-search what's already provided.

10. **Read project CLAUDE.md before starting non-trivial work**. If a CLAUDE.md exists at the project root or any ancestor of the working directory, Read it in full. It contains anti-patterns, gatekeepers, object glossaries, and canonical chains that prevent recurring failure modes. Skipping this is the second-largest source of wasted work after Rule 3.

10a. **Proof catalogs**. For Lean theorem inventory or scope-assessment tasks, the auto-generated catalogs live at `~/Physics/claude/docs/reference/proofs.md` (full), `proofs_suspicious.md` (heuristic-flagged), and `mathlib-contributions.md` (our in-flight upstream Mathlib work on branch `ag` vs `upstream/master`). Regenerate via `python3 build_theorem_index.py` from `~/Physics/claude/`.

11. **Use Read, not grep, for content claims**. When you must produce a count, list, or status of declarations in a source file (sorrys, axioms, theorem inventories, TODOs), use the Read tool on the full file. `grep` matches comments, docstrings, and prose discussion of the keyword — not actual proof obligations or declarations. Same for any inventory of code-vs-comment claims.

12. **Derivation-First Rule (DFR)**. When asked to identify or correlate a quantity to a known target (L-function, regulator, mass-spectrum value, anything): derive it via ONE chain of identified principles, compute ONCE, compare without retrofit. **Forbidden:** testing candidate families; "best-of-N" matches; mixing identified + unidentified factors; integer-pattern-matching dimensions to dim-of-some-Lie-group; ratios within "a few %" called "structural" without an explicit derivation chain. Negative result is valid — don't try alternate forms after a derivation gives non-matching values; that IS the answer. If a prompt directs you to "test candidates" / "search space of {X,Y,Z}" / "find best match": STOP. Restate as a single derivation and ask the dispatcher.

## Worktree Protocol

If you are working in a git worktree (check: `git rev-parse --show-toplevel` differs from the project root, or `.git` is a file not a directory):

1. **Commit before reporting completion**. Stage only files you modified (`git add <file1> <file2> ...`). Commit with `--no-gpg-sign` and a descriptive message.
2. **Report your branch name** in your completion message: "Changes committed on branch `<branch-name>`." The team lead needs this to merge.
3. **Do NOT push** — worktree branches are local.
4. **Do NOT merge into master** — the lead handles merging.

If you are NOT in a worktree (normal working directory), your edits land directly in the main tree. No commit needed unless the lead instructs you to commit.

## Scope

When you finish editing, run `git diff --stat` and include the summary in your return
message — which files, how many lines, brief description. The parent uses this to verify
the diff matches the task.

If a build failure or hidden dependency pushes you beyond the files named in the task,
stop and report — don't edit a different file to work around it.

## Lean proof debugging (MANDATORY for non-trivial proofs)

When writing a non-trivial Lean proof, sprinkle `trace_state` between tactics and `set_option pp.coercions true; set_option pp.numericTypes true` at file top. `lake build` then logs the goal at every step (with all casts/coercions visible), the same step-by-step view an interactive prover gives. Faster than edit-build-error iteration. **Remove all `trace_state` calls before the final commit.**

## Mathlib contribution awareness

If your task touches `~/Physics/mathlib4` or consumes Mathlib lemmas, Read `~/Physics/claude/docs/reference/mathlib-contributions.md` to see what this project has already contributed on the `ag` branch. Avoid duplicating landed work; build on it.

## Stopping Conditions

Stop and return partial results if:
- Same error 3 times consecutively
- 10+ tool calls with no new findings
- 5+ search phrasings with no results
- 8+ files read without concrete output

## Output

- kb_add BEFORE your final output (work must survive even if output is truncated)
- Conclusion first, evidence second
- Cite sources: file:line or kb-ID for every factual claim
