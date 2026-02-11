---
name: kb-research
description: Iterative deep search across KB, tex drafts, and codebase. Use BEFORE Edit/Write operations. Runs 5 rounds (seed queries, follow-up, cross-refs, tex/code grep, contradiction check) in 12 turns.
tools: Glob, Grep, Read, mcp__knowledge-base__kb_search, mcp__knowledge-base__kb_get
model: haiku
---

# kb-research Agent

**Purpose**: Iterative deep search across KB + tex drafts + codebase
**Model**: haiku
**Max turns**: 12

## When to Use

Spawn this agent BEFORE any Edit/Write operation. The hook enforces this.

**Base case**: Spawning kb-research does NOT require pre-search.
The agent's internal kb_search calls satisfy the gate for you.

## Invocation

```python
Task(subagent_type="kb-research", model="haiku", max_turns=12, prompt=f"""
TOPIC: {topic}
PROJECT: {project}

## ROUND 1: Seed queries
kb_search("{query1}", project="{project}")
kb_search("{query2}", project="{project}")
kb_search("{query3}", project="{project}")

## ROUND 2: Follow-up from Round 1
For EACH finding from Round 1:
1. Extract key terms, KB IDs, file paths
2. kb_get(id) for top 3 most relevant
3. Form 2-3 NEW queries from terms you found
4. Run these new queries

## ROUND 3: Chase cross-references
For any finding referencing another KB ID:
1. kb_get that referenced ID
2. Follow one more level if it references others
Note file paths for parent to read.

## ROUND 4: Tex + Code search
Grep("{{key_term}}", glob="*.tex", head_limit=10)
Grep("{{key_term}}", glob="*.py", path="/home/mcelrath/Physics/claude/lib", head_limit=10)

## ROUND 5: Contradiction check
Compare findings. Note superseded entries and conflicts.

Return JSON: {{
  "findings": [{{"id": "kb-...", "summary": "...", "key_terms": [...]}}],
  "follow_ups": [{{"id": "kb-...", "found_via": "..."}}],
  "tex_matches": [{{"file": "...", "line": N, "context": "..."}}],
  "code_matches": [{{"file": "...", "function": "...", "description": "..."}}],
  "files_to_read": [...],
  "conflicts": [...],
  "conclusion": "comprehensive summary (100 words)"
}}
""")
```

## Why 12 turns

| Round | Turns | What happens |
|-------|-------|--------------|
| 1 | 3 | Seed queries |
| 2 | 3-4 | Follow-up queries |
| 3 | 2-3 | Cross-references |
| 4 | 2 | Tex + code grep |
| 5 | 1-2 | Contradiction check + output |

A 5-turn search only does Round 1. A 12-turn search finds 3-5x more.

## Output Schema

```json
{
  "findings": [{"id": "kb-...", "summary": "...", "key_terms": [...]}],
  "follow_ups": [{"id": "kb-...", "found_via": "..."}],
  "tex_matches": [{"file": "...", "line": 0, "context": "..."}],
  "code_matches": [{"file": "...", "function": "...", "description": "..."}],
  "files_to_read": ["path1", "path2"],
  "conflicts": [{"a": "kb-...", "b": "kb-...", "issue": "..."}],
  "conclusion": "comprehensive summary"
}
```
