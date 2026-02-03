---
description: Analyze build errors using local LLM with full source context
allowed-tools: Bash(llm-analyze-errors:*), Bash(build-manager analyze:*), Bash(build-manager analyze-errors:*), Bash(llm-query:*), Bash(build-manager get-errors:*), Bash(build-manager status:*)
argument-hint: [project-path]
---

# Build Error Analysis

Analyzing build errors using local LLM at tardis:9510 (262K context window).

## Current Build Status
```
!`build-manager status 2>/dev/null || echo "No active builds"`
```

## Error Analysis
```
!`llm-analyze-errors --project "{{args[0] || '.'}}" 2>&1`
```

## Follow-up Actions

If the analysis is incomplete or you need more context, I can:

1. **Read additional source files** - Get full file content for files mentioned in errors
2. **Query LLM directly** - Ask specific questions about the error
3. **Check build history** - See if this error has occurred before
4. **List available logs** - Find other build logs to analyze

Use `build-manager get-errors` for raw error extraction without LLM analysis.
