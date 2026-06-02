---
allowed-tools: Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git show:*), Bash(git merge-base:*), Bash(git tag:*), Bash(git rev-parse:*), Bash(git checkout:*), Bash(git switch:*), Bash(git apply:*), Bash(git cherry-pick:*), Bash(git rebase:*), Bash(git commit:*), Bash(git add:*), Bash(git rm:*), Bash(git worktree:*), Bash(git stash:*), Bash(git reflog:*), Bash(ast-grep:*), Bash(bd:*), Bash(/bin/true)
description: Drive a refactor / rebase / cherry-pick / forward-port / git-replay task with the hard-won discipline that keeps these error-prone jobs from cascading into conflict hell.
argument-hint: [task description or bd epic-id]
---

# /refactor — disciplined rebasing, squashing, cherry-pick, forward-port, git replay

These tasks are error-prone. Agents repeatedly make the same mistakes: decompose by
subject matter, cherry-pick blindly onto evolved upstream, lose work to a bad reset, defer
follow-ups into nowhere. This skill front-loads the lessons that two large real-world
campaigns (llama.cpp MVW rebase `llamacpp-it4z`; composable_kernel forward-port `vllm-tdn`)
paid for in days of wall-clock. **Read this whole file before touching git.**

## Context

- Branch: !`git branch --show-current 2>&1 || /bin/true`
- Working dir: !`pwd`
- Tree state (MUST be clean before any replay):
```
!`git status --porcelain 2>&1 || /bin/true`
```
- Recent commits:
```
!`git log --oneline -12 2>&1 || /bin/true`
```
- gpgsign setting (if true and no tty, every commit needs `-c commit.gpgsign=false`):
```
!`git config --get commit.gpgsign 2>&1 || /bin/true`
```

## The task

`$ARGUMENTS`

If `$ARGUMENTS` is a bd epic-id: `bd show $ARGUMENTS` and read its design file in full first.
If it's a free-text description: this is almost certainly multi-phase — create a bd epic
(see "Plan & track" below) before writing code.

---

## Iron rules (CLAUDE.md — non-negotiable)

- **NEVER** `git reset --hard`, `git push --force`, `git add -A`, `git add .`.
- **NEVER** push. Tags and commits stay local until the user drives the push.
- Interactive rebase IS allowed and often the right tool (reorder, split, fixup, drop) — but
  this harness has no TTY, so run it SCRIPTED, never bare. Drive the todo list with
  `GIT_SEQUENCE_EDITOR` and any message edits with `GIT_EDITOR` (see Step 7). A bare
  `git rebase -i` / `git add -i` hangs waiting for an editor — that is the thing to avoid.
- Commit with `git commit --no-gpg-sign` (or `-c commit.gpgsign=false` if the repo forces signing).
- Before EVERY Edit/Write: `git diff -- <path>`. Unexpected changes = concurrent edit → STOP.
- DELETE superseded code; no compat shims, wrappers, aliases, or dead code. Git history is the backup.
- Every deferred / out-of-scope item becomes a real `bd` issue with `--deps=discovered-from:<epic>`
  BEFORE the plan ships. Free-text "follow-up later" is forbidden.
- **The task is not DONE until you have cleaned up after yourself** (Step 8). Every worktree
  and branch you created is removed, merged, or explicitly parked-with-a-bd-issue; no tree is
  left dirty. Leaving orphan worktrees/branches/uncommitted files is an incomplete task, not a
  finished one — report your artifact disposition list before claiming done.

---

## Foundational discipline — this is where most failures actually come from

Nearly every cascading-conflict disaster traces back to one of two omissions: the agent did
not READ the touched files in full, or did not MAP what consumes them. Do both, on every
topic, before you change a line. These apply throughout — every step below assumes them.

### 1. Read every touched file IN FULL

- For each file in the topic's scope, read the WHOLE file on BOTH sides:
  `git show <our-branch>:<file>` and `git show <upstream-target>:<file>`. Not the diff hunks —
  the file. The diff shows what changed; only the full file shows the *interaction surface*:
  what else lives there, what invariants the surrounding code assumes, which struct fields and
  helpers your change touches indirectly.
- A slice / hunk-only read is how you miss the sibling helper that uses a different API, the
  struct field another topic depends on, the static_assert that guards your type. Those are
  exactly what turn a "clean" cherry-pick into a deadlock.
