# Claude Code Configuration

Personal Claude Code configuration with custom agents, review workflows, and automation hooks.

## Quick Start

```bash
# Clone and symlink
git clone https://github.com/YOUR_USERNAME/claude ~/.claude-config
ln -sfn ~/.claude-config ~/.claude

# Or if ~/.claude already exists with data you want to keep:
mv ~/.claude ~/.claude.bak
ln -sfn ~/Projects/ai/claude ~/.claude
```

## Directory Structure

```
~/.claude/
├── CLAUDE.md           # Master rules and instructions (589 lines)
├── reviewers.yaml      # Expert reviewer personas (84 reviewers, 22 domains)
├── settings.json       # Tool permissions (shareable)
├── settings.local.json # Machine-specific overrides (gitignored)
├── agents/             # Custom agent definitions (8 agents)
├── commands/           # Slash commands (8 commands)
├── hooks/              # Automation hooks (25 hooks)
└── .gitignore          # Excludes credentials, sessions, history
```

## Key Features

### 1. Mandatory Review Gates

Two-stage review workflow enforced by agents:

| Stage | Agent | Trigger |
|-------|-------|---------|
| Before implementing | `expert-review` | Plan approval |
| After implementing | `implementation-review` | Code complete |

Both agents run in background (prevents memory exhaustion) and must return APPROVED.

### 2. Named Reviewer Personas (`reviewers.yaml`)

84 expert reviewers across 22 technical domains. Agents auto-select appropriate panels:

**Technical Domains:**
- Clifford algebras (Lounesto, Penrose, Porteous)
- Polylogarithms (Zagier, Lewin, Bloch)
- QFT/Gauge theory (Peskin, Coleman, Weinberg)
- Condensed matter (Anderson, Kitaev, Bardeen)
- And 18 more...

**Composite Panels:**
```yaml
technical_review: [Peskin, Anderson, Connes]
popular_writing: [Sagan, Feynman, Munroe, Orwell]
skeptic_panel: [Mencken, Russell, 't Hooft]
```

**Auto-trigger phrases:** "critically review", "sanity check", "verify this"

### 3. Automation Hooks

25 hooks enforce workflow compliance:

| Hook | Purpose |
|------|---------|
| `session-start-resume.sh` | Restore previous session state |
| `check-existing-code.sh` | Block reimplementing existing code |
| `kb-search-gate.sh` | Require KB search before new work |
| `block-markdown-files.sh` | Prevent unintended file creation |
| `block-presentation-cells.sh` | Keep notebooks computation-only |
| `plan-write-review.sh` | Re-run expert-review after plan edits |

### 4. Custom Agents

| Agent | Purpose |
|-------|---------|
| `expert-review` | Plan review with state machine (APPROVED/REJECTED/INCOMPLETE/ERROR) |
| `implementation-review` | Post-implementation code/test verification |
| `software-architect` | Architecture and design guidance |
| `sprint-code-reviewer` | Sprint completion validation |
| `compiler-error-analyzer` | Build error analysis |

### 5. Slash Commands

| Command | Purpose |
|---------|---------|
| `/review` | Trigger appropriate review agent |
| `/sprint` | Sprint planning and task management |
| `/analyze` | Deep code/log analysis |
| `/save-state` | Manual session state save |

## CLAUDE.md Highlights

Key rules enforced:

```markdown
# Anti-Patterns (blocked by hooks)
- Creating markdown files without request
- Notebooks with markdown cells or comments
- print() statements that explain instead of compute
- Reimplementing existing code without checking
- "Should I proceed?" (just do it)
- "What would you like..." (use AskUserQuestion tool)

# Rules
- kb_search before implementation (enforced by hook)
- No mocks, stubs, or fake data
- No `git add -A` or `git push --force`
- Options for user → AskUserQuestion tool
```

## Knowledge Base Integration

Uses MCP server for persistent knowledge:

```python
kb_search(query, project)      # Find prior results
kb_add(content, type, project) # Record discoveries
kb_correct(id, content, reason) # Fix outdated findings
```

KB searches should use Haiku agent for efficiency:
```python
Task(subagent_type="general-purpose", model="haiku",
     prompt="Search KB for [TOPIC]. Try 3+ phrasings...")
```

## Jupyter Notebooks

Notebooks are for **computation only**:
- No markdown cells
- No comments
- No print() with labels/descriptions
- Explanations go in response text

```python
setup_notebook("experiment", server_url="http://localhost:8888")
modify_notebook_cells("experiment", "add_code", "result = compute()")
```

## Settings

`settings.json` contains shareable permissions:
- Tool allowlists (bash commands, git operations)
- Feature flags (skills, tasks, LSP)

`settings.local.json` (gitignored) contains machine-specific:
- Host-specific commands (pacman, pactl)
- Local paths and credentials

## What's Gitignored

```
sessions/          # Active session state
cache/             # Performance caches
history.jsonl      # Conversation history
*.credentials      # Secrets
settings.local.json # Machine-specific
projects/          # Per-project session data
```

## Integration with Physics Project

The `~/Physics/claude/CLAUDE.md` extends this config with domain-specific rules:
- τ²(M) condensate physics
- Polylog gap equations
- Mode sum normalization
- Gauge coupling constraints (no PDG comparisons)

## Contributing

This is a personal configuration. Feel free to fork and adapt for your own use.

## License

MIT
