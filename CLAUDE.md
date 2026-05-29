# Global Development Rules

---

# STANDING USER ORDERS

1. READ any file IN FULL. Do not use grep or equivalents. Hooks will block it.
2. "I should read..." is an anti-pattern. I expect you to READ before reporting.
3. DO NOT simply append to any file. READ THE FILE IN FULL and figure out where your contribution belongs.
4. RESEARCH first. This project is long-running and comprehensive. kb-research is waiting for your instructions. If it times out or fails, ask for help or suggest fixes.
5. SURFACE confusion, contradictions, and architectural anti-patterns. If the code seems messy, propose to fix it. Don't wait for the user to ask. Ask other agents on the bridge and surface your questions, confusion, and doubts in every turn.
6. You MUST be on the bridge. Run `~/.agent-bridge/bridge watch <handle>` with run_in_background=True after EVERY turn (hook enforced) this is your async notification mechanism for instructions and answers to questions from other agents. Adding a & and chaining it with other commands is NOT equivalent. A process exiting is your notification mechanism of another agent's message. This is an async notification mechanism and you must run this EXACTLY as instructed.

# Planning and Review (Beads-Based)

Plans live in `~/.claude/plans/PLAN-<slug>.md` and are referenced from beads epics via `--design-file`.

## Planning Workflow

```
1. Plan:    Write ~/.claude/plans/PLAN-<slug>.md
2. Epic:    bd create --type=epic --title="Plan: X" --design-file=~/.claude/plans/PLAN-<slug>.md
3. Review:  Task(subagent_type="expert-review", prompt="FULL REVIEW: epic=<id> plan=<path> project_root=<path>")
4. Verdict: APPROVED → proceed; REJECTED → revise, re-run
5. Work:    bd create --type=task --parent=<epic-id>; bd update <task-id> --claim
6. Verify:  Task(subagent_type="implementation-review", prompt="epic=<epic-id> project_root=<path>")
7. Close:   bd close <epic-id> <task-ids...>
8. Commit:  git add <files> && git commit --no-gpg-sign
```

## Epic Trigger

Create a beads epic if: 3+ phases, 5+ files, work spans compaction, or multi-session. Agent team when 2+ independent phases.

## Tiered Review

| Tier | When | Invocation |
|------|------|------------|
| **Full** | Plans/epics, architectural decisions | `Task(subagent_type="expert-review", prompt="FULL REVIEW: ...")` |
| **Light** | Issue triage, priority changes | `Task(subagent_type="expert-review", model="sonnet", prompt="LIGHT REVIEW: ...")` |
| **None** | Creating issues, KB, reading | Just do it |

Reviews are non-persistent. Do NOT use ExitPlanMode, `.approved` markers, or `Mode:` fields.

## Follow-up Discipline (no orphan deferrals)

Plans frequently defer work as "Out of scope" / "Follow-up" / "Deferred to a future epic." That category is **write-only by default**: it goes into plan text, the plan ships, and nothing in the workflow ever reads it again. Sessions end, /dispatch closes the epic, the deferred work vanishes from awareness. This is a systematic failure mode — pieces deferred this way are repeatedly the load-bearing fix that gets rediscovered only after multiple symptom-patching attempts.

**Rule**: every deferred / follow-up / out-of-scope item in a plan MUST be a real `bd` issue, created BEFORE the plan is submitted for review, with `--deps=discovered-from:<this-epic-id>`. The plan refers to follow-ups by bd-ID, never by free text.

Plan section format:
```
## Follow-ups (in bd)

- llamacpp-abcd: Sync mmvq.cu to upstream — discovered while removing TMAC
- llamacpp-efgh: Audit Nemekath cherry inventory — surfaced during TMAC scope work
```

Never:
```
## Out of scope
- Sync mmvq.cu to upstream: deferred to follow-up epic.   ← FORBIDDEN, no bd-ID
```

A bd-ID makes the work first-class: `bd ready` will surface it in future sessions, `bd list --status=open` keeps it visible, `discovered-from` links it back to its parent epic.

**Reviewer obligation**: expert-review REJECTS any plan with a "Follow-up" / "Out of scope" / "Deferred" reference that lacks a `bd-XXX` / `<project>-XXXX` ID in the same line or the line immediately below. The plan author must create the bd issue first, then re-submit.

**Dispatch obligation**: at epic completion, /dispatch runs `bd list --json | jq` to surface any open issues with `discovered-from:<this-epic>` and lists them in the completion report with explicit "next-step suggestions."

