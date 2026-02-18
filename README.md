# Claude Code Configuration

A batteries-included `~/.claude` configuration with custom agents, review workflows, automation hooks, and strict coding discipline enforcement.

## What This Does

This config turns Claude Code into a more rigorous development partner:

- **Two-stage review gates** prevent sloppy code from shipping (plan review + implementation review)
- **25 automation hooks** enforce workflow compliance (no reimplementing existing code, no accidental `git add -A`, KB search before implementation, etc.)
- **8 custom agents** for specialized tasks (architecture, sprint reviews, build error analysis)
- **84 reviewer personas** across 22 domains that Claude adopts for code review
- **Anti-pattern detection** blocks common Claude failure modes (speculation, "should I proceed?", print-spam)

## Quick Start

```bash
# Back up existing config if you have one
[ -d ~/.claude ] && mv ~/.claude ~/.claude.bak

# Clone directly as ~/.claude
git clone https://github.com/YOUR_USERNAME/claude-code-config ~/.claude
```

Claude Code reads `~/.claude/` automatically on startup.

### Optional: Local Overrides

Create `~/.claude/settings.local.json` (gitignored) for machine-specific settings:

```json
{
  "permissions": {
    "allow": [
      "Bash(pacman:*)",
      "Bash(your-local-commands:*)"
    ]
  },
  "env": {
    "KB_EMBEDDING_URL": "http://your-server:8080/embedding"
  }
}
```

## What's Included

```
~/.claude/
├── CLAUDE.md            # Master rules (agent dispatch, anti-patterns, KB workflow)
├── reviewers.yaml       # 84 expert reviewer personas across 22 domains
├── settings.json        # Tool permissions, hooks, features
├── agents/              # 8 custom agent definitions
│   ├── expert-review.md           # Plan review (APPROVED/REJECTED/INCOMPLETE)
│   ├── implementation-review.md   # Post-implementation verification
│   ├── software-architect.md      # Architecture guidance
│   ├── sprint-code-reviewer.md    # Sprint completion validation
│   ├── compiler-error-analyzer.md # Build error analysis (needs local LLM)
│   ├── kb-research.md             # Iterative KB search (5 rounds)
│   ├── gpu-bios-analyzer.md       # GPU ROM analysis
│   └── makefile-reviewer.md       # Build system review
├── commands/            # Slash commands (/review, /sprint, /analyze, etc.)
├── hooks/               # 25 automation hooks
├── bin/                 # Helper scripts (statusline)
├── tools/               # Local LLM integration tools
├── plugins/             # LSP plugin config
└── docs/                # Agent prompt templates and reference
```

## Key Features

### Review Gates

Every plan goes through `expert-review` before implementation. Every implementation goes through `implementation-review` before completion. Both run in background to prevent memory exhaustion and must return APPROVED.

### Hooks

Selected highlights from the 25 hooks:

| Hook | What it does |
|------|-------------|
| `check-existing-code.sh` | Blocks reimplementing code that already exists |
| `kb-search-gate.sh` | Requires KB search before writing new code |
| `block-markdown-files.sh` | Prevents accidental doc file creation |
| `block-print-spam.sh` | Catches explanatory print() in scripts |
| `remind-patterns.sh` | Reminds anti-patterns on every prompt |
| `session-start-resume.sh` | Restores session state across restarts |
| `plan-write-review.sh` | Re-runs expert-review when plans change |

### Reviewer Personas

`reviewers.yaml` defines 84 expert personas. Claude auto-selects 2-3 relevant reviewers based on context. Trigger phrases: "critically review", "sanity check", "verify this".

Pre-built panels:
- `technical_review`: Peskin + Anderson + Connes
- `popular_writing`: Sagan + Feynman + Munroe + Orwell
- `skeptic_panel`: Mencken + Russell + 't Hooft

### Anti-Patterns Blocked

The CLAUDE.md and hooks work together to prevent:
- Speculation ("I believe", "this likely")
- Asking permission ("Should I proceed?", "What would you like...")
- Reimplementing existing code without searching first
- `git add -A` or `git push --force`
- Mocks, stubs, or fake data
- Notebooks with markdown cells or comments

### Slash Commands

| Command | Purpose |
|---------|---------|
| `/review` | Trigger appropriate review agent |
| `/sprint` | Sprint planning and task management |
| `/analyze` | Deep code/log analysis |
| `/merge` | Merge sprint branch into master |

## Optional Dependencies

Some features require external services. Everything works without them, but these hooks will silently skip:

| Feature | What it needs | Environment variable |
|---------|--------------|---------------------|
| Knowledge Base | MCP server (`knowledge-base`) | Configured in MCP settings |
| Build error analysis | Local LLM (llama.cpp) | `LLM_ENDPOINT` (default: `localhost:9510`) |
| KB embeddings | Embedding server | `KB_EMBEDDING_URL` (default: `localhost:8080`) |

## Customization

### Adding Your Own Rules

Edit `CLAUDE.md` to add project-specific rules. The existing structure supports:
- Per-project CLAUDE.md files (in your project repos)
- Domain-specific reviewer panels
- Custom hook triggers

### Removing Physics-Specific Content

This config was developed for a physics research project. To remove domain-specific content:
1. Edit `reviewers.yaml` to remove/replace physics reviewers
2. Remove physics references from `CLAUDE.md` (Jupyter/SageMath/Maple sections)
3. Remove `commands/review-physics.md`

### Adding Hooks

Hooks go in `hooks/` and are referenced in `settings.json`. Each hook is a shell script that receives context via environment variables and stdin. See existing hooks for the pattern.

## Settings

`settings.json` contains shareable permissions:
- Tool allowlists (bash commands, git operations)
- Feature flags (skills, tasks, LSP)

`settings.local.json` (gitignored) contains machine-specific:
- Host-specific commands
- Local paths and endpoint URLs

## What's Gitignored

```
sessions/           # Active session state
cache/              # Performance caches
history.jsonl       # Conversation history
*.credentials       # Secrets
settings.local.json # Machine-specific overrides
projects/           # Per-project session data
```

## License

MIT
