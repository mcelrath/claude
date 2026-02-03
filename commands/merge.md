---
allowed-tools: Bash(git add:*), Bash(git commit:*), Bash(git worktree:*), Bash(git branch:*), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git checkout:*), Bash(git merge:*), Bash(git rebase:*), Bash(git reset:*), Bash(git rm:*), Bash(/bin/true)
description: Merge a completed sprint branch into master with comprehensive validation and commit squashing.
argument-hint: [sprint-branch-name]
---

# Merge Command
# Usage: /merge [sprint-branch-name]

## Context

- Current git branch: !`git branch --show-current`
- Current working directory: !`pwd`
- Recent git commits:
```
!`git log --oneline -10 2>&1 || /bin/true`
```
- Bash(git status):
```
!`git status`
```
- Available branches:
```
!`git branch -a`
```

## Rules

- Always verify clean working directory before any operations
- Never merge without comprehensive validation
- Use proper git merge techniques
- Always run tests after successful merge

## Your task

I need to merge a completed sprint branch into master. Please:

### Phase 1: Determine Target Branch

1. **Identify Sprint Branch**:
   - If sprint branch name provided as argument: use "{{args[0]}}"
   - If no argument provided: use current branch (assume we're in a worktree)
   - Store the target branch name for use throughout the process

### Phase 2: Pre-Merge Validation

2. **Ensure Clean Working Directory**:
   - Switch to master branch: `git checkout master`
   - Verify no uncommitted changes: `git status --porcelain` should return empty
   - Pull latest changes if needed: `git pull origin master`

3. **Validate Sprint Branch**:
   - Check that target branch exists locally
   - Show commit history differences between master and sprint branch
   - Count uncommitted changes in sprint branch (should be 0 for clean merge)

4. **Comprehensive Sprint Validation**:
   - Run basic functionality tests to ensure system works
   - Check for any merge conflicts before merging: `git merge --no-commit --no-ff <target-branch> --dry-run` if available
   - Verify sprint goals are achieved (check SPRINT_*.md files if present)

### Phase 3: Squash Sprint Commits

5. **Switch to Sprint Branch**:
   - Checkout the sprint branch: `git checkout <target-branch>`
   - Ensure the working directory is clean

6. **Analyze Commit History**:
   - Show all commits that will be squashed: `git log --oneline master..<target-branch>`
   - Count the number of commits to be squashed
   - Verify there are commits to squash (if only 1 commit, skip squashing)

7. **Perform Interactive Rebase to Squash**:
   - Start interactive rebase: `git rebase -i master`
   - Squash all commits into a single comprehensive commit
   - Create a descriptive commit message that summarizes the entire sprint
   - Commit message format: "Sprint {N}: {brief description of all features implemented}"

8. **Validate Squashed Commit**:
   - Verify the squashed commit contains all changes: `git show --stat HEAD`
   - Ensure the commit history is clean and logical
   - Run tests to verify the squashed commit works correctly

### Phase 4: Execute Merge

9. **Perform Clean Merge**:
   - Switch back to master: `git checkout master`
   - Merge the squashed sprint branch: `git merge <target-branch>`
   - If conflicts occur, stop and report them clearly
   - Verify merge commit details and success

10. **Post-Merge Validation**:
   - Run comprehensive tests to ensure nothing broke
   - Verify all sprint files are properly integrated
   - Check that the working directory is clean after merge

### Phase 5: Cleanup

11. **Clean Up Sprint Resources**:
   - Remove worktree if it exists (check in .worktrees/ directory)
   - Delete the sprint branch: `git branch -d <target-branch>`
   - Verify cleanup was successful

12. **Final Verification**:
   - Show final commit history (should show single squashed commit)
   - Run final test to confirm system health
   - Provide summary of what was merged

## Branch Selection Logic

The sprint branch to merge is:
- If argument provided: "{{args[0]}}"
- If no argument: current branch (assume working in worktree)
- Current branch detected as: !`git branch --show-current`

## Error Handling

If any step fails:
- Stop immediately and report the specific error
- Provide clear instructions on how to fix the issue
- Never proceed to the next phase if validation fails
- Offer to abort merge if critical issues are found