**Session-start obligation**: every new session surfaces open follow-ups from epics closed in the last 30 days, so they cannot fall off the radar between sessions.

A hook enforces the bd-ID requirement on `Write` to `~/.claude/plans/PLAN-*.md` (see `~/.claude/hooks/block-followup-without-bd-id.sh`).

## Mathlib Fork Survey Discipline

Plans citing Mathlib lemmas must include: `## Mathlib fork survey / - loogle 'LemmaName': found at X.lean:NNN`. Use loogle at `~/Physics/loogle/` (port 8088). Bare grep is fallback. Search WHOLE `~/Physics/mathlib4/Mathlib/` tree; try variant forms before declaring gap.

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

**Subagent rules**:
- Review agents: `run_in_background=True`
- Never pass `max_turns`; use STOPPING CONDITIONS instead
- Every prompt starts with `Read ~/.claude/agents/preamble.md FIRST`
- Include `~/.local/bin/kb add before returning` in every agent prompt
- Model defaults: Haiku lookups only; Sonnet implementation; Opus lead only (max 1/batch)
- **VERIFY AGENT WORK**: Read what agents claim. Summaries describe intent, not what landed.
- **AGENTS MUST READ, NOT GREP**: `grep sorry` matches comments; only Read disambiguates.
- **HOOKS DO NOT FIRE FOR SUBAGENTS**: all PreToolUse hooks (block-text-search, block-approximations, etc.) only fire in the parent session. Agents can bypass them silently. Mitigations: (1) for Lean sorry/axiom counts, agents MUST use `lean-audit <path>` (not grep); (2) for source search, agents should use `ast-grep` or `Read`; (3) include explicit anti-pattern warnings in every agent prompt.

**Agent preamble**: `"CRITICAL: the naive implementation would be X — do NOT do that. Required: Y."`

### Worktree Isolation

`isolation: "worktree"` is AUTO-DELETED when agent completes. Changes are LOST. Only use for read-only exploration. For implementation: work in main tree or `git worktree add .worktrees/<name>`.

### Scope Rules

3+ parallel Opus agents: FORBIDDEN. Agent >10 min: likely stuck, kill. Agent reads >10 files without KB entry: scope too broad, kill. Mixed compute+theory prompt: SPLIT.

## Concurrent Edit Detection

**Before every Edit/Write**: `git diff -- path/to/file.ext`. If changes you didn't make: **STOP** — concurrent edit detected, do NOT overwrite.

---

# Rules

**Hook blocks are FINAL.** If a hook blocks your tool call (exit 2), STOP. Do not rephrase or use a different tool. Tell the user.

## Read Before You Write

If you cite, reference, or depend on a file/theorem/function, you MUST have READ it first. No exceptions. If reading X would help, READ X — do not ask the user for permission.

**Checklist before any plan / review / dispatch prompt**:
- [ ] Every cited theorem / function / module → Read its definition (not just name)
- [ ] Every Mathlib lemma → survey the fork first (loogle)
- [ ] Every file path cited as "existing" → `ls` + Read confirms
- [ ] Every "this covers Y" claim → Read the file; verify

**Enforcement**: any plan/review/dispatch lacking a "Files read in full:" preamble is incomplete. expert-review rejects on sight.

Before implementing any new function: search codebase for similar names. USE existing code instead of reimplementing.

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
No mocks, stubs, or fake data.

No backwards compatibility. No wrappers. No forwarding functions. No aliases. No dead code. DELETE wrong/superseded code — git history preserves it.

No `git add -A`, `git add .`, `git reset --hard`, `git push --force`.

## Decision Authority

**You decide, then do it**: writing code, running tests, searching, recording KB. No "Should I proceed?"

**User decides**: claiming tasks, research direction, architectural choices with multiple valid options. Use `AskUserQuestion`. NEVER: "What would you like...", "Would you like me to...", "Should I..."

## Anti-Patterns