- `grep`/`rg` on source is BLOCKED (and is the wrong tool for "what does this file do"). Read it.

### 2. Map producers and consumers with `ast-grep`, then verify the change works for each

A change is not understood until you know who calls it and what it calls. AFTER reading the
files in full, use `ast-grep` (AST-shape search — `rg` only for literal strings) to enumerate
the interaction surface of every symbol your change touches:

```
# downstream consumers — who CALLS the function/method you changed:
ast-grep --lang cpp -p 'changed_fn($$$)'
ast-grep --lang cpp -p '$X.changed_method($$$)'
# producers / definitions — what your code DEPENDS ON (signatures, structs, enums):
ast-grep --lang cpp -p 'struct ChangedStruct { $$$ }'
ast-grep --lang python -p 'def changed_fn($$$)'        # also run the `-> $R` variant
```

For EACH call site found: read it in full and confirm your change is compatible with it —
signature, types, ownership, ordering, the struct fields it reads. If upstream changed a
signature your code calls (or your change alters a signature upstream code calls), that call
site is a conflict you must resolve NOW, not discover at link time. This consumer/producer
sweep is what makes the Step 5 gate ("is this even consumed?") and the Step 3 decomposition
("which topics share a helper?") answerable with evidence instead of guesswork.

> `ast-grep`'s empty result is NOT proof of absence — a pattern silently misses any node with
> a child it doesn't model (e.g. a Python def with a return annotation needs the `-> $R`
> variant). Run both plain and annotated forms; confirm a known call site matches first.

---

## Step 0 — Bank state before you touch anything (Phase 0 discipline)

The single cheapest insurance. ~10 minutes; saves a lost day.

1. Confirm clean tree (`git status --porcelain` empty). If dirty, stop and resolve.
2. Anchor tag the current tip — full history stays reachable forever:
   ```
   git tag pre-<task>-<YYYY-MM-DD> HEAD
   ```
3. Semantically tag each LOAD-BEARING commit you intend to replay:
   ```
   git tag stable/<feature-name> <sha>
   ```
   Verify each resolves: `git rev-parse stable/<feature-name>^{commit}`.
4. Record the tag manifest in the bd epic `--notes` (and `kb add`). Do NOT push tags.
5. **Enable rerere** — `git config rerere.enabled true`. The same helper/struct conflict
   recurs across topics in a forward-port; rerere records your first hand-resolution and
   replays it automatically on every repeat. Single highest-ROI line in this skill.
6. **Bank a behavioural baseline** (the Feathers characterization-test move, in our terms):
   before touching git, record what "working" means for the CURRENT branch — `llama-bench`
   pp/tg numbers and one smoke-request transcript — into the bd epic notes. This is your
   regression oracle in Step 6; "no functional regression" needs a recorded before-state.
7. **Open an artifact ledger in the bd epic `--notes`.** Every branch and worktree you create
   during this task gets ONE line, added the moment you create it:
   `created: <branch-or-.worktrees/name> — purpose`. When you dispose of it in Step 8, append
   the outcome to the same line: `... — purpose → MERGED 2026-06-02` (or `→ DELETED` / `→ PARKED
   bd-xxxx`). That turns Step 8's completion gate into an O(1) visual scan instead of a
   cross-reference exercise. You cannot clean up what you did not track. This repo's 80-worktree
   graveyard is what happens without it.

After this, any `reset`/rebase mistake is recoverable with `git reflog` + the anchor tag.
You can throw away whole branches without fear.

---

## Step 1 — Find the merge-base and size the drift

```
MB=$(git merge-base <our-branch> <upstream-target>)
git log --oneline $MB..<our-branch>          # commits to replay
git log --oneline $MB..<upstream-target>      # how far upstream evolved
git diff --numstat $MB <our-branch> -- <hot file>   # per-file change size
```

Compute the **overlap set**: files WE touched ∩ files UPSTREAM touched. That intersection
is your entire conflict surface. Everything outside it is free. Cluster the overlap by
subsystem and rank by `numstat` — the few biggest-churn files dominate the cost.

---

## Step 2 — Classify every commit you plan to replay

Not all commits are real. Audit `$MB..<our-branch>` and bucket each:

| bucket | disposition |
|--------|-------------|
| LOAD-BEARING (net new capability / fix) | keep — this is what you replay |
| INTERMEDIATE-REVERT-NOISE (add then remove; net-zero) | DROP entirely |
| diagnostic / env-var flag churn | FOLD into the one final flag-default commit |
| flip-flop (toggled on/off/on across commits) | keep ONLY the final-state |
| docs / research / microbench / scratch | DROP — leave on the old branch as notes |
| duplicate commits ("Working ✓" ×2) | replay ONCE |

Dropping noise is the biggest lever for shrinking conflict surface. In the CK port, 39 of
70 commits were docs/research — none belonged on upstream.

---

## Step 3 — THE decomposition trap (read twice)

**Decompose topics by COMPILATION-UNIT-DEPENDENCY, never by SUBJECT MATTER.**

The MVW campaign's 13 subject-matter topics ("EP", "MTP", "structure-match") ALL failed to
build in isolation. Reason: a helper function / struct field / type added during one topic's
work is *used* by another topic. Example: `ggml_cuda_graph_guess_n_tokens`, added during the
graph-cache work, is called by the prefill-skip work — so those "separate" topics can't be
separated. Cherry-pick conflicts then **cascade**: resolving topic A pulls in half of topic B.

Correct decomposition: a handful of WIDER topics, each encompassing *all* the helpers,
struct fields, and integration points it needs to be **self-compiling** on top of the target.
MVW collapsed 13 → 5 cohesive topics (model-arch, ssm-kernels, graph-machinery, ep-and-rocm,
fattn). Topics may have a strict order (T1 before T2) — declare it.

Smell test for a bad split: "this topic won't compile until I also bring in X from another
topic." That means X belongs in this topic. Merge them.

---

## Step 4 — Choose the replay mechanism

Pick per-task; they are not interchangeable.

### A. `git cherry-pick` — only when commits apply cleanly onto a target that barely moved
Good for a short, linear, conflict-free series. The moment conflicts cascade across topics,
abandon it (see Step 3).

### B. Per-feature squashed net-diff via `git apply --3way` — the workhorse for forward-ports
When upstream rewrote the hot files and your history has noise/duplicates, do NOT
`git rebase --onto` (it re-resolves the same evolving file once *per micro-commit* — 6–8×).
Instead apply each feature's NET diff once and resolve each file once:
```
git switch -c topic/<feature> <upstream-target>
git diff $MB <our-branch> -- <feature files> > /tmp/feat.patch
git apply --check /tmp/feat.patch   # FIRST: enumerate hunks that fail context-match.
git apply --3way   /tmp/feat.patch
git status            # CRITICAL — inspect the result two ways:
                      #  (1) ANY .rej file = unresolved conflict (--3way drops .rej on
                      #      partial failure instead of inline markers). Hand-merge it.
                      #  (2) a hunk that fails --check AND has no 3-way blob is SILENTLY
                      #      SKIPPED by --3way (no .rej, no marker). So also:
git diff --stat       # confirm EXACTLY the files you expect changed — a short stat
                      # means hunks were silently dropped; reconcile before committing.
# after resolving:
git add <files> && git commit --no-gpg-sign -m "forward-port(<topic>): <what + why>"
```

### C. Reimplement-on-upstream — when upstream's API diverged too far to port a diff
Treat your branch as a **SPEC, not a cherry-pick source**. Per topic, in order:
1. `git show <our-branch>:<file>` — read your final state IN FULL (Foundational rule 1).
2. `git show <upstream-target>:<file>` — read upstream's evolved version IN FULL. What changed:
   new signatures, refactored functions, split/renamed struct fields, moved subtrees.
3. Identify the integration points with the ast-grep consumer/producer sweep (Foundational
   rule 2): enumerate every caller of the symbols you touch and every symbol you depend on,
   read each, and confirm compatibility. This IS the interaction-surface map.
4. `git switch -c topic/<feature> <upstream-target>`.
5. Reimplement the SEMANTIC change against upstream's API. Cherry-pick the parts that still
   apply; hand-write the parts that don't. Bring in every helper the topic needs (Step 3).
6. Build. Smoke test. Commit as 1–2 rationale-rich commits.
7. `kb add`: what was cherry-picked vs reimplemented, what conflicted, which upstream API
   differences mattered. The next topic (and the next session) needs this.

