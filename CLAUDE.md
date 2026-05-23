# Global Development Rules

---

# Planning and Review (Beads-Based)

All plans live in `~/.claude/plans/PLAN-<slug>.md` files AND are referenced from beads epics via `--design-file`. No ExitPlanMode. No `Mode:` fields.

## Planning Workflow

```
1. Plan:    Write plan file: ~/.claude/plans/PLAN-<slug>.md
2. Epic:    bd create --type=epic --title="Plan: X" --design-file=~/.claude/plans/PLAN-<slug>.md
3. Review:  Task(subagent_type="expert-review", prompt="FULL REVIEW: epic=<id> plan=<path> project_root=<path>")  -- non-persistent
4. Verdict: APPROVED → proceed; REJECTED → revise plan, re-run review
5. Claim:   bd update <epic-id> --status=in_progress
6. Work:    bd create --type=task --parent=<epic-id> --title="Phase N: ..."; bd update <task-id> --claim
7. Verify:  Task(subagent_type="implementation-review", prompt="epic=<epic-id> project_root=<path>")  -- non-persistent
8. Close:   bd close <epic-id> <task-ids...>
9. Commit:  git add <files> && git commit --no-gpg-sign
```

## Epic Trigger (MANDATORY)

Create a beads epic with child tasks if ANY of these are true:
- 3+ implementation phases; 5+ files modified; work cannot complete before context compaction; multi-session coordination.

Use an agent team when 2+ phases are independent and touch different code sections.

## Pre-Response Self-Check (MANDATORY)

Before emitting any plan / bridge message / review verdict / agent dispatch prompt, answer YES to all five:

1. Did I run every required survey (Mathlib fork via loogle; theorem index; sibling CLAUDE.md)?
2. Did I declare every algebraic symbol I use (Notation section first if >2 quantities)?
3. Did I provide a derivation or citation for every quantitative claim?
4. Did I surface contradictions instead of papering them over (silent term-drop = papering)?
5. Did I re-read what I just wrote — does section A contradict section B in the SAME output?

## Mathlib Fork Survey Discipline

**Required preamble for every plan citing Mathlib lemmas** — auto-rejected by expert-review if missing: `## Mathlib fork survey / - grep -rn 'LemmaName' ~/Physics/mathlib4/Mathlib/: found at X.lean:NNN / - AnotherLemma: NOT FOUND`.

Survey rules: (a) bare grep, NO `^theorem|^lemma` anchor — misses `protected lemma`; (b) search the WHOLE `~/Physics/mathlib4/Mathlib/` tree — content splits across directories; (c) try variant forms (`det_pos`, `det_nonneg`) before concluding gap exists; (d) cite EXACT `file:line`. **Preferred**: loogle at `~/Physics/loogle/` — catches prefix misses AND directory splits. Bare grep is fallback.

## Tiered Review

"The first principle is that you must not fool yourself—and you are the easiest person to fool." (Feynman).

| Tier | When | Invocation |
|------|------|------------|
| **Full** | Plans/epics, architectural decisions | `Task(subagent_type="expert-review", prompt="FULL REVIEW: epic=<id> plan=<path> project_root=<path>")` |
| **Light** | Issue triage, priority changes, closing issues | `Task(subagent_type="expert-review", model="sonnet", prompt="LIGHT REVIEW: epic=<id> project_root=<path>")` |
| **None** | Creating issues, recording KB, reading/searching | Just do it |

**Reviews are ALWAYS non-persistent.** Use `Task(subagent_type="expert-review", ...)` directly — NEVER `bd mol wisp mol-expert-review`. Escalation: Depth 0 propose → 1 light review → 2 full review → 3 STOP, escalate to user. **Do NOT use**: ExitPlanMode, `.approved` marker files, `Mode: PLANNING/IMPLEMENTATION`.

## Session Management

**State lives in beads.** No handoff.md, no work_context.json.

**Resume**: `bd list --status=in_progress` → `bd show <epic-id>` → `~/.local/bin/kb list -p <project>`.

**Before context loss**: `~/.local/bin/kb add "SESSION CHECKPOINT: ..." -t discovery -p <project> --tags session-checkpoint`