| If you write... | STOP because... |
|-----------------|-----------------|
| `I believe` / `This likely` / `This probably` | Speculation. Run code, verify. |
| Box-drawing table (┌┬┐├┼┤└┴┘│─) | NEVER. Use dashes + spaces only. |
| "promising" / "straightforward" / "just needs" | SHALLOW ASSESSMENT without reading code. |
| "Verify X covers Y" / "Assuming X exists" | DEFERRED READ. Read first, then write. |
| "Want me to look at X?" / "Should I check Z?" | DELEGATED READING. If reading helps, READ. |
| Hook blocks, then rephrasing/splitting | Hook blocks are FINAL. STOP. |
| Blending contradictory patterns | CONFLICT AVERAGING. Pick one, justify, flag other. |
| `kb search -p <one-project>` as first query | CROSS-PROJECT BLINDNESS. First search always unfiltered. |
| Agent claims "axiom X retired by reusing template Y" | LABEL-MATCH MISTAKE. Read X's *statement*. Similar names ≠ same content. |
| Test asserts *something* (truthy, non-null, has key) | INTENT-FREE TEST. Assert the *correct* value for a *stated reason*. |
| Haiku survey changes axiom count or scope | OUT-OF-SCOPE MODEL. Haiku for true lookups only; scope changes need Sonnet+. |
| "try candidates A, B, C and pick whichever matches" | DFR VIOLATION. Derive via ONE chain, compute ONCE, compare. |
| Starting epic without expert-review | ALL epics get expert-review first. No exceptions. |
| `Task(..., max_turns=N, ...)` | Use STOPPING CONDITIONS instead. |
| Dispatching agents to implement from long conversation | State key constraint first: "naive impl = X, DO NOT do that." |
| Reviewing a plan by reading plan doc + code without first searching `proofs.md` | LEAN-BLIND REVIEW. The plan's premise may be superseded by a Lean theorem (operator origin, coupling constant, interaction order). A review that doesn't check Lean can approve a plan whose foundation is already proven wrong — or already proven right. |
| Analyzing operator structure by reading Python source first | LEAN-BLIND ANALYSIS. The operator's origin, coupling value, and algebraic identity are axiomatized in Lean. Python implements; Lean proves. Check Lean first. |
| Enumerating migration surface or refactor scope via `rg "X.method"` alone | GREP-BLIND AUDIT. Read affected files + upstream callers + downstream callees IN FULL first. For code-shape queries use `ast-grep --lang <lang> '<AST pattern>'`, not `rg`. Text-grep is for literal strings only. Sibling helpers using different APIs are invisible to text-grep but reachable from the same entry point — they ship as deadlocks. |
| `may already say` / `probably already covered` / `I think the doc has` / `the test likely covers` / `that function probably handles` | UNVERIFIED-COVERAGE HEDGE. The hedge proves you didn't Read. STOP and Read the relevant sections / files in full before making the claim. Hedges generalize beyond docs — they also appear when speculating about test coverage, function behavior, or call-graph reachability without verification. Hedge = STOP signal, not a softener you ship. |
| Citing a Mathlib lemma by file:line without `grep`-ing `~/Physics/mathlib4/` first | HALLUCINATED CITATION. Survey the fork first (see Mathlib Fork Survey Discipline above). |
| Symbol k (or any symbol) used for two different quantities in same plan/message | NOTATION CONFLICT. Declare a Notation section first when >2 algebraic quantities are in play. |
| Plan contradicts CLAUDE.md convention | CLAUDE.MD WINS. Surface the contradiction to dispatcher; do NOT silently propagate the plan's version. |
| `next session` / `for tonight` / `pick this up later` / `tomorrow` / `call it a day` / `wrap up for now` | UNPROMPTED DEFERRAL. Do not propose stopping. Compaction is a checkpoint, not a stop. The user decides when to stop; you do not propose it. If you have unfinished work, continue it. |
| `since context is low` / `running low on context` / `context is getting tight` / `to save context` | CONTEXT-AS-EXCUSE. Low context is a `~/.local/bin/kb add` trigger (checkpoint your progress, then continue), not a stop signal. The harness handles compaction; you handle the work. |
| `good stopping point` / `natural place to pause` / `good place to break` | PERFORMATIVE PAUSE. Stopping points are user-determined, not Claude-determined. Continue working. |
| `Want me to continue?` / `Should I keep going?` (asked when work is unfinished and user hasn't paused you) | PROMPTING FOR PERMISSION TO WORK. The user already asked for the work. Do it. Reserve AskUserQuestion for genuine forks where the answer changes WHAT you do, not WHETHER you proceed. |

## Don't propose pauses

Do not propose stopping. Do not say "next session," "for tonight," "since context is low," "good stopping point," "we can pick this up later," or similar. These are unprompted deferrals and they subvert the user's workflow.

- **Compaction is a checkpoint, not a stop.** When context compacts, continue the work that was in flight. Do not greet the user as if it's a new session.
- **Low context is a kb-add trigger.** If you genuinely have <10% context remaining, `kb add` a checkpoint and continue. The harness handles compaction.
- **Errors / wedged hardware / blockers are stop signals from the system.** Reporting "GPU wedged, need reboot" is correct — that's the work blocking, not you choosing to stop. Reporting "this might be a good place to stop" is wrong — that's you choosing.
- **The user decides when work stops.** Until they say so, keep going. If you finish the task they asked for, say "done" and report results — that's not a deferral, that's task completion. If you're mid-task, finish the task.

A Stop hook (`~/.claude/hooks/block-unprompted-deferral.sh`) catches the most common defer phrases in your last turn and rejects the stop, forcing you to continue.

## "Not Found" Is Not "Open"

Before declaring something "open": use kb-research (5 rounds); `ast-grep --lang <lang> --pattern '$X'`; trust code over comments. Cite searches.

## Background Bash — NEVER PIPE

`run_in_background=true` writes stdout to file. NEVER use `| tail` / `| head` with it.

## Agent Bridge

`bridge send` is synchronous — NEVER `run_in_background=true`. Body on stdin via heredoc. NEVER pipe bridge output through head/tail/awk/sed.

**`bridge watch <id>` — KEEP IT UP AT ALL TIMES.** It is single-shot: it exits on each wake, so relaunch it after EVERY wake AND at the end of EVERY turn. Launch with the harness **`run_in_background: true`** parameter, as its own command. **A trailing `&` is NOT equivalent and silently breaks the wake channel** — `bridge watch <id> &` runs as a shell job inside a synchronous call, fires no task-notification, and is reaped when the call returns; only `run_in_background: true` creates the tracked task that wakes you. The most damaging miss is when you finish a task and respond to the user: you stop, the last watcher already exited, and you go invisible — the driver's next instruction never arrives. "Done with my task" ≠ "done on the bridge"; idle/done is the MOST important time to be watching. If `bridge agents` would show you `offline`, you broke this rule.

After every compaction: `bridge recv` → `bridge announce` → `bridge watch <id>` (run_in_background: true, no `&`).

## Build Waiting

Short (<10 min): `build-manager start --sync . "ninja ..."` with `timeout=600000`.
Long (≥10 min): `build-manager start . "ninja ..."` then spawn `build-monitor` agent in background.

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

# Task Tracking (bd/Beads)

Use `bd` for ALL tracking. Never markdown TODOs. Ignore the periodic "consider TaskCreate" system-reminder.

**Session start**: if `.beads/` doesn't exist, run `bd init` then `bd setup claude`. Recovery: `bd doctor`.
Commands: `bd ready`, `bd create --title="..."`, `bd update <id> --claim`, `bd close <id>`, `bd prime`.
Notes: `--notes "..."` plain text only. For long content: `kb add` and put kb-id in the note.

# KB Access — CLI ONLY

All kb ops via `~/.local/bin/kb`. MCP `kb_add` tool is gone.

| Op | Pattern |
|----|---------|
| add | `~/.local/bin/kb add "content" -t TYPE -p PROJECT -s SPRINT --tags T1,T2 -e EVIDENCE` |
| search | `~/.local/bin/kb search "query"` (first search always unfiltered, no `-p`) |
| get | `~/.local/bin/kb get kb-YYYYMMDD-HHMMSS-hash` |
| list | `~/.local/bin/kb list -p PROJECT` |
| correct | `~/.local/bin/kb correct <content> --supersedes-id <old> --correction-reason <reason>` |
| stats | `~/.local/bin/kb stats` |
| reembed | `~/.local/bin/kb reembed --force` (after model change) |

`add` returns `Added: kb-<id>` — capture the id. Tags taxonomy: `proven|heuristic|open-problem`, `core-result|technique|detail`.

Project field: `algebraic-genesis` (canonical), or `secular-constraints` / `claude` for repo-specific.

**kb-down fallback**: `~/.claude/pending-kb-adds/<UTC>-<session>.txt` with `# type:`, `# project:`, `# tags:` header; `kb flush-pending` drains. NEVER fall back to `.md`.

# Jupyter Notebooks

No markdown cells, no `# comments`, no docstrings, no print labels. Use for numeric checks, SageMath/SymPy algebra, plots.

# Output Discipline

Tables > prose. Bullets > paragraphs. No "I'll now..." / "Let me..." / "Successfully".
Table format: dashes + spaces only. NEVER box-drawing characters.
Notation discipline: >2 algebraic quantities → declare Notation section first.

# Hooks

Hooks intercept tool calls. **Hook blocks are FINAL.** Each prints an actionable error with the correct alternative tool/approach. If you hit a hook not documented here, surface it to the user.

| Hook | Trigger | Escape route |
|------|---------|--------------|
| **block-text-search-on-source** | `grep`/`rg`/`find`/`awk`/`sed` on source files (.py, .lean, .md, etc.) | Python: `ast-grep --lang python --pattern '$X'`. Lean: `lean-audit <path>` (sorry/axiom counts), `loogle 'Qualified.Name'` (built-decl/type search), or `lean-search NAME`/`-u NAME`/`-i MODULE` (ALLOWED source-level locate/usages/importers — for unbuilt/sorry files or unknown qualified name). Markdown: `ast-grep -c ~/.config/ast-grep/sgconfig.yml --lang markdown ...`. Or use the `Read` tool. |
| **block-markdown-via-bash** / **block-markdown-files** | Bash/Write creating new `.md` file | Route per ".md Creation Is Blocked" section below. |
| **block-print-spam** | ≥3 banner/narration echo/print lines in one Bash call | Strip all banners. Do NOT split into multiple calls. |
| **block-large-heredoc** | Heredoc body >30 lines to interpreter | Write to script file, then execute. |
| **block-approximations** | `for b in range(`, `curve_fit`, `polyfit`, `lstsq`, bare exponential mode sums | Use `cl44.generating_functional` or `cl44.spectral_zeta`. Exact computation only. |

## ast-grep gotcha — empty result is NOT "absent"

`ast-grep` matches the AST **structurally**, so a pattern silently MISSES any node carrying a child the pattern omits → **false negatives**. An empty `ast-grep` result does NOT prove a symbol is absent, and trusting it risks a duplicate reimplementation (the "research before implementing" failure mode).

- **Return annotations break the def pattern**: `def $F($$$): $$$` does NOT match a function with a return type — `def f(...) -> T:` has a `return_type` child the pattern has no slot for. Verified: `def fermion_masses($$$): $$$` → empty, though the function exists as `def fermion_masses(...) -> dict:`; `def $F($$$) -> $R: $$$` matches it. This codebase annotates returns heavily, so the plain pattern misses many defs.
- **Robust def-search**: run BOTH `def $F($$$): $$$` and `def $F($$$) -> $R: $$$`, or locate a known name with `python3 -c "import inspect; from <mod> import <f>; print(inspect.getsourcelines(<f>)[1])"`. Never conclude "not found / no prior art" from a single empty plain-def `ast-grep`.

## Lean Audit — `lean-audit`

`lean-audit <file-or-dir>` is the ONLY correct way to count sorry/axiom in Lean files. It parses comments (nested `/- -/`, `--`) and only flags code-level occurrences. `grep sorry` matches comment text and WILL give wrong counts — this has caused multiple wrong review verdicts.

```
lean-audit <file.lean>          # source scan + deep (#print axioms) if oleans exist
lean-audit <directory/>         # recursive, per-file
lean-audit <path> --json        # programmatic output
lean-audit <path> --no-deep     # skip #print axioms
lean-audit <path> --no-warnings # only sorry/axiom/:=True (no native_decide etc.)
```

Deep mode auto-enables when `.olean` exists for a file: runs `#print axioms` via `lake env lean --stdin` to catch `sorryAx` transitively (even through `opaque`). Output shows `[deep]` tag per file.

**Detects**: sorry, admit, axiom, := True, unsafeCoerce/Cast, implemented_by, native_decide, trustMe, trivial bodies, rfl-witness tautologies, type : True, ∃ _ True.

**Hooks do NOT fire for subagents.** All agent prompts needing sorry counts MUST say: `"Use lean-audit <path> to count sorries — do NOT use grep/rg on .lean files."`

# .md Creation Is Blocked

Hooks block new `.md` files. Route content:
- Finding / checkpoint / agent report → `~/.local/bin/kb add` or INLINE to dispatcher
- Plan (multi-phase) → `~/.claude/plans/PLAN-<slug>.md` (allowlisted)
- Task note → `bd update <id> --notes "..."`
- Architecture reference → Edit EXISTING `docs/reference/` doc
- Short summary → just write it in your reply

Existing `.md` Edit / `git mv` always OK.