### D. `git rebase --onto <new-base> <old-base> <branch>` — only for a clean linear series
onto a target that did NOT rewrite your hot files. If it did, use B instead. Escape hatch if
you must `--onto` over rewritten files: `-X ours` / `-X theirs` auto-resolves one conflict
direction — but you lose Step 4B's per-file visibility, so prefer B.

### E. `git replay --onto <new-base> <old-base>..<branch>` — headless dry-run replay
Newren's `replay` (experimental; verify `git replay --help` exists on this host first — it
does on git ≥ 2.44) replays commits via merge-ort WITHOUT touching the working tree or index.
It prints proposed new SHAs (and `update-ref` lines) instead of moving any branch. Use it to
**detect conflicts before committing to a real rebase** — a zero-side-effect probe of how bad
the replay will be. Nothing is applied until you act on its output.

---

## Step 5 — Gate before you do hard merge work

Before resolving an expensive collision, ask: **does anything downstream actually consume this?**

The CK port nearly burned a day reconciling a 805/610-line `gemm_quant` rewrite — until an
Explore of the consumer (vLLM) proved vLLM never calls that surface. The whole collision was
*excluded*: take upstream's version verbatim, preserve our variant on the old branch + a bd
issue for future integration. Answer "is it consumed?" with the Foundational-rule-2 ast-grep
sweep across the consuming repo (then read the hits) — trace the include-chain / call-graph
before committing to a merge, not with a guess.

Decompose each ported feature into:
- **clean-add** — file absent upstream, zero deps on rewritten code → cheap, do these first.
- **collision** — upstream rewrote the same file → expensive; gate it (is it consumed?),
  and prefer adopting upstream's new structure over forcing yours.

---

## Step 6 — Build & validate at every commit

- After each topic commit: build (`ninja -C build -j32 <target>`) — STOP on first failure
  not fixable in ~15 min; triage (port bug vs integration vs genuine upstream-API blocker).
- Smoke test: minimal load + one real operation. Confirm no functional regression vs the
  bare upstream-target baseline (establish that baseline smokes FIRST).
- Don't gate on perfect performance — get it green and coherent, then validate on a real
  workload and file regressions as fresh bd issues.
- GPU binaries: ALWAYS via `scripts/launch-llama.py` (see project CLAUDE.md). Never direct.

---

## Step 7 — Squashing for a clean final history

- **Squash a whole series into one** — the cleanest method, no rebase needed:
  `git reset --soft $MB && git commit --no-gpg-sign` (soft reset keeps worktree + index; only
  moves the ref). This is the ONE sanctioned `reset` — `--soft` never touches files; `--hard`
  stays forbidden. You write the single message fresh, so message handling is trivial.
