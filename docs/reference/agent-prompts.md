# Agent Prompt Templates & Reference

## Haiku Delegation Tasks

| Task Type | Example Prompt |
|-----------|----------------|
| Existence check | "Does lib/ contain X? JSON: {found:bool, files:[]}" |
| File summary | "Summarize src/foo.py. JSON: {purpose:str}" |
| Signature extraction | "List public functions in X. JSON: {functions:[{name,args,returns}]}" |
| Pattern search | "Find files importing Y. JSON: {files:[]}" |
| Validation | "Run pytest test_foo.py. JSON: {passed:bool, failures:[]}" |

## Output Compression

| Verbose | Compressed |
|---------|------------|
| "Find X and explain" | "Find X. JSON: {found:bool, path:str, line:int}" |
| "Summarize results" | "JSON: {summary:str (max 50 words), items:[]}" |
| "Tell me if it passes" | "JSON: {passed:bool, error:str|null}" |

## Research Agent Prompt Template

```
TASK: {task_description}

## PRIOR KNOWLEDGE (from KB)
{kb_findings_summary}
- kb-XXXXX: {one-line summary}
If these answer the question, STOP and report "Already resolved: kb-XXXXX"

## EXPERT PANEL REQUIREMENT
Select 2-3 domain experts from: {domain1} ({expert_names}), {domain2} ({expert_names}).
State panel and relevance to this question.

## STOPPING CONDITIONS
Stop and return partial results immediately if:
- Same error 3+ times consecutively
- 10+ tool calls with no new findings
- 5+ KB search phrasings with no new results
- Read 8+ files without producing a concrete output
Checkpoint: call kb_add every 10 tool uses, even mid-task.

## SCOPE CONSTRAINTS
- Phase 1 (5 min): State approach, produce intermediate output, kb_add checkpoint
- Phase 2 (5 min): Complete computation/analysis
- If stuck after Phase 1, kb_add what you have and RETURN

## TECHNICAL QUESTIONS
1. {specific_question_1}

## DELIVERABLE
{expected_output_format}. ≤300 words. Conclusion first.
BEFORE RETURNING: kb_add(content=<findings>, finding_type="discovery",
project="{project}", tags="{tags}", verified=<bool>)
```

## Stopping Conditions (Include in ALL agent prompts)

Agents terminate naturally when their task is complete. To prevent infinite loops and ensure work is preserved:

```
## STOPPING CONDITIONS
Stop and return partial results immediately if:
- Same error 3+ times consecutively
- 10+ tool calls with no new findings
- 5+ KB search phrasings with no new results
- Read 8+ files without producing a concrete output
Checkpoint: call kb_add every 10 tool uses, even mid-task.
```

**Checkpoint principle**: Work survives any termination if kb_add is called every 10 tool uses. Design agents to checkpoint frequently rather than save everything at the end.

**Stuck agent rule**: If an agent runs >10 min without output, check and kill it (rule already in CLAUDE.md).

## Expert Panel Domains

| Topic | Suggested Experts |
|-------|-------------------|
| Categories/Functors | Baez, Mac Lane, Lurie |
| Polylogarithms/K-theory | Zagier, Goncharov, Brown |
| Clifford algebras | Lounesto, Porteous, Atiyah |
| Hodge theory | Deligne, Schmid, Saito |
| Representation theory | Vogan, Kazhdan, Lusztig |
| Physics/QFT | Peskin, Weinberg, Coleman |
| Anti-patterns | Claude (always include) |

## Deep Search Protocol (MANDATORY for research)

Shallow search = one round of queries. Deep search = iterative, each round informed by previous.

**Problem**: Agents search once and stop. They don't follow citation chains, extract new terms
from results, or chase cross-references. This misses most of what's in KB/code/literature.

**Solution**: Use the kb-research agent (`~/.claude/agents/kb-research.md`) or the iterative
template below. Key principle: **each round's queries come from the PREVIOUS round's results.**

### Iterative Search Template (5 rounds)