**Persistent memory**: `~/.local/bin/kb add "insight" -t discovery -p <project> --tags <topic>`. Retrieve with `~/.local/bin/kb search "<keyword>"`. Do NOT use `bd remember` / `bd memories` and do NOT use MEMORY.md files.

## Why .md creation is blocked

`INVESTIGATION_*.md` / `*_AUDIT.md` files are unfindable after a few sessions. Hooks enforce. **Hook blocks are FINAL.** Route content:

- Finding / checkpoint / agent report → `~/.local/bin/kb add` or INLINE to dispatcher
- Plan (multi-phase) → `~/.claude/plans/PLAN-<slug>.md` (allowlisted)
- bd task note → `bd update <id> --notes "..."`
- Architecture reference → Edit EXISTING `docs/reference/` doc (do not create new)

**kb-down fallback**: `~/.claude/pending-kb-adds/<UTC>-<session>.txt` with `# type:`, `# project:`, `# tags:` header; `kb flush-pending` drains. NEVER fall back to .md. **Existing .md files**: Edit and `git mv` always OK.

## Agent Dispatch

**Default: answer yourself.** Agents parallelize, not outsource.

| Task Type | How to Handle |
|-----------|---------------|
| Reasoning / structural | Answer yourself |
| Symbolic algebra | Jupyter SageMath/SymPy |
| Numerical | Agent + scripts (Jupyter only if iterating) |
| KB / literature search | Haiku kb-research agent (5 rounds) |
| 3+ parallel streams | Agent Team |

**Subagent rules (MANDATORY)**:
- Review agents: `run_in_background=True`
- Never pass `max_turns`; use STOPPING CONDITIONS in prompt instead
- Every prompt: start with `Read ~/.claude/agents/preamble.md FIRST`
- Include `~/.local/bin/kb add before returning` in every agent prompt (CLI; the MCP `kb_add` tool was removed 2026-05-19)
- Structured JSON output with schema. For proof-work agents: split sorry counts into `axiomatized_phase_2b_targets` (intentional scaffolding) vs `accidental_sorrys` (real gaps) — headers reporting only total sorrys mislead reviewers.
- Model defaults: Haiku for true lookups only; Sonnet for implementation; Opus lead only (max 1/batch). **Haiku is FORBIDDEN** for dispatches that change scope, retire axioms, or alter critical path — use Sonnet or Opus.
- **VERIFY AGENT WORK (MANDATORY)**: Read whatever the agent claims — committed files, cited theorems, kb entries. Agent summaries describe intent, not what landed. Negative results must be re-checked; "feasible" often means label-matched, not statement-verified.
- **AGENTS MUST READ, NOT GREP**: audit/inventory prompts MUST instruct the agent to Read each file in full. `grep sorry` matches comments — only Read disambiguates proof obligations.

**Agent preamble**: `"CRITICAL: the naive implementation would be X — do NOT do that. Required: Y."` (agents have no conversation history)

### Worktree Isolation Rules (MANDATORY)

`isolation: "worktree"` is AUTO-DELETED when agent completes. Changes are LOST.

| Use case | Correct approach |
|----------|-----------------|
| Implement a feature | Work directly in main tree |
| Implement on a branch | `git checkout -b`, work in main tree |
| Parallel implementation | `git worktree add .worktrees/<name>`, no isolation param |
| Read-only exploration | `isolation: "worktree"` is OK |

**Cost of getting this wrong:** Agent work is lost. This has happened.

### Scope and Timeout Rules

| Rule | Action |
|------|--------|
| 3+ parallel Opus agents | FORBIDDEN |
| Agent running >10 min | Likely stuck. Kill. |
| Agent reads >10 files without KB entry | Scope too broad. Kill and answer yourself. |
| Mixed compute+theory prompt | SPLIT |
| No STOPPING CONDITIONS section | Add it |

## Concurrent Edit Detection (MANDATORY)

**Before every Edit/Write**: `git diff -- path/to/file.ext`. If changes you didn't make: **STOP**.

> **CONCURRENT EDIT DETECTED**: `path/to/file.ext` modified by another session. Do NOT silently overwrite.

**After every git commit**: `git status --short`. Warn if unexpected files are modified.

---

# Rules

