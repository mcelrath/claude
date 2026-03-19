# Agent Preamble — Claude Code Config (claude)

Read this BEFORE starting your task. Subagents do NOT see CLAUDE.md.

## The Project

This is the user's global Claude Code configuration at `~/.claude` (`/home/mcelrath/Projects/ai/claude`).
It contains: CLAUDE.md (global rules), hooks/, agents/ (subagent prompts), models.yaml (model registry),
beads workflow tooling, and project-specific scaffold files (reviewers.yaml, agent-preamble.md).
The primary domain is AI agent orchestration, LLM workflow tooling, and Claude Code configuration.

## Non-Negotiable Constraints

- **Hook blocks are FINAL.** If a hook exits 2, STOP. Do not rephrase or work around it.
- **No markdown file creation** unless explicitly requested (hook enforced).
- **No `git add -A` or `git add .`** — other Claude sessions may be active.
- **kb-research agent before any Edit/Write** (hook enforced). Spawn it; don't call kb_search directly.
- **Every agent prompt must start with**: `Read ~/.claude/agents/preamble.md FIRST, then proceed.`
- **Never pass `max_turns`** to Task(). Use STOPPING CONDITIONS in prompt instead.
- **Review agents**: always `run_in_background=True` (prevents 34GB+ memory growth).
- **All plans go in**: `~/.claude/plans/PLAN-<slug>.md`. No ExitPlanMode. No `.approved` markers.
- **Commit only touched files**: `git add <file1> <file2>` with explicit paths, `--no-gpg-sign`.
- **Concurrent edit detection**: Before Edit/Write, if file was previously read, run `git diff -- <file>`. STOP if unexpected changes found.

## Key Proven Results (Do NOT Re-Derive)

None established yet for this configuration project itself (KB findings under project=claude are
mostly from HyperComplexAnalysis which shares the same CLAUDE.md via global config).

## Terminology

| Term | Definition |
|------|------------|
| bd / beads | Task tracking CLI. `bd create`, `bd update`, `bd close`, `bd show`, `bd ready` |
| epic | A bd issue of type=epic with a design-file plan. Requires expert-review before implementation. |
| kb-research agent | Subagent for KB/literature search. NEVER call kb_search directly in main agent. |
| preamble.md | `~/.claude/agents/preamble.md` — epistemological rules, must be read by every subagent |
| reviewers.yaml | `{project_root}/reviewers.yaml` — reviewer personas for expert-review |
| agent-preamble.md | `{project_root}/agent-preamble.md` — this file, project-specific subagent context |
| model_calibration | Per-domain probe results in reviewers.yaml. WRONG = never use that model for that domain. |
| run_in_background | MANDATORY for review agents. Prevents memory growth (34GB+). |

## Key Modules

| Path | Purpose |
|------|---------|
| `agents/preamble.md` | Global agent epistemological rules |
| `agents/expert-review.md` | Full/light review subagent prompt |
| `agents/kb-research.md` | KB search subagent template |
| `agents/project-setup.md` | This agent's own prompt |
| `hooks/` | Pre/post tool hooks enforcing workflow rules |
| `models.yaml` | Model registry: providers, cost tiers, calibration data |
| `reviewers.yaml` | Reviewer personas (this project) |
| `agent-preamble.md` | This file |

## Anti-Patterns

| Pattern | Why Wrong |
|---------|-----------|
| Calling `kb_search()` in main agent | Spawn kb-research agent instead. Hook enforces this. |
| `Task(..., max_turns=N, ...)` | Hard limits cut agents off mid-tool-call. Use STOPPING CONDITIONS. |
| Agent prompt without `Read preamble.md` | Agents make shallow-search and inference failures without it. |
| ExitPlanMode / EnterPlanMode | DEPRECATED. Use beads epics. |
| Plan written in conversation prose | Write to `~/.claude/plans/PLAN-<slug>.md` first. |
| Expert-review prompt inlines plan | Prompt = `FULL REVIEW: epic=<id> project_root=<path>`. Plan in design file. |
| `git add -A` or `git add .` | Other sessions may be active. Use explicit file paths. |
| Hook blocks, then rephrasing to bypass | Hook blocks are FINAL. STOP and tell user what was blocked. |
| `I believe` / `This likely` / speculative claims | Verify from data. Cite file:line or kb-ID. |
| Box-drawing table characters (┌─┬│) | NEVER. Use dashes and spaces only. |
| 3+ parallel Opus agents | FORBIDDEN. Use Haiku/Sonnet for at least 2. |
| Polling build-manager status in a loop | Use `--sync` for short builds, team+build-monitor for long. |
| Using model rated WRONG for a domain | Check models.yaml calibration before assigning models. |

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
