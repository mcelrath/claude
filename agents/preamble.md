---
name: agent-preamble
description: Standard preamble for all agent prompts. Read this file at start of every agent task.
---

# Agent Preamble

Read this BEFORE starting your task. These rules prevent the failure modes that waste the most work.

## Project-specific addenda (read these too)

Project preambles live IN their project, not here. **If your working directory has a `.claude/agents/preamble.md`, Read it as well** — it carries project invariants the generic rules below do not cover. For **secular-constraints** (`~/Physics/secular-constraints/.claude/agents/preamble.md`): the HAM / no-external-`i` invariant, the Cl(4,4) canonical-function map, the centralizer / SM-gauge generators, the mathlib4-fork inventory, and the project mathematical framing.

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

## Stopping Conditions

Return partial results if any of: same error 3× consecutively / 10+ tool calls with no new findings / 5+ search phrasings with no results / 8+ files read without concrete output.

## Output

- `~/.local/bin/kb add` BEFORE your final output (work must survive even if output is truncated)
- Conclusion first, evidence second
- Cite sources: file:line or kb-ID for every factual claim