**Hook blocks are FINAL.** If a hook blocks your tool call (exit 2), STOP. Do not rephrase, restructure, or use a different tool to do the same thing. Tell the user what was blocked and why.

## READ FILES IN FULL — NEVER DEFER READING (MANDATORY)

**If you cite, reference, or depend on a file/theorem/function in any output (plan, review, recommendation, scope assessment, agent dispatch prompt), you MUST have READ it in full FIRST.** No exceptions. Reading is not optional; it is a precondition to producing the output.

**Banned phrases** (each is proof you skipped reading or are delegating reading to the user): "Verify X covers Y", "I should read X", "Assuming X exists", "Pending verification of X", "If X is as described in the name...", "Want me to look at X?", "Want me to read X?", "Should I look at X?", "Do you want me to read/check/inspect X?". If reading X would help you answer, READ X — do not ask the user for permission first. If you would write any of these — STOP, read the file, then write.

**Checklist before any plan / review / dispatch prompt**:
- [ ] Every cited theorem / function / module → Read its definition; confirm signature (not just name)
- [ ] Every Mathlib lemma → survey the fork first (see Mathlib Fork Survey Discipline above)
- [ ] Every file path cited as "existing" → `ls` + Read confirms
- [ ] Every "this covers Y" claim → Read the file; verify (not label-matched)

**Enforcement**: any plan/review/dispatch lacking a "Files read in full:" preamble is incomplete. expert-review should reject on sight.

Before implementing ANY new function/struct/algorithm: `rg "similar_name"` across codebase; read *.md docs in directory; use Task/Explore agent if uncertain. USE existing code instead of reimplementing. This is your #1 failure mode.

**Any claim about what a file/codebase/doc/test "covers", "reaches", "handles", or "does" must come from Read, not grep.** `grep`/`rg` finds string matches; it does NOT find structural dependencies, semantic coverage, or prose that discusses a topic in different vocabulary than your search terms. Using text-grep to answer coverage/structure/behavior questions is a systematic Claude failure mode that spans code (call-graph reachability, migration scope), docs (whether topic X is covered), and tests (whether behavior Y is asserted).

Canonical workflow for any such claim:
1. **Identify the source of truth** — the file(s), section(s), or test(s) that would settle the claim.
2. **Read each in full** — not just matching lines. For code, recursively Read upstream callers (to public API boundary) and downstream callees (to std/syscalls/external), paying attention to indirect calls (trait methods, helper modules, callback registries). For docs, Read the TOC and every plausibly-related section. For tests, Read each test body, not just names.
3. **For breadth-after-Read on code, use `ast-grep`, not `rg`.** ast-grep matches AST patterns: `ast-grep --lang rust 'self.kernels.$_.forward($$$)'` finds code-shape queries text-grep misses. Use `rg` ONLY for literal strings — error messages, env-var names, file paths.
4. **Only AFTER full Read** can you `rg` — and only to confirm, not to construct.

Canonical code failure: `rg "X.execute"` audit finds 6 call sites to migrate; full Read reveals a sibling helper at the same entry point using `obj.kernels.*.forward` + `memcpy_d2h` — invisible to text-grep, deadlocks on first user run after migration ships.

Canonical doc failure: `grep "atomic_store_n SYSTEM"` returns no hits; full Read of "Persistent worker ack protocol" reveals the same hazard documented under different vocabulary. Edit recommended would have duplicated an existing rule, or contradicted it.

The cost of a 200-line Read is real; the cost of a shipped regression or a redundant/contradictory edit is higher.

No mocks, stubs, or fake data.

No backwards compatibility. No wrappers. No forwarding functions. No aliases. No dead code. DELETE wrong/superseded code — git history preserves it.

No `git add -A`, `git add .`, `git reset --hard`, `git push --force`.

## Decision Authority

**Level 1 — Light review decides**: closing issues, reprioritizing, declaring done/failed.

**Level 2 — You decide, then do it**: writing code, running tests, searching, recording KB. No "Should I proceed?" Scale detection: if >1 context window, create epic + team first.

**Level 3 — User decides**: claiming tasks, choosing research direction, architectural decisions with multiple valid options. Use `AskUserQuestion`. Never open-ended prompts.

