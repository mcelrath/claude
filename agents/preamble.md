---
name: agent-preamble
description: Standard preamble for all agent prompts. Read this file at start of every agent task.
---

# Agent Preamble

Read this BEFORE starting your task. These rules prevent the failure modes that waste the most work.

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

## Worktree Protocol

If you are working in a git worktree (check: `git rev-parse --show-toplevel` differs from the project root, or `.git` is a file not a directory):

1. **Commit before reporting completion**. Stage only files you modified (`git add <file1> <file2> ...`). Commit with `--no-gpg-sign` and a descriptive message.
2. **Report your branch name** in your completion message: "Changes committed on branch `<branch-name>`." The team lead needs this to merge.
3. **Do NOT push** — worktree branches are local.
4. **Do NOT merge into master** — the lead handles merging.

If you are NOT in a worktree (normal working directory), your edits land directly in the main tree. No commit needed unless the lead instructs you to commit.

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