```
Task(subagent_type="general-purpose", model="haiku", prompt=f"""
TOPIC: {topic}

## ROUND 1: Seed queries (provided by parent)
Run these KB searches:
{seed_queries}

## ROUND 2: Follow-up from Round 1
For EACH finding from Round 1:
1. Extract key terms, KB IDs, file paths, and cited findings
2. kb_get(finding_id) for the top 3 most relevant findings (read full content)
3. Form 2-3 NEW search queries using terms you found but didn't search for
4. Run these new queries

## ROUND 3: Chase cross-references
For any KB finding that references another KB ID (e.g., "see kb-XXXXX"):
1. kb_get that referenced ID
2. If IT references others, follow one more level
For any finding that mentions a file path:
1. Note the path for the parent agent to read

## ROUND 4: Tex + Code search
Grep("{{key_term}}", glob="*.tex", head_limit=10)
Grep("{{key_term}}", glob="*.py", path="${PROJECT_DIR}/lib", head_limit=10)

## ROUND 5: Contradiction check
Compare findings. If two findings disagree, note the conflict and which is newer.
Check for superseded findings (kb_correct chains).

## Output
Return JSON: {{
  "findings": [
    {{"id": "kb-...", "summary": "...", "key_terms": ["..."], "cross_refs": ["kb-..."]}}
  ],
  "follow_up_findings": [
    {{"id": "kb-...", "summary": "...", "found_via": "term X from kb-..."}}
  ],
  "tex_matches": [{{"file": "...", "line": N, "context": "..."}}],
  "code_matches": [{{"file": "...", "function": "...", "description": "..."}}],
  "files_to_read": ["path1", "path2"],
  "conflicts": [{{"finding_a": "kb-...", "finding_b": "kb-...", "issue": "..."}}],
  "search_terms_exhausted": ["term1", "term2"],
  "search_terms_untried": ["term3", "term4"],
  "conclusion": "comprehensive summary (100 words)"
}}
""")
```

### Search round budget

| Round | Tool calls | What happens |
|-------|------------|-------------|
| 1 | 3 | Seed queries (provided by parent) |
| 2 | 3-4 | Follow-up queries from Round 1 results |
| 3 | 2-3 | Chase cross-references (kb_get) |
| 4 | 2 | Tex + code grep |
| 5 | 1-2 | Contradiction check + output |

All 5 rounds use ~12 tool calls and find 3-5x more than a single-round search.

### Web Search Depth Template

```
Task(subagent_type="general-purpose", model="haiku", prompt=f"""
TOPIC: {topic}

## ROUND 1: Broad search
WebSearch("{broad_query_1}")
WebSearch("{broad_query_2}")

## ROUND 2: Targeted from Round 1
For each useful result from Round 1:
1. Extract author names, paper titles, key terms
2. WebSearch for the most promising lead (e.g., "AuthorName topic 2025")
3. If a result mentions a specific paper/theorem, search for it directly

## ROUND 3: Fetch key sources
For the top 2-3 most relevant URLs found:
1. WebFetch(url, "Extract: key theorems, definitions, and results related to {topic}")

## Output
Return JSON: {{
  "sources": [{{"title": "...", "url": "...", "key_results": ["..."]}}],
  "follow_up_sources": [{{"title": "...", "found_via": "search term from round 1"}}],
  "key_theorems": ["..."],
  "conclusion": "what the literature says (100 words)"
}}
""")
```

## Ready-to-Use Haiku Prompts (Simple)

For quick lookups (NOT research), these single-round templates are fine:

```python
# File existence
'Does {path} contain files matching {pattern}? JSON: {found:bool, files:[], count:int}'

# Function search
'Find function {name} in {path}. JSON: {found:bool, file:str, line:int, signature:str}'

# Import check
'What does {file} import? JSON: {imports:[], from_imports:[{module,names}]}'

# Test result
'Run pytest {path}. JSON: {passed:bool, total:int, failed:int, errors:[]}'

# Diff summary
'Summarize changes in {file}. JSON: {added:int, removed:int, functions_changed:[]}'

# Type check
'What type is {symbol} in {file}? JSON: {type:str, defined_at:str}'
```

**Decision**: Simple lookup → single-round template. Research → iterative 5-round template.

## Mandatory Agent Rules (Include in ALL agent prompts)