NEVER: "What would you like...", "Would you like me to...", "Should I..."

# Anti-Patterns (key entries; hook-enforced entries removed)

| If you write... | STOP because... |
|-----------------|-----------------|
| `I believe` / `This likely` / `This probably` | Speculation. Run code, verify from data. |
| Box-drawing table (┌┬┐├┼┤└┴┘│─) | NEVER. Use dashes + spaces only. |
| "promising" / "straightforward" / "just needs" without reading implementation | SHALLOW ASSESSMENT. |
| "pending" / "untested" / "open question" without 3+ search strategies | "Not Found" ≠ "Open". Cite searches. |
| `kb search -p <one-project>` as first query | CROSS-PROJECT BLINDNESS. First search must be unfiltered (`kb search "query"` without `-p`). |
| Agent prompt without `Read preamble.md` | PREAMBLE MISSING. |
| `old_name = new_name` / RuntimeError stub | NO BACKWARDS COMPATIBILITY. Delete the old function. |
| Starting epic without expert-review | ALL epics get expert-review first. No exceptions. |
| `Task(..., max_turns=N, ...)` | Use STOPPING CONDITIONS instead. |
| Dispatching agents to implement from long conversation | State key constraint first: "naive impl = X, DO NOT do that." |
| Hook blocks tool call, then rephrasing/splitting | Hook blocks are FINAL. STOP. |
| Blending two contradictory patterns to satisfy both | CONFLICT AVERAGING. Pick one (newer/more tested), justify it, flag the other for cleanup. Don't satisfy both. |
| Test asserts function returned *something* (truthy, non-null, has key) | INTENT-FREE TEST. Assert the *correct* value for a *stated reason*. A test that can't fail when business logic changes is wrong. |
| Survey/research agent claims "axiom X can be retired by reusing template Y" | LABEL-MATCH MISTAKE. Read X's *statement* before dispatching implementation. Similar names ≠ same content. |
| Acting on a haiku-survey recommendation that changes axiom count, critical path, or implementation scope | OUT-OF-SCOPE MODEL. Haiku is for true lookups; load-bearing structural claims require Sonnet+. |
| Reviewing a plan by reading plan doc + code without first searching `proofs.md` | LEAN-BLIND REVIEW. The plan's premise may be superseded by a Lean theorem (operator origin, coupling constant, interaction order). A review that doesn't check Lean can approve a plan whose foundation is already proven wrong — or already proven right. |
| Analyzing operator structure by reading Python source first | LEAN-BLIND ANALYSIS. The operator's origin, coupling value, and algebraic identity are axiomatized in Lean. Python implements; Lean proves. Check Lean first. |
| Enumerating migration surface or refactor scope via `rg "X.method"` alone | GREP-BLIND AUDIT. Read affected files + upstream callers + downstream callees IN FULL first. For code-shape queries use `ast-grep --lang <lang> '<AST pattern>'`, not `rg`. Text-grep is for literal strings only. Sibling helpers using different APIs are invisible to text-grep but reachable from the same entry point — they ship as deadlocks. |
| `may already say` / `probably already covered` / `I think the doc has` / `the test likely covers` / `that function probably handles` | UNVERIFIED-COVERAGE HEDGE. The hedge proves you didn't Read. STOP and Read the relevant sections / files in full before making the claim. Hedges generalize beyond docs — they also appear when speculating about test coverage, function behavior, or call-graph reachability without verification. Hedge = STOP signal, not a softener you ship. |
| "Verify X covers Y" / "I should read X" / "Pending verification" / "Assuming X is..." in output | DEFERRED READ. See "READ FILES IN FULL" above. Reading is YOUR job, not the user's. Read first; THEN write. |
| "Want me to look at X?" / "Want me to read Y?" / "Should I check Z?" — asking permission to read | DELEGATED READING. If reading helps, READ. Don't ask. Same root cause as DEFERRED READ. |
| Citing a Mathlib lemma by file:line without `grep`-ing `~/Physics/mathlib4/` first | HALLUCINATED CITATION. Survey the fork first (see Mathlib Fork Survey Discipline above). |
| "try candidates A, B, C and pick whichever returns target" in a plan | DFR VIOLATION. Derive via ONE chain of identified principles, compute ONCE, compare. Best-of-N / numerology fires at plan-write time. |
| Symbol k (or any symbol) used for two different quantities in same plan/message | NOTATION CONFLICT. Declare a Notation section first when >2 algebraic quantities are in play. |
| Plan contradicts CLAUDE.md convention | CLAUDE.MD WINS. Surface the contradiction to dispatcher; do NOT silently propagate the plan's version. |

