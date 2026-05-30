---
name: agent-preamble
description: Standard preamble for all agent prompts. Read this file at start of every agent task.
---

# Agent Preamble

Read this BEFORE starting your task. These rules prevent the failure modes that waste the most work.

## Pre-flight assertion (secular-constraints)

This project is pure Cl(4,4) mathematics. Output is Cl(4,4)-intrinsic. Use canonical functions in cl44/; do not reimplement. Do not compare to external references.

## HAM INVARIANT (no external i — PROVEN, and hooks do NOT protect you)

In Cl(4,4) a physical observable that comes out **complex is a proof of error, not a result.** By the HAM theorem (`~/Physics/claude/HYPERCOMPLEX_ANALYSIS.tex` §5), Cl(4,4) is one of only 6 hypercomplex extensions supporting monogenic functions / a Cauchy–Riemann equation; an external `i` (Python `1j`, `dtype=complex`) BREAKS meromorphy. The `1j` block hook does NOT fire for sub-agents, so this rule is on you.

- A complex mass / eigenvalue / pole means EITHER the `i` is an internal $J_X$ — identify the sector: vector $V_8\to J_A$, even-spinor $S^+\to J_B$, odd-spinor $S^-\to J_C$ (the fermion mass op `M_g5_odd_48` is odd-spinor $\to J_C$) — OR you are computing the wrong object (e.g. a pole of a non-normal operator like `det(γ̃·p + M)=0`).
- **Never repair a complex observable by taking `.real` / `abs()` / dropping the imaginary part** — that is selective omission of an exact computation.
- Observables (masses) are real spectral / channel-trace data `Tr(P_α f(M))` — e.g. `(4/3)·eig(MᵀM)` (PSD gram) — NOT complex poles. $J_X$ is the internal Wick rotation, the only legitimate "$i$".
- Known external-`i` violations (do NOT copy): `self_consistent.py::_sector_gram_complex_np`, `h_chi` (these are the character-twist computation, separate from the aux-field calc).
- Before any J-contraction, verify J is in the SAME basis as its partner (orthogonal-similarity arbiter; mixed weight-Q × Fock-J is the recurring trap).
- **HAM ↔ polylog ladder: Cl(4,4) is the trilogarithm Li₃ (class-3 nilpotent).** The HAM dimension ladder (Ramakrishnan monodromy termination; `app_A_polylogarithms.tex` "Dimensional Constraints from Monodromy Structure" table): Li₁↔ℂ (dim 2, Cl(1,1)), Li₂↔split-ℍ (dim 4, Cl(2,2), Heisenberg H₃, class 2), **Li₃↔split-𝕆 (dim 8 = Cl(4,4)), nilpotency class 3** (= split-octonion Mal'cev class 3), Li₄↔dim 16 (where the ternary constraint terminates — octonions are the last; this IS the HAM theorem). For Cl(4,4) polylog / monodromy / Bogoliubov-sheet / partition-function work the relevant polylog is the **trilogarithm Li₃**; the dimension table maps each algebra to its polylog weight — match Cl(4,4) → Li₃ there.

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
| SM gauge / centralizer generators (su3_c, su2_L, u1_Y/N, Q_EM, J_A/B/C) | see "Centralizer / SM-gauge generators" below — DO NOT re-derive |

## Centralizer / SM-gauge generators (lean-proven, multi-rotation — call the codified functions)

The su(3)_c × su(2)_L × u(1)_Y × u(1)_N gauge generators, the complex structures J_A/B/C, and the centralizer decomposition are **codified and Lean-proven**. Their derivation chains through **multiple rotations** (Fock basis → `centralizer_weight_basis` P → `U_pairing_48` 48-lift → the canonical **`cartan_weight`** joint-Cartan frame) plus sign-canonical literals; the codified functions encapsulate all of it. Call them directly, contracted in the `cartan_weight` frame:

| Generator | Canonical cl44 function | Lean |
|-----------|-------------------------|------|
| su(3)_c COLOR (splits lepton/quark, Casimir {0,16}) | `cl44.centralizer_jw.cij_jw(a,b)`, a,b∈{1,2,3} | `PatiSalamBreaking`, `ColorSU3Classification` |
| su(2)_L weak | `cl44.gauge_algebra.su2_weak_48` | `SU2WeakFromCentralizer` |
| Q_EM, T3_L, Y, T3_R, B−L, N | `cl44.gauge_algebra.cartan_charge_operators_48` | `Gauge48Charges`, `U4ResidualSM` |
| complex structures J_A,J_B,J_C | `cl44.complex_structures.j_matrix_16` (Fock) / `j_matrices_48` (weight) | `SplitCompactJ`, `WickRotation`, `WickCartanCompact` |
| Fock↔weight P, 48-lift | `cl44.centralizer.centralizer_weight_basis`, `cl44.gauge_algebra.U_pairing_48` | `UPairing48` |
| canonical frame | `cl44.basis_types.CANONICAL_WEIGHT_FRAME` = `'cartan_weight'` | — |

The lepton/quark COLOR su(3) is `cij_jw(a,b)`, a,b∈{1,2,3} (splits lepton-singlet/quark-triplet, Casimir {0,16}). The V₃ generation/pairing su(3) is `sm_color_su3_48` (uniform Casimir 4/3). The leptoquark coset is the 4 generators `{C02,C20,C03,C30}` — a CP³ = U(4)/(U(1)×U(3)) Hermitian-symmetric coset, an sl(2) triple with J'=ad(u(1)_N central H). Full context: the **project** CLAUDE.md section "CENTRALIZER DECOMPOSITION — CANONICAL ENTRY POINT", to read before centralizer/gauge work.

## Project mathematical framing (secular-constraints)

This project is Cl(4,4) Clifford algebra: 48-dim R-vector space with quaternionic structure {J_A, J_B, J_C}, shift operator M, centralizer gl(4). Tools: Gaussian integration over auxiliary scalars, analytic continuation, spectral zeta, lattice theta, Hecke functional equations. Output: Cl(4,4)-intrinsic eigenvalues and unitary mixings reported as exact rational/algebraic objects.

## Epistemological Rules (MOST IMPORTANT)

1. **"Not Found" ≠ "Doesn't Exist"**. If you search and find nothing, say "I found no evidence for X (searched: [queries])." Never say "X is open/untested/unknown."

2. **Code > Comments > KB > Your Assumptions**. When sources disagree: test assertions win, then code, then recent KB, then comments, then old KB. Your reasoning about what "should" be true is LAST.

3. **Shallow research = wrong conclusions**. The actual failure mode: you search KB, get 3 results, read summaries, and conclude "this is the state of knowledge." But 40+ findings exist under variant project names, the implementation lives in a different worktree, and a tex draft contradicts your conclusion. **A search is not complete until you have run all 5 rounds** of the kb-research protocol: seed queries → follow-up from results → cross-reference chasing → tex/code grep → contradiction check. Stopping after round 2 because you "have enough" is the #1 research failure mode.

4. **Verify, don't infer**. If you need to know whether Phase 6 was done, grep for the RESULTS, don't infer from a TODO comment. Comments go stale. Code and data don't.

5. **State your evidence**. Every claim must cite: file:line, kb-ID, or command output. "DISASSEMBLY.md:1362 shows BACKREF=1.01x" not "BACKREF is negligible."

## Operational Rules

6. **kb_add before returning, VIA CLI** (the MCP `mcp__knowledge-base__kb_add` was REMOVED 2026-05-19 because sub-agent MCP propagation is racy per GitHub claude-code #14496/#13254). Your work survives termination only if recorded. Checkpoint every 10 tool uses. Exact invocation:

   ```
   ~/.local/bin/kb add "FINDING CONTENT" \
     -t discovery \
     -p algebraic-genesis \
     -s SPRINT-NAME \
     --tags TAG1,TAG2,TAG3 \
     -e "evidence: file:line citations"
   ```

   Returns `Added: kb-YYYYMMDD-HHMMSS-hash`. Capture the kb-id and report it.

   Other operations: `kb get <id>`, `kb search "query" -p PROJECT`, `kb list -p PROJECT`, `kb correct <new> --supersedes-id <old> --correction-reason <reason>`, `kb stats`.

   **NEVER** call `mcp__knowledge-base__kb_*` — those tools no longer exist on the MCP server.

7. **Project tag is one of: `algebraic-genesis` (physics/math cross-cutting), `secular-constraints`, `claude`, or another existing project name listed in your project's CLAUDE.md**. Do NOT invent new project names. If unsure, check `~/.local/bin/kb stats` (lists current namespaces). For the two-repo Physics work (`~/Physics/secular-constraints/` + `~/Physics/claude/`), the canonical name is **Algebraic Genesis**.

8. **kb search with project=None first** if your topic might span projects. Then narrow. Many findings are filed under variant project names (the Algebraic Genesis namespace-consolidation epic is in flight; see bd `secular-constraints-adkh.4`).

9. **Don't duplicate the parent's work**. If the parent gave you KB IDs or findings, start from those. Don't re-search what's already provided.

10. **Read project CLAUDE.md before starting non-trivial work**. If a CLAUDE.md exists at the project root or any ancestor of the working directory, Read it in full. It contains anti-patterns, gatekeepers, object glossaries, and canonical chains that prevent recurring failure modes. Skipping this is the second-largest source of wasted work after Rule 3.

10a. **Proof catalogs**. For Lean theorem inventory or scope-assessment tasks, the auto-generated catalogs live at `~/Physics/claude/docs/reference/proofs.md` (full), `proofs_suspicious.md` (heuristic-flagged), and `mathlib-contributions.md` (our in-flight upstream Mathlib work on branch `ag` vs `upstream/master`). Regenerate via `python3 build_theorem_index.py` from `~/Physics/claude/`.

11. **Use Read, not grep, for content claims** (counts/lists/inventories of declarations, sorrys, axioms, TODOs). grep matches comments/docstrings; only Read disambiguates.

12. **Derivation-First Rule (DFR)**. When asked to identify or correlate a quantity to a known target (L-function, regulator, mass-spectrum value, anything): derive it via ONE chain of identified principles, compute ONCE, compare without retrofit. **Forbidden:** testing candidate families; "best-of-N" matches; mixing identified + unidentified factors; integer-pattern-matching dimensions to dim-of-some-Lie-group; ratios within "a few %" called "structural" without an explicit derivation chain. Negative result is valid — don't try alternate forms after a derivation gives non-matching values; that IS the answer. If a prompt directs you to "test candidates" / "search space of {X,Y,Z}" / "find best match": STOP. Restate as a single derivation and ask the dispatcher.

13. **NEVER create new `.md` files.** The block-markdown-files hook blocks the Write anyway. Investigation reports MUST return inline to the dispatcher (and/or `kb add`); `*_INVESTIGATION.md` is hard-blocked unconditionally. For the destination matrix by content type, see `~/.claude/CLAUDE.md` section "Why .md creation is blocked". Existing .md files can be Edit'd / `git mv`'d freely.

13a. **kb-down does NOT release the .md ban.** If `~/.local/bin/kb add` fails (ash:8081 unreachable, network error, anything), your report content stays in the inline `tool_result` you return to the dispatcher — the dispatcher persists later. Alternatively, write a queue file at `~/.claude/pending-kb-adds/<UTC>-<session-short>.txt` with the structured header (`# type: ... # project: ... # tags: ...` then blank line then content); `kb flush-pending` drains it. **Never create a .md as a fallback persistence path.**

## Worktree Protocol

In a worktree (`.git` is a file, not a dir): commit your changes (`git add <files> && git commit --no-gpg-sign -m '...'`), report the branch name in your return message, do not push, do not merge into master. In a normal working tree: no commit needed unless lead instructs.

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

Return partial results if any of: same error 3× consecutively / 10+ tool calls with no new findings / 5+ search phrasings with no results / 8+ files read without concrete output.

## Output

- `~/.local/bin/kb add` BEFORE your final output (work must survive even if output is truncated)
- Conclusion first, evidence second
- Cite sources: file:line or kb-ID for every factual claim
