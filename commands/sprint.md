---
allowed-tools: Bash(tree:*), Bash(ls:*), Bash(find:*), Bash(git add:*), Bash(git commit:*), Bash(git worktree:*), Bash(git branch:*), Bash(git status:*), Bash(git checkout:*), Bash(git pull:*), Bash(git log:*), Bash(git init:*), Bash(mkdir:*), Bash(/bin/true)
description: Start a new sprint and create a SPRINT_NAME.md plan for it.
argument-hint: [sprint-number-or-name] [description]
---

# Sprint Command
# Usage: /sprint <NAME> <description...>

## Context

- Project filesystem tree: 
```
!`tree --gitignore`
```
- Current git branch: !`git branch --show-current`
- Recent git commits: 
```
!`git log --oneline -10 2>&1 || /bin/true`
```
- Bash(pwd && ls -la): 
```
!`pwd && ls -la`
```
- Bash(git status): 
```
!`git status`
```

## Rules

- The entire filesystem tree is above. **DO NOT** use find to find anything else. It's all there.

## Your task

I need to start a new sprint. Please:

1. Analyze the current codebase to understand its structure, programming languages, and existing patterns

2. Create a comprehensive sprint plan named SPRINT_{{args[0]}}.md that includes:
   - Focus on creating a detailed, actionable plan with a task breakdown that covers all aspects of the requested work based on the user's description below
   - Implementation approach and architecture decisions
   - Specific files and components to be created or modified
   - Testing strategy
   - Any dependencies or prerequisites

3. Ensure .gitignore exists and contains:
   - Common patterns for the detected programming languages
   - .worktrees/ directory
   - Any other standard ignore patterns for this project type

4. Commit the SPRINT_{{args[0]}}.md and .gitignore files to the repository

5. Ensure we're working from master HEAD with no uncommitted changes:
   - Ensure we're on a clean commit point for worktree creation
   - Verify clean working directory: `git status --porcelain` should return empty
   - Pull latest changes: `git pull origin master` (if remote exists)
   - Ensure no uncommitted changes exist before creating worktree

6. Create a git worktree in .worktrees/ directory with name "sprint-{{args[0]}}-<short-description>" and creating a new branch of the same name.
   - The short-description should be a concise (2-3 word) summary based on the user's description
   - Use current branch HEAD as the source branch
   - Create clean worktree with no uncommitted changes: `git worktree add -b sprint-{{args[0]}}-<short-description> .worktrees/sprint-{{args[0]}}-<short-description>`
   - Switch to this worktree with `cd .worktrees/sprint-{{args[0]}}-<short-description>`
   - Verify clean state: `git status --porcelain` should return empty in the worktree

7. From now on you must work ONLY within the worktree you just created.
   - Do not look at ../.. which should be the master branch and will contain other work

The sprint name is: {{args[0]}}
The sprint description is: {{args[1:]}}