# Background Bash Output — NEVER PIPE

`run_in_background=true` writes stdout to a file. Shell pipes (`| tail`, `| head`) consume output BEFORE it reaches the file.

**Rule**: NEVER use `| tail` / `| head` in a Bash call with `run_in_background=true`. Run without pipe; read file afterward.

# Agent Bridge — Correct Usage

`bridge send` is synchronous — NEVER `run_in_background=true`. Body goes on stdin via heredoc (`bridge send all "subject" <<'EOF' ... EOF`), not as a quoted arg (exit 144 otherwise).

`bridge watch <id>` is a single-shot blocker — launch ONCE with `run_in_background=true`, relaunch after every wake. Check `ps aux | grep "bridge watch"` before launching.

After every compaction: `bridge recv` → `bridge announce` → `bridge watch <id>` in background. Ask peers "what did I miss?".

NEVER pipe `bridge recv`/`peek`/`tail`/`show` through `head`/`tail`/`awk`/`sed`. Read the FULL message.

**Bridge derivation discipline**: quantitative scaling claims include a 2-3 line derivation OR numerical-source citation. Bridge messages propagate fast — not exempt from derivation discipline.

# Build Waiting Protocol

Short builds (< 10 min): `build-manager start --sync . "ninja ..."` with `timeout=600000`.

Long builds (≥ 10 min): `build-manager start . "ninja ..."` then spawn `build-monitor` agent with `run_in_background=True`. Stop and wait for agent message.

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

# Task Tracking (bd/Beads)

Use `bd` for ALL task and plan tracking. Never use markdown TODOs.

**Session start**: if `.beads/` doesn't exist, run `bd init` then `bd setup claude`. Commands: `bd ready` (no-blocker work), `bd create --title="..."`, `bd update <id> --claim`, `bd close <id>`, `bd prime` (load context). Recovery: `bd doctor`.

**TaskCreate reminder**: the harness emits a periodic "consider TaskCreate" system-reminder; ignore it — `bd` is the only correct task tracker for this project family. Hook fix to suppress when `.beads/` exists is separate follow-up work.

**bd notes format**: `--notes "..."` plain text only. Hooks block heredocs >30 lines AND `.md` writes in `.beads/`. For long content: use `kb add` and put the kb-id in the note. Each `--notes` call replaces the prior.

# KB Access — CLI ONLY

**All kb operations go through the CLI** (`~/.local/bin/kb`). MCP `mcp__knowledge-base__kb_add` is gone — do NOT use it.

| Operation | Pattern |
|-----------|---------|
| kb add | `~/.local/bin/kb add "content" -t TYPE -p PROJECT -s SPRINT --tags T1,T2 -e EVIDENCE` |
| kb search | `~/.local/bin/kb search "query" -p PROJECT` (or spawn `kb-research` agent for 5-round search) |
| kb get | `~/.local/bin/kb get kb-YYYYMMDD-HHMMSS-hash` |
| kb list | `~/.local/bin/kb list -p PROJECT` |
| kb correct | `~/.local/bin/kb correct <new-content> --supersedes-id <old-id> --correction-reason <reason>` |
| kb stats | `~/.local/bin/kb stats` |
| kb reembed | `~/.local/bin/kb reembed --force` (full re-embed after model change) |

`add` returns `Added: kb-<YYYYMMDD>-<HHMMSS>-<hash>` — capture the id. Tags taxonomy: proven|heuristic|open-problem, core-result|technique|detail.

**Project field**: use `algebraic-genesis` (canonical), or `secular-constraints` / `claude` for repo-specific work. Do NOT invent new project namespaces.

# Jupyter Notebooks (Computation Only)

No markdown cells, no `# comments`, no docstrings, no print labels.