### Rule 1: Read Before Import (CRITICAL)

**NEVER guess function signatures from lib/.** Before importing any module:
1. Use the Read tool to read the module file
2. Or read `docs/reference/api_signatures.md` for quick reference
3. If a function doesn't exist, DO NOT debug — write the computation from scratch

Common wrong guesses that waste turns:
- `from lib.fock_operators import total_number` → correct: `cached_total_number`
- `from lib.fock_operators import chirality` → correct: `cached_chirality`
- `from lib.induced_gravity import triality_images` → correct: `get_triality_images_of_mhf`
- `cl.gamma[i]` → correct: `cl.gamma(i)` (method, not subscript)

### Rule 2: Haiku Sub-Agents for Literature/KB Search

For ANY literature search, KB exploration, or web search, delegate to a Haiku sub-agent:

```python
Task(subagent_type="general-purpose", model="haiku", prompt=f"""
Search for: {topic}

1. kb_search("{query1}"), kb_search("{query2}"), kb_search("{query3}")
2. WebSearch("{web_query}") if KB has nothing
3. Return JSON: {{
     "kb_findings": [{{id, summary}}],
     "web_findings": [{{title, url, key_point}}],
     "conclusion": "str (50 words max)"
   }}
""")
```

**Why**: Haiku is 10x cheaper and faster for lookups. Saves Sonnet/Opus turns for reasoning and computation.

**When to delegate**:
- KB searches (always — try 3+ phrasings)
- Web searches for papers, definitions, theorems
- File existence checks
- API signature lookups

**When NOT to delegate**:
- Reading a specific file you know the path to (just Read it yourself)
- Running a computation (do it yourself)
- Reasoning about results (do it yourself)

### Rule 3: Scripts Over Jupyter for Agents

When an agent needs to run computation, prefer writing a Python script over Jupyter:

**Jupyter problems for agents:**
- `setup_notebook` + `modify_notebook_cells` API is unfamiliar, agents misuse parameters
- Import errors in cells require `edit_code` operations that waste turns
- Cell state management adds complexity

**Script approach:**
```python
# Write script
Write("/path/to/exploration/my_investigation.py", content)
# Run it
Bash("cd ${PROJECT_DIR} && python3 exploration/my_investigation.py")
```

**When Jupyter IS appropriate for agents:**
- Agent needs to iterate interactively on plots
- SageMath/Maple kernel required
- User explicitly requested notebook output

### Rule 4: API Signatures Quick Reference

Tell agents to read the signatures file:
```
Read docs/reference/api_signatures.md for function signatures before importing from lib/.
```

This file contains the most-used imports with correct names, common gotchas, and full module signatures.

## Updated Research Agent Template

```
TASK: {task_description}

## PRIOR KNOWLEDGE (from KB)
{kb_findings_summary}
If these answer the question, STOP and report "Already resolved: kb-XXXXX"

## API REFERENCE
Read docs/reference/api_signatures.md BEFORE importing from lib/.
NEVER guess function names. If unsure, Read the module file first.

## HAIKU DELEGATION
For literature/KB/web searches, spawn a Haiku sub-agent:
  Task(subagent_type="general-purpose", model="haiku",
       prompt="Search KB and web for {topic}. Return JSON: {findings, conclusion}")
This saves your turns for reasoning and computation.

## COMPUTATION METHOD
Write Python SCRIPTS (not Jupyter) for numerical work:
  Write("exploration/{name}.py", code)
  Bash("cd ${PROJECT_DIR} && python3 exploration/{name}.py")

## EXPERT PANEL REQUIREMENT
Select 2-3 domain experts from: {domain1} ({expert_names}), {domain2} ({expert_names}).

## STOPPING CONDITIONS
Stop and return partial results immediately if:
- Same error 3+ times consecutively
- 10+ tool calls with no new findings
- Read 8+ files without a concrete output
Checkpoint: call kb_add every 10 tool uses.

## DELIVERABLE
{expected_output_format}. ≤300 words. Conclusion first.
BEFORE RETURNING: kb_add(content=<findings>, finding_type="discovery",
project="{project}", tags="{tags}", verified=<bool>)
```
