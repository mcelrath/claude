# Global Development Rules (all projects)

This file is GLOBAL and must carry ZERO project-specific or ~/Physics content.
Project rules live in each repo's own `CLAUDE.md` — e.g. `~/Physics/secular-constraints/CLAUDE.md`
holds the Algebraic Genesis / Cl(4,4) / Lean / Mathlib specifics (canonical repos, object
catalog, Lean-proof workflow, Mathlib fork survey).

---

# STANDING USER ORDERS

1. READ any file IN FULL. Do not use grep or equivalents. Hooks will block it.
2. "I should read..." is an anti-pattern. I expect you to READ before reporting.
3. DO NOT simply append to any file. READ THE FILE IN FULL and figure out where your contribution belongs.
4. RESEARCH first. This project is long-running and comprehensive. kb-research is waiting for your instructions. If it times out or fails, ask for help or suggest fixes.
5. SURFACE confusion, contradictions, and architectural anti-patterns. If the code seems messy, propose to fix it. Don't wait for the user to ask. Surface your questions, confusion, and doubts in every turn.

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

## Session Management

**State lives in beads.** No handoff.md, no work_context.json.

**Resume**: `bd list --status=in_progress` → `bd show <epic-id>` → `~/.local/bin/kb list -p <project>`.

**Before context loss**: `~/.local/bin/kb add "SESSION CHECKPOINT: ..." -t discovery -p <project> --tags session-checkpoint`

**Persistent memory**: `~/.local/bin/kb add "insight" -t discovery -p <project> --tags <topic>`. Retrieve with `~/.local/bin/kb search "<keyword>"`. Do NOT use `bd remember` / `bd memories` and do NOT use MEMORY.md files.

## Bridge Reply Discipline

When sending a bridge message that requires a response, add `--needs-reply`:

```
bridge send <to> "<subject>" --needs-reply << 'EOF'
body
EOF
```

The Stop hook surfaces any unanswered `--needs-reply` messages as `BRIDGE_PENDING_REPLIES` before the session goes idle. Responders close the loop with `--reply <id>`. Check open items anytime with `bridge pending-replies`.

Receipt (`bridge ack`) ≠ reply — ack means "I read it", reply means "I responded to it".

**Inbound owed-reply tracker** (Stop hook `bridge-owed-reply-stop.py`): a peer message addressed to you with `needs_reply=true` that you have NOT answered (no `--reply <id>` from you) is an OWED REPLY. It is recomputed fresh from `~/.agent-bridge/messages.jsonl` every Stop — disk-derived, so it SURVIVES COMPACTION and re-surfaces until you `bridge send … --reply <id>`. With `BRIDGE_OWED_HARD_BLOCK=1` it BLOCKS idle until each owed reply is answered or consciously deferred (`echo "$(date +%s) <id> <why>" >> /tmp/claude-kb-state/owed-deferred`, re-blocks after 6h). This is what lets you defer a reply safely — you will not forget it.

## Work Queueing & Wake Discipline

Juggling 3+ peer/user requests, agents drop replies and thrash between tasks. The durable trackers (owed-reply above) make deferral safe — so do NOT flip-flop:

1. **WIP cap = 1 active, 2 max.** A second only when the first is genuinely blocked (waiting on a build / agent / reply). Beyond → queue, don't start.
2. **Interrupt vs. queue.** A new message interrupts current work ONLY if it (a) blocks the current task, (b) is a safety/HOLD broadcast on a resource in use, or (c) is sender-marked blocking/urgent. Otherwise: read to triage, queue, continue.
3. **Finish-or-park before switching** — complete the unit or leave a one-line park note so resuming is cheap.
4. **Service the queue at breaks, batched** — not by ping-ponging each turn.

