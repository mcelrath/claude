---
description: Run verify-latex over the 4 canonical tex papers; report citation drift.
argument-hint: "[--strict | --fast]"
---

Task(subagent_type="verify-latex",
     prompt="Verify citations in ~/Physics/claude/{8D_PAPER,HYPERCOMPLEX_ANALYSIS,NUMBER_THEORY,rh}.tex and sections/*.tex against the Lean catalog (proofs.md), Python symbol existence, and kb-IDs. Args: $ARGUMENTS. Follow the verify-latex agent prompt template; ~/.local/bin/kb add the drift report (project=algebraic-genesis, tags=verify-latex,citation-drift) BEFORE returning. Include the kb-id in the final message.")
