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

## SCOPE CONSTRAINTS
- Phase 1 (5 min): State approach, produce intermediate output
- Phase 2 (5 min): Complete computation/analysis
- If stuck after Phase 1, kb_add what you have and RETURN

## TECHNICAL QUESTIONS
1. {specific_question_1}

## DELIVERABLE
{expected_output_format}. ≤300 words. Conclusion first.
BEFORE RETURNING: kb_add(content=<findings>, finding_type="discovery",
project="{project}", tags="{tags}", verified=<bool>)
```

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

## Ready-to-Use Haiku Prompts

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

**Usage**: Copy template, fill placeholders, wrap in Task call with `model="haiku"`.