**Wake discipline** (binds all agents):
- **Wake only when addressed.** Do not spend a turn on a watcher wake for a message not addressed to you (directed-to-others / `all` broadcasts). Relaunch the watcher and move on — no commentary.
- **No cross-agent narration.** Do not summarize to the user what OTHER agents are doing — the user sees every terminal; relaying peer activity is waste.
- **No self/infra-praise.** Never editorialize that the system works ("survived compaction", "working as intended", "the discipline paid off"). The user knows. Surface the system ONLY when it FAILS.

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
- Every prompt starts with `Read ~/.claude/agents/preamble.md FIRST` — and, when the project has one, `Read <project>/.claude/agents/preamble.md` too (project invariants live there, not global; e.g. `~/Physics/secular-constraints/.claude/agents/preamble.md` carries the Cl(4,4) HAM/canonical-function/centralizer rules)
- Include `~/.local/bin/kb add before returning` in every agent prompt
- Model defaults: Haiku lookups only; Sonnet implementation; Opus lead only (max 1/batch)
- **VERIFY AGENT WORK**: Read what agents claim. Summaries describe intent, not what landed.
- **AGENTS MUST READ, NOT GREP**: `grep sorry` matches comments; only Read disambiguates.
- **HOOKS FIRE FOR SUBAGENTS** (Claude Code v2.1.145+; verified empirically on 2.1.154, 2026-05-30 — a sub-agent's `grep file.py` and partial `Read` were both blocked by the parent's PreToolUse hooks). PreToolUse/PostToolUse hooks DO fire for sub-agent tool calls; the hook input carries an `agent_id` field (present only for sub-agents) so a hook can scope behavior per origin. block-text-search, block-approximations, read-coverage-gate, etc. ENFORCE on agents — agents do NOT bypass them. settings.json hot-reloads (new hooks fire without restart). (The old "hooks don't fire for subagents" belief was true on ≤ v2.1.76 — GitHub #34692 — and is now false.) Still correct practice: agents use `lean-audit` for sorry/axiom counts and `ast-grep` for source-shape search (the right tools; grep-on-source is blocked for agents too), and the read-coverage-gate forces agents to read WHOLE files (partial/slice reads blocked via the agent_id branch).

**Agent preamble**: `"CRITICAL: the naive implementation would be X — do NOT do that. Required: Y."`

### Worktree Isolation

`isolation: "worktree"` is AUTO-DELETED when agent completes. Changes are LOST. Only use for read-only exploration. For implementation: work in main tree or `git worktree add .worktrees/<name>`.

### Scope Rules

3+ parallel Opus agents: FORBIDDEN. Agent >10 min: likely stuck, kill. Agent reads >10 files without KB entry: scope too broad, kill. Mixed compute+theory prompt: SPLIT.

### Rate-limit recovery — auto-`continue` resumed agents

Subagents sometimes fail with `API Error: Server is temporarily limiting requests (not your usage limit) · Rate limited` — this is API-side throttling, not our quota. The agent returns with `status: completed` and a short result string containing "Rate limited", typically after only a handful of tool uses and well before doing real work.

**Always resume rather than re-dispatch.** A new `Agent()` call starts fresh with zero memory of the prior run. `SendMessage(to=<agentId>, message="continue …")` resumes the agent from its prior transcript with full context — claimed bd tasks, files already read, partial work — all preserved.

Pattern:
1. Detect: agent task-notification result string contains "Rate limited" / "rate limit" / "temporarily limiting requests"
2. Capture the agent's `agentId` from its original spawn result (`a...-...` format)
3. `SendMessage(to=<agentId>, message="continue — you were rate-limited; pick up where you left off. <one-sentence reminder of the task scope + plan/bd-id reference>. If you've lost context: <terse re-statement of mission>. Prefer fewer tool calls if rate-limits persist (batch shell ops with && chaining; read each file once).")`
4. Relaunch `bridge watch <handle>` per the Agent Bridge section
5. End your turn; the resumed agent runs in background and notifies when done

Do **not** re-dispatch via fresh `Agent()` for rate-limit failures — that loses any progress (bd task state, kb entries, partial code) the original agent made before the rate limit hit. Do re-dispatch if the failure is something OTHER than rate-limit (genuine error, agent gave up, etc.) — those are different failure modes.

If an agent hits rate-limit repeatedly (3+ resumes without forward progress), pause and decide: either (a) wait a longer cooldown (5-10 min) before the next resume, or (b) do the work yourself in the main session if it's discrete enough to fit. The main session has its own quota; subagent quota appears to be separately throttled.

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

No `git add -A`, `git add .`, `git reset --hard`, `git push --force`.

## Destructive git operations — confirm with the human first

`git stash drop`/`stash clear`, `reset --hard`/`--merge`, `clean -f`, `checkout -f`/`--force`, `switch --force`/`--discard-changes`, `worktree remove --force`, and whole-tree `checkout .`/`restore .` can ERASE uncommitted, stashed, or untracked work — content that is invisible to `git status` and unrecoverable past the gc window. A forensic audit of all sessions on this host found exactly one near-fatal data-loss incident, and it was this exact mechanism: a conflicted `git stash pop` "cleaned up" with `git checkout HEAD -- <files> && git stash drop` — destroying the ONLY copy of uncommitted work (recovered solely via `git fsck --dangling`).

- **NEVER `git stash drop`/`stash clear` until the matching `git stash pop` exited 0 with NO conflict markers.** On a conflicted pop: resolve it, or `git stash branch <name>` to materialize the stash safely — never drop.
- To set work aside, PREFER a throwaway commit (`git switch -c wip/<name> && git commit -am wip`) over `stash` — a commit is reachable and trivially recoverable; a dropped stash is not.
- `git reset --hard` stays forbidden — use `git reset --soft <ref>` (keeps your files) or `git restore --staged <path>`.
- Enforced by `guard-destructive-git.sh` (PreToolUse/Bash, per-command-segment token match): these verbs are BLOCKED unless you FIRST `AskUserQuestion` to confirm the specific discard with the human. That arms a 10-minute per-session bypass (`git-asked-gate.sh` on PostToolUse/AskUserQuestion). State exactly what will be lost — run `git status` / `git stash list` — before you ask.
- Recover an already-lost tip/stash within the gc window: `git reflog`, `git fsck --lost-found`, `git fsck --dangling`.

## Decision Authority

**You decide, then do it**: writing code, running tests, searching, recording KB, **committing completed work + closing its beads**. No "Should I proceed?"

**Commit + close completed work — ALWAYS, never ask.** The moment a unit of work is validated/complete (a green build of a finished feature, a passed soak), `git commit --no-gpg-sign` the specific files AND `bd close` its completed beads in the same motion, automatically. Do NOT ask "should I commit / bank this?" or present commit-and-close as an option — "bank" (commit + close completed beads, leaving genuine unfinished/design follow-ups as open bd issues) is the DEFAULT, not a decision to surface. Agents systematically leave completed beads open and skip committing — losing the audit trail and the on-disk checkpoint. Do not be one of them.

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
| Enumerating migration surface or refactor scope via `rg "X.method"` alone | GREP-BLIND AUDIT. Read affected files + upstream callers + downstream callees IN FULL first. For code-shape queries use `ast-grep --lang <lang> '<AST pattern>'`, not `rg`. Text-grep is for literal strings only. Sibling helpers using different APIs are invisible to text-grep but reachable from the same entry point — they ship as deadlocks. |
| `may already say` / `probably already covered` / `I think the doc has` / `the test likely covers` / `that function probably handles` | UNVERIFIED-COVERAGE HEDGE. The hedge proves you didn't Read. STOP and Read the relevant sections / files in full before making the claim. Hedges generalize beyond docs — they also appear when speculating about test coverage, function behavior, or call-graph reachability without verification. Hedge = STOP signal, not a softener you ship. |
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

## Build Waiting

Short (<10 min): `build-manager start --sync . "ninja ..."` with `timeout=600000`.
Long (≥10 min): `build-manager start . "ninja ..."` then spawn `build-monitor` agent in background.

# System

Arch. pacman/yay. Python 3.13. rg/fd. git --no-gpg-sign.

# Task Tracking (bd/Beads)

Use `bd` for ALL tracking. Never markdown TODOs. Ignore the periodic "consider TaskCreate" system-reminder.
Do NOT use `bd remember` / `bd memories` -- use `~/.local/bin/kb add` instead.
Do NOT use `bd edit` -- it opens `$EDITOR` and blocks agents.

**Session start**: if `.beads/` doesn't exist, run `bd init` then `bd setup claude`. Recovery: `bd doctor`.
**Session close**: before saying "done", run `git status` -> `git add <files>` -> `git commit` -> `git push`.

## bd commands

| Command | Purpose |
|---------|---------|
| `bd ready` | Show issues ready to work (no blockers) |
| `bd list --status=open` | List open issues |
| `bd list --status=in_progress` | List claimed issues |
| `bd show <id>` | Full issue detail with deps |
| `bd create --title="..." --description="..." --type=task|bug|feature|epic --priority=2` | New issue; priority 0-4 (0=critical, 2=medium, 4=backlog) -- NOT "high"/"low" |
| `bd update <id> --status=in_progress` | Claim work |
| `bd update <id> --assignee=name --title=... --notes=... --design=...` | Update fields |
| `bd close <id1> <id2> ...` | Close one or more issues |
| `bd close <id> --reason="..."` | Close with reason |
| `bd dep add <issue> <depends-on>` | Add dependency |
| `bd blocked` | Show all blocked issues |
| `bd search <query>` | Search issues |
| `bd dolt push` / `bd dolt pull` | Sync with remote |
| `bd stats` / `bd doctor` | Health check |

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
| **block-text-search-on-source** | `grep`/`rg`/`find`/`awk`/`sed` on source files (.py, .lean, .md, etc.) | Python: `ast-grep --lang python --pattern '$X'`. Lean: `lean-audit <path>` (sorry/axiom counts), `loogle '"substr"'` (name-substring) / `loogle 'Qualified.Name'` / type-search — these index DECLARATION names, NOT file/module names (and a file's name can differ from its namespace, e.g. `Two_PI_AllOrders.lean` ↔ `TwoPI_AllOrders`), so a file/module-name query returns EMPTY ("0 declarations" / `unknown identifier`) = a query-FORM signal, **NOT absence**. For FILE existence use `lean-search -f <Name>` (as of 2026-06-03 lean-search DOES index file/module names — matches stem, dotted `A.B.Foo`, or path `B/Foo`) or `fd`/`Read`; for MODULE importers use `lean-search -i <Module.Path>`; NEVER conclude "X doesn't exist/unbuilt/unverifiable" from an empty decl-search — and note `lean-search NAME` decl-mode now ALSO appends a "FILES matching" section, so an empty DECLARATIONS list with a non-empty FILES list means NAME is a module/file (present), NOT absent. (`lean-search NAME`/`-f NAME`/`-u NAME`/`-i MODULE` = ALLOWED source-level locate(decls+files)/files/usages/importers — for unbuilt/sorry files or unknown qualified name. And: lean-audit/build COUNT sorries/axioms but do NOT validate the STATEMENT — a sorry on a false/vacuous statement is a soundness hole they pass; READ the statement.) Markdown: `ast-grep -c ~/.config/ast-grep/sgconfig.yml --lang markdown ...`. Or use the `Read` tool. |
| **block-markdown-via-bash** / **block-markdown-files** | Bash/Write creating new `.md` file | Route per ".md Creation Is Blocked" section below. |
| **block-print-spam** | ≥3 banner/narration echo/print lines in one Bash call | Strip all banners. Do NOT split into multiple calls. |
| **block-large-heredoc** | Heredoc body >30 lines to interpreter | Write to script file, then execute. |
| **block-approximations** | `for b in range(`, `curve_fit`, `polyfit`, `lstsq`, bare exponential mode sums | Use `cl44.generating_functional` or `cl44.spectral_zeta`. Exact computation only. |
| **read-coverage-gate** | `Read` with `offset`/`limit` (partial read) of a source/doc file | **Sub-agents**: BLOCKED — read the WHOLE file (drop offset/limit; >2000-line files page top-down to EOF, no gaps — there are always side-concerns elsewhere in the same file). **Main session**: allowed, but gets read-dep-augment instead. Logs/data/non-source extensions: not gated. |
| **read-dep-augment** | main-session partial `Read` of a source file (PostToolUse, never blocks) | Surfaces the in-file defs OUTSIDE your slice + cross-file producers/consumers, so a slice does not silently miss same-file side-concerns. |
| **redirect-tmp-scripts** | Write/Bash creating a `.py`/`.sh`/`.lean` under system `/tmp` (or `/var/tmp`) | Scratch scripts go in the project's committed `./tmp/<topic>/` (version-controlled, ungated, promotable to `cl44/`), NOT system `/tmp` (lost on reboot). Reading `/tmp`, non-script `/tmp` files, and `/tmp/claude-*` outputs are NOT blocked. Fires for sub-agents. |
| **guard-destructive-git** | Bash running `git stash drop`/`clear`, `reset --hard`/`--merge`, `clean -f`, `checkout`/`switch --force`/`--discard-changes`, `worktree remove --force`, or whole-tree `checkout .`/`restore .` | BLOCKED — can erase uncommitted/stashed/untracked work. `AskUserQuestion` to confirm the SPECIFIC discard with the human (state what `git status`/`git stash list` shows); that arms a 10-min per-session bypass (`git-asked-gate.sh` on AskUserQuestion), then retry. Or take the safer path the block prints: `git switch -c wip/<name> && git commit -am wip`, `git stash branch <name>`, or `git reset --soft`. Named-path `checkout -- <file>` / `restore <file>` and `restore --staged .` are NOT blocked. |

## Surfacing hooks — what you'll see, and what to DO

Besides the BLOCKING hooks above, several hooks INJECT advisory context (they never block). These exist to stop blind reimplementation and dropped obligations. When you see a tag, take the action — a surfaced id is a STOP-and-retrieve signal, NOT a citation token:

| Injected context you'll see | From | Action |
|---|---|---|
| `[OPEN-BD: <id> (P?) — title]` | PreToolUse Task / Bash(bridge send) | Possibly-relevant OPEN bd issue. `bd show <id>` (full body + design-file) BEFORE writing analysis/code — you may be about to duplicate or contradict it. Don't cite from the one-liner. |
| `[ALREADY-CODIFIED: mod.name (file:line)]` / `[RETIRED: name → use X]` | compose_time_check / symbol_surface | The symbol exists (or is retired). Read + reuse; do NOT reimplement. RETIRED → use the redirect target. |
| `Possibly-relevant prior findings … [KB ~0.NN <id> (proj): …]` | UserPromptSubmit kb-prompt-surface | Semantic kb hits for your prompt. `kb get <id>` before reimplementing what they describe. |
| `BRIDGE_UNREAD` / `BRIDGE_PENDING_REPLIES` / `BRIDGE_OWED_REPLIES` | Stop hooks | Unread peer msgs / replies you're owed / replies you OWE. `recv`; for owed, `bridge send … --reply <id>` (or defer — see Work Queueing). |
| `[STRUCTURAL-FACT … DO NOT RECOMPUTE]` / `[SORRY-CONTRACT WAITING: …]` | compose_time_check | Value/contract already established. Cite certified_data / route to the owner; do not re-derive. |
| `🛑 KB-INFRA DOWN (…)` | ash_health gate | Embedding/LLM server down → kb-search + surfacing are BLIND (empty ≠ "nothing found"). STOP retrieval-dependent derivation; tell the user; mechanical-only until recovered. |

## ast-grep gotcha — empty result is NOT "absent"

`ast-grep` matches the AST **structurally**, so a pattern silently MISSES any node carrying a child the pattern omits → **false negatives**. An empty `ast-grep` result does NOT prove a symbol is absent, and trusting it risks a duplicate reimplementation (the "research before implementing" failure mode).

- **Return annotations break the def pattern**: `def $F($$$): $$$` does NOT match a function with a return type — `def f(...) -> T:` has a `return_type` child the pattern has no slot for. Verified: `def fermion_masses($$$): $$$` → empty, though the function exists as `def fermion_masses(...) -> dict:`; `def $F($$$) -> $R: $$$` matches it. This codebase annotates returns heavily, so the plain pattern misses many defs.
- **Robust def-search**: run BOTH `def $F($$$): $$$` and `def $F($$$) -> $R: $$$`, or locate a known name with `python3 -c "import inspect; from <mod> import <f>; print(inspect.getsourcelines(<f>)[1])"`. Never conclude "not found / no prior art" from a single empty plain-def `ast-grep`.

## Symbol usage-finding: use the LSP, never grep, and don't trust an empty ast-grep

"Where is symbol X **defined / used / who-calls-it**" is a SEMANTIC question — answer it with the **LSP tool**, not ast-grep and not grep:
- **ast-grep is structural** — a bare-identifier pattern matches only standalone identifier *expression* nodes, so it silently misses field accesses (`p2p.X[i]`), declarations (`X: T`), and type positions. This produced a wrong "the field is never set → the handoff is dormant" conclusion that nearly shipped a bigger-than-needed plan; `findReferences` then found 6 real uses across 3 files. ast-grep stays for code-SHAPE queries only.
- **grep stays banned** (`block-text-search-on-source`) — it encourages shallow reading. Route through the LSP.

LSP operations: `findReferences`, `goToDefinition`, `incomingCalls`/`outgoingCalls` (call graph), `workspaceSymbol` (find by name).

### Reliable-use procedure (rust-analyzer indexes lazily — a cold query LIES)
1. **Warm + gate.** rust-analyzer (the LSP plugin) indexes the whole workspace on first use — minutes on a big tree (it runs `cargo check`, incl. build.rs, internally). The SessionStart `rust-analyzer-prewarm.sh` hook backgrounds a `cargo check` to shrink that, but the in-memory index still builds on the first LSP-tool call. So before relying on the LSP, issue one cheap probe — `workspaceSymbol` for a known struct — and **retry until it returns**. "No symbols found / not indexed" means *wait and retry*, NEVER "absent".
2. **Exact, current position.** LSP is line/col-based (1-based). After ANY edit the line numbers shift — re-Read (or use `documentSymbol`) to get the symbol's CURRENT line/col right before `findReferences`/`goToDefinition`. A stale position silently returns nothing.
3. **Empty ≠ absent.** Only an empty `findReferences` taken AFTER warm-up AND at the correct position is a trustworthy "no usages." Confirm dead/unused code via the LSP at the right position — never via an empty ast-grep.

# .md Creation Is Blocked

Hooks block new `.md` files. Route content:
- Finding / checkpoint / agent report → `~/.local/bin/kb add` or INLINE to dispatcher
- Plan (multi-phase) → `~/.claude/plans/PLAN-<slug>.md` (allowlisted)
- Task note → `bd update <id> --notes "..."`
- Architecture reference → Edit EXISTING `docs/reference/` doc
- Short summary → just write it in your reply

Existing `.md` Edit / `git mv` always OK.