- **Mark fixups as you go, fold them at the end** — the maintainer idiom for keeping a clean
  series without manual todo-editing. Commit corrections with `git commit --fixup=<sha>` (or
  `--squash=<sha>`), then collapse them all with autosquash. `fixup!` DROPS the fixup's message
  (keeps the target's); `squash!` CONCATENATES both messages. Run it scripted (no TTY):
  ```
  GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash --no-gpg-sign $MB
  ```
  `--autosquash` reorders each `fixup!`/`squash!` next to its target and pre-marks the action,
  so `GIT_SEQUENCE_EDITOR=true` (accept the todo as-is) is all you need — no `sed`, no hand-edit.
- **REORDER / SPLIT / DROP specific commits** — when autosquash isn't enough, script the todo
  list. `GIT_SEQUENCE_EDITOR` is fed the todo file as `$1`; write the file you want and copy it
  in. `GIT_EDITOR` supplies any reword messages. Note `git rebase --no-gpg-sign` IS a valid flag
  (it countermands `commit.gpgsign` for the rebase):
  ```
  printf 'pick %s\npick %s\n' <sha-B> <sha-A> > /tmp/todo   # e.g. swap order
  GIT_SEQUENCE_EDITOR='cp /tmp/todo' GIT_EDITOR='cp /tmp/msg' \
    git rebase -i --no-gpg-sign $MB
  ```
  Never run a BARE `git rebase -i` — with no editor it blocks forever.
- **Stacked topic branches** (T1 → T2 → T3 from Step 3's ordered decomposition): rebase the
  base with `git rebase --update-refs <base>` so every intermediate branch tip advances
  automatically. Without it, T2/T3 stay pinned at stale SHAs and you fix them by hand.
- **Branch contains merge commits you want to keep**: `git rebase --rebase-merges` preserves
  the merge topology; a plain rebase flattens it.
- Or build each topic as a single net-diff commit from the start (Step 4B) and never squash.
- Commit messages are rationale-rich: what changed, WHY, what upstream API it aligns to,
  what was dropped/folded. The message is the only durable record of the replay decisions.

---

## Step 8 — Close out: the refactor is NOT done until the tree is clean

A refactor that leaves orphan worktrees, dirty trees, or unexplained branches is INCOMPLETE —
no matter how good the code is. "Done" means: someone (usually future-you) can run
`git worktree list` and `git branch` and understand every single entry, OR there is nothing
left to understand. This repo accumulated 80 worktrees — 24 with abandoned uncommitted edits,
18 on already-merged branches — because this step kept getting skipped. Do NOT add to it.

### The load-bearing insight: a BRANCH or TAG preserves code; a WORKTREE never needs to
A worktree is just a checked-out directory. Removing it loses NOTHING as long as a branch or
tag points at the commits. "We might want this code back later" is NOT a reason to keep a
worktree — it is a reason to keep a *branch or tag* and remove the *directory*. Keeping code
≠ keeping a working directory. This one distinction collapses 80 worktrees into a handful of
named, explained branches.

### Disposition — every branch and worktree you created gets EXACTLY ONE outcome
| outcome | when | action |
|---------|------|--------|
| MERGED | work landed on the target | `git worktree remove <wt>`; then `git branch -d <br>` (lowercase `-d` deletes only if merged — a refusal means it is NOT actually merged; investigate, don't `-D` blindly) |
| DELETE | dead end / superseded / scratch / a bisect or baseline probe | confirm nothing unmerged is worth keeping, then `git worktree remove <wt>` + `git branch -D <br>` |
| PARK (abandoned-but-wanted) | code we genuinely want to return to | (1) COMMIT everything — no dirty tree; (2) **make a ref point at the tip** (this is what keeps the commits reachable — ONE ref is enough): if already on a branch, it anchors the tip; if on a DETACHED HEAD, `git switch -c wip/<name>` FIRST (else step 5 orphans the commits — see warning below); (3) mark it parked: `git tag -a parked/<name> -m "<why>"` (annotated). Keep the tag name DISTINCT from any branch name (`wip/<name>` branch vs `parked/<name>` tag) — a branch and tag sharing a string makes `git rev-parse` ambiguous; (4) file a bd issue: what's in it, WHY parked, and the TRIGGER that would make us return; (5) `git worktree remove <wt>`. The ref + bd issue preserve the work; the directory goes. |

There is no fourth outcome. "Leave it for now" is how the graveyard formed — it is forbidden.

> **Orphan-commit warning (the silent-loss footgun):** a worktree on a DETACHED HEAD has commits
> that NO branch or tag references. `git worktree remove` happily deletes such a worktree, and its
> tip then becomes unreachable — `git gc` collects it after the grace window (weeks), so the loss
> is silent and delayed. ALWAYS attach a branch (`git switch -c`) or tag to a detached-HEAD tip
> BEFORE removing the worktree, unless you are certain (DELETE outcome) you want those commits gone.
> Recover an already-orphaned tip with `git reflog` or `git fsck --lost-found` (only within the gc window).

### No dirty tree may be abandoned, ever
Before removing or parking: `git -C <wt> status --porcelain` MUST be empty. Uncommitted edits
are either worth keeping (commit them to the branch) or not (`git restore` / discard them) —
you decide NOW, while you still know what they were. `git worktree remove` REFUSES a dirty
tree; that refusal is the system protecting you. Read what's there and resolve it — do NOT
`--force` past it. An abandoned dirty worktree is the single worst artifact: months later
nobody can tell whether those edits were a fix or a false start.

### Probe worktrees die in the session that birthed them
`bisect-*`, `baseline-*`, `upstream-bench`, detached-HEAD comparison checkouts — single-use.
The moment the number/answer is recorded in bd or kb, `git worktree remove` it. Never let a
probe outlive its question.

### Completion gate — run this and act on it before you say "done"
```
git worktree prune                    # clear admin entries for dirs already gone
git worktree list                     # every entry must be: main, a long-lived tracked
                                      # branch, or a PARKED one that has a bd issue
git branch --no-merged master         # each must be PARKED (tagged + bd issue) or deleted
git -C <each wt you made> status --porcelain   # all empty
```
Note: `git branch -d` checks "merged" against the branch's upstream, or HEAD if none — NOT
necessarily `master`. Run the delete from the main worktree on master (or after confirming the
branch is reachable from master via the `--no-merged master` check above); a `-d` refusal there
means genuinely-unmerged, so investigate rather than reaching for `-D`. (Rare case — you
deliberately keep a worktree on a sometimes-absent mount: `git worktree lock --reason "..."` so
`prune` won't reap its admin dir. Step 8's default is still to remove, not keep.)

The refactor is complete only when: every worktree you created is removed or parked-with-a-bd-issue,
no branch you created is both unmerged AND unexplained, and no tree you touched is dirty. Your
completion report MUST end with the disposition list — one line per created artifact and its outcome.

---

## Plan & track (multi-phase → bd epic, always reviewed)

This work trips every epic trigger (3+ phases, 5+ files, spans sessions). So:

1. Write `~/.claude/plans/PLAN-<slug>.md` — include "Files read in full:", the merge-base SHA,
   the topic decomposition (by compilation-unit), the per-topic mechanism (Step 4 A/B/C/D),
   the drop/fold/keep audit (Step 2), and a `## Follow-ups (in bd)` section where EVERY
   deferred item already has a real bd-ID.
2. `bd create --type=epic --title="..." --design-file=~/.claude/plans/PLAN-<slug>.md`
3. `Task(subagent_type="expert-review", prompt="FULL REVIEW: epic=<id> plan=<path> project_root=<path>")`
4. APPROVED → work the topics in dependency order; one bd task per topic.
5. `kb add` a discovery note per topic (cherry-picked vs reimplemented, conflicts, API deltas).
6. Verify with `implementation-review`, then `bd close`.

## Recovery cheatsheet

| situation | recovery |
|-----------|----------|
| botched a topic branch | `git switch <upstream-target> && git branch -D topic/<x>`; restart from the anchor |
| just-ran rebase/merge/reset went wrong | `git reset --soft ORIG_HEAD` — git writes ORIG_HEAD to the pre-op tip automatically (free undo, no anchor needed). NOTE: ORIG_HEAD is written by rebase/merge/reset only — NOT by `apply`/`cherry-pick`/`am`; for those use `git reflog` |
| lost a commit | `git reflog` → `git cherry-pick <sha>` |
| `apply --3way` left `.rej` | hand-merge each `.rej`; never stage a tree with `.rej` files in it |
| upstream moved mid-task | FREEZE the fetched upstream snapshot; don't re-fetch until validation passes |
| "where was the good state?" | the Step-0 anchor tag: `git rev-parse pre-<task>-<date>^{commit}` |

Recovery ALWAYS uses `git reset --soft <ref>`, `git checkout <ref> -- <file>`, or `git switch` —
**never** `git reset --hard`. The soft/checkout forms cannot lose uncommitted work; `--hard` can.

## Anti-patterns (STOP if you catch yourself)

- Reading diff hunks instead of the WHOLE file on both sides → you miss the interaction
  surface (sibling helpers, shared struct fields, guarding asserts). Root cause #1 (Foundational rule 1).
- Editing a symbol without enumerating its callers/callees via ast-grep → link-time or
  runtime surprise that text-grep never showed you (Foundational rule 2).
- Decomposing topics by subject matter → cascading cherry-pick conflicts (Step 3).
- `git rebase --onto` across hot files upstream rewrote → 6–8× re-resolution (Step 4B).
- Resolving a big collision before checking if it's even consumed (Step 5).
- Replaying docs/research/revert-noise commits (Step 2).
- Skipping Step 0 because "it's a small change" — it never is.
- `git add .` then commit — stages generated files and unrelated churn.
- Deferring follow-ups as free text instead of bd issues.
- Declaring "done" with worktrees/branches you created still lying around (Step 8) — the task
  is not finished until the tree is clean.
- Keeping a WORKTREE because "the code might be useful" — keep a tagged BRANCH and a bd issue;
  remove the directory. A worktree never preserves anything a branch/tag doesn't.
- Abandoning a dirty worktree (`--force`-removing or just walking away) — resolve the
  uncommitted edits now, while you still know what they are.
- Leaving a `bisect-*` / `baseline-*` / `*-bench` probe worktree after it answered its question.
