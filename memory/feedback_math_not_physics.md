---
name: No physics framing in agent dispatch
description: Never frame mathematical computations as "solving" physics problems; direct agents to compute exact mathematical objects only
type: feedback
---

Never direct agents toward "solving" a physical hierarchy, "explaining" a ratio, or "finding the source" of a discrepancy. This is mathematics.

Correct agent dispatch framing: "compute the eigenvalues of X exactly and report them."

Wrong framing: "figure out whether the b-tower is responsible for the 16.8x hierarchy."

**Why:** The project computes mathematical objects (eigenvalues of matrices, L-function zeros, algebraic identities). Physics interpretation of those objects is separate and not the agent's job. Directing agents toward physics goals causes them to stop at "close enough" numerical matches instead of completing exact calculations.

**How to apply:** In every agent dispatch involving eigenvalues, matrix norms, or sums: state the mathematical object precisely, ask for the exact result, and omit any mention of whether the result "explains" or "matches" a physical observable.