Check server: `query_notebook("test", "check_server", server_url="http://localhost:8888")`.

**When to use**: numeric checks, hypothesis exploration, SageMath/Maple algebra, plots. Scripts for reusable computation and CI tests.

# Output Discipline

**Truncation parameters**: Grep `head_limit=20`; Read `limit=100`; Glob `**/*.py` not `**/*`.

**Terseness**: Tables > prose. Bullets > paragraphs. No "I'll now..." / "Let me..." / "Successfully".

**Table format**: dashes + spaces only. NEVER box-drawing characters. Measure all content before rendering.

**Notation discipline**: any plan / bridge message / agent prompt with >2 algebraic quantities declares a Notation section first (symbol → meaning, one line each). Reuse of the same symbol for two different meanings without explicit redefinition is a hard error.

# Hooks (what blocks and why)

Hooks intercept tool calls before they run. **Hook blocks are FINAL** (see top of Rules). Each one prints an actionable error. This index documents them by name so you know what to expect BEFORE you waste a turn discovering them.

| Hook | Trigger | Escape route |
|------|---------|--------------|
| **block-text-search-on-source.sh** | `grep` / `rg` / `find` / `awk` / `sed` on `.py`, `.md`, `.lean`, etc. source files | Python: `ast-grep --lang python --pattern '$X'`. Lean: `loogle 'Name'` (port 8088). Markdown: `ast-grep -c ~/.config/ast-grep/sgconfig.yml --lang markdown ...`. For full-file inspection, use the `Read` tool. |
| **block-markdown-via-bash.sh** | Bash command that creates a new `.md` file (heredoc redirect, `cat > foo.md`, even `python3` script that writes a `.md` path) | Route by content type per "Why .md creation is blocked" above. Existing `.md` files: Edit and `git mv` always OK; the block only fires on NEW `.md` creation. Beware: even ARGUMENTS containing `.md` paths can trigger this (e.g. `diff a.md b.md` — use the `Read` tool to inspect the diff artifact instead, or run via a Python `subprocess` whose argv list doesn't appear in the command string the hook scans). |
| **block-print-spam.sh** | Shell script with banner/header `echo` lines (≥5 narrative prints in one Bash call) | Strip every banner / "=== section ===" header / step-narration `echo`. Numeric results, tables, structured data are fine. Do NOT split into multiple Bash calls to dodge the count. |
| **block-large-heredoc.sh** | Heredoc body >30 lines (especially in `bd update --notes`) | For long content: `kb add "..."` and put the kb-id in the bd note, or write a file and pipe via `cat file \| cmd`. |
| **block-md-creation** (in `.beads/`) | Any new `.md` file under `.beads/` | bd state lives in the SQLite DB, not in `.md`. Use `bd update --notes` or `kb add`. |
| **bridge-watcher-alive.sh** | UserPromptSubmit when no `bridge watch <agent-id>` is running in the background | Launch via Bash with `run_in_background=true`: `~/.agent-bridge/bridge watch <id>`. The watcher exits on each peer message — relaunch after every wake. Use `setsid nohup` + `disown` to detach from the Claude shell so it survives shell teardown. |
| **bridge-send-validation** | `bridge send` body passed as quoted arg, or `bridge send` invoked with `run_in_background=true` | `bridge send` is SYNCHRONOUS. Body goes on stdin via heredoc OR via `< /tmp/msg.txt` file pipe. See "Agent Bridge — Correct Usage" above. |
| **kb-precompact.sh** | PreCompact phase | Auto-flushes pending KB queue. Nothing to do. |
| **precompact-save-state.sh** | PreCompact phase | Auto-saves state. Nothing to do. |
| **session-start hooks** | SessionStart phase | Auto-load context (bd prime, lean LSP config, peer registry, recent KB, resume handoff). Nothing to do. |

**Discovery is failure.** If you hit a hook the first time, that's an instruction-surface bug — agents should know the rule BEFORE acting. If you hit one not listed above, surface it to the user so this table can be extended. Do NOT silently work around it.

# "Not Found" Is Not "Open"

Before declaring something "open": use kb-research (5 rounds); `ast-grep --lang <lang> --pattern '$X'` (not `rg` — see Hooks above); trust code over comments.
