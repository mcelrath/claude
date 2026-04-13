# Agent Preamble — Claude Code Config (claude)

Read this BEFORE starting your task. Subagents do NOT see CLAUDE.md.

## The Project

This is the user's global Claude Code configuration at `~/.claude` (`/home/mcelrath/Projects/ai/claude`).
It contains CLAUDE.md (global rules), hooks/ (25 bash automation hooks), agents/ (13 subagent prompts),
models.yaml (model registry with calibration data), beads workflow tooling, and project-specific
scaffold files (reviewers.yaml, agent-preamble.md). The primary domains are AI agent orchestration,
LLM workflow tooling, shell hook enforcement, and multi-session concurrency safety.

## Non-Negotiable Constraints

- Hook blocks are FINAL. If a hook exits 2, STOP. Do not rephrase or work around it.
- No markdown file creation unless explicitly requested (hook enforced).
- No `git add -A` or `git add .` -- other Claude sessions may be active.
- kb-research agent before any Edit/Write (hook enforced). Spawn it; don't call kb_search directly.
- Every agent prompt must start with: `Read ~/.claude/agents/preamble.md FIRST, then proceed.`
- Never pass `max_turns` to Task(). Use STOPPING CONDITIONS in prompt instead.
- Review agents: always `run_in_background=True`.
- All plans go in `~/.claude/plans/PLAN-<slug>.md`. No ExitPlanMode. No `.approved` markers.
- Commit only touched files: `git add <file1> <file2>` with explicit paths, `--no-gpg-sign`.
- Concurrent edit detection: Before Edit/Write, run `git diff -- <file>`. STOP if unexpected changes.
- No backwards compatibility wrappers. Delete superseded code; git history exists.
- No mocks, stubs, or fake data.

## Key Proven Results (Do NOT Re-Derive)

- nemotron-3-super is the only viable local model for this project (5/5 CORRECT on calibration probes)
- qwen3.5:122b too slow (all timeouts), devstral-2/qwen3-coder API format errors, qwen3.5:35b partial
- Model calibration date: 2026-03-19

## Terminology

| Term | Definition |
|------|------------|
| bd / beads | Task tracking CLI. `bd create`, `bd update`, `bd close`, `bd show`, `bd ready` |
| epic | A bd issue of type=epic with a design-file plan. Requires expert-review before implementation |
| kb-research agent | Subagent for KB/literature search. NEVER call kb_search directly in main agent |
| preamble.md | `~/.claude/agents/preamble.md` -- epistemological rules for every subagent |
| reviewers.yaml | `{project_root}/reviewers.yaml` -- reviewer personas for expert-review |
| model_calibration | Per-domain probe results. WRONG = never use that model for that domain |
| run_in_background | MANDATORY for review agents. Prevents memory growth |
| trigger_paths | Glob patterns in reviewers.yaml that determine which personas review which files |

## Key Modules

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Master rules: agent dispatch, anti-patterns, KB workflow, git rules |
| `agents/preamble.md` | Global agent epistemological rules (read first in every agent) |
| `agents/expert-review.md` | Full/light review subagent prompt |
| `agents/kb-research.md` | KB search subagent template (5 rounds, 12 turns) |
| `agents/project-setup.md` | Scaffold generator (this agent's own prompt) |
| `hooks/` | 25+ bash hooks enforcing workflow rules |
| `hooks/lib/` | Shared hook utilities |
| `models.yaml` | Model registry: providers, cost tiers, calibration data |
| `settings.json` | Tool permissions, hook definitions, feature flags |
| `commands/` | Slash commands (/review, /sprint, /analyze, /merge) |
| `skills/` | Skill definitions for Claude Code |

## Anti-Patterns

| Pattern | Why Wrong |
|---------|-----------|
| Calling `kb_search()` in main agent | Spawn kb-research agent instead. Hook enforces this |
| `Task(..., max_turns=N)` | Hard limits cut agents off mid-tool-call. Use STOPPING CONDITIONS |
| Agent prompt without `Read preamble.md` | Agents make shallow-search and inference failures without it |
| ExitPlanMode / EnterPlanMode / `.approved` | DEPRECATED. Use beads epics |
| Plan written in conversation prose | Write to `~/.claude/plans/PLAN-<slug>.md` first |
| Expert-review prompt inlines plan | Prompt should reference epic ID and design file path |
| `git add -A` or `git add .` | Other sessions may be active. Use explicit file paths |
| Hook blocks, then rephrasing to bypass | Hook blocks are FINAL. STOP and tell user |
| `I believe` / `This likely` | Verify from data. Cite file:line or kb-ID |
| Box-drawing table characters | NEVER. Use dashes and spaces only |
| 3+ parallel Opus agents | FORBIDDEN. Use Haiku/Sonnet for at least 2 |
| `old_name = new_name` / RuntimeError stub | No backwards compatibility. Delete and fix callers |
| Starting epic without expert-review | ALL epics get expert-review before implementation |
| `isolation: "worktree"` for implementation | Worktree isolation auto-deletes. Use manual worktree for kept work |

## Epistemological Rules

1. "Not Found" does not equal "Doesn't Exist." Say "I found no evidence for X."
2. Code > Comments > KB > Your assumptions.
3. 5 rounds of kb-research, not 2.
4. Verify, don't infer. Grep for RESULTS, not TODO comments.
5. State your evidence. Every claim cites file:line, kb-ID, or command output.
6. kb_add before returning. Checkpoint every 10 tool uses.
7. project="claude" for all kb_add/kb_search calls in this project.
8. First kb_search query must use project=None (cross-project blindness is real).

## Stopping Conditions

Stop and return partial results if:
- Same error 3 times consecutively
- 10+ tool calls with no new findings
- 5+ search phrasings with no results
- 8+ files read without concrete output
