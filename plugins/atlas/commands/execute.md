# Atlas Execute Command

Ralph-style iterative execution loop for autonomously working through GitHub issues.

## Usage

```
/atlas execute [--issue <number>] [--max-iterations <n>]
```

## Examples

```
/atlas execute                          # Pick next assigned issue
/atlas execute --issue 42               # Work on specific issue
/atlas execute --max-iterations 10      # Limit iteration count
```

## Workflow

When this command is invoked, follow these steps:

### Step 1: Load Configuration

```bash
# Get GitHub org from config
GITHUB_ORG=$(./scripts/config-reader.sh github_org)

# Get product repos
PRODUCT_REPOS=$(./scripts/config-reader.sh product_repos)
```

If config doesn't exist, guide user to run `/atlas setup` first.

### Step 2: Select Issue to Work On

If `--issue` is provided, fetch that specific issue:

```bash
gh issue view {number} --repo "$GITHUB_ORG/{repo}" --json number,title,body,labels,assignees
```

Otherwise, query for the next available issue:

```bash
# Get assigned issues first
gh issue list --repo "$GITHUB_ORG/{repo}" --assignee @me --state open --json number,title,labels --limit 10

# If no assigned issues, get issues labeled for atlas
gh issue list --repo "$GITHUB_ORG/{repo}" --label "atlas" --state open --json number,title,labels --limit 10
```

Priority order for issue selection:
1. Issues assigned to current user
2. Issues labeled with `atlas` or `automation`
3. Issues labeled with `good-first-issue`

### Step 3: Gather Context

#### 3a. Issue Context
Parse the issue body for:
- Description and requirements
- Acceptance criteria (checkboxes)
- Referenced files or areas
- Related issues or PRs

#### 3b. Knowledge Context
Query the knowledge base for relevant information:

```bash
# Query based on issue title and description keywords
./scripts/knowledge/query.sh "{issue title}" --limit 5 --format context

# Get any company-specific guidelines
./scripts/knowledge/query.sh "coding standards guidelines" --limit 3 --format context
```

#### 3c. Codebase Context
For each relevant product repo:
1. Read README and understand project structure
2. Identify files mentioned in the issue
3. Find similar implementations for reference
4. Note testing patterns

### Step 4: Create Execution Plan

Based on gathered context, create a plan:

1. List specific files to create or modify
2. Identify tests to write or update
3. Note any dependencies or blockers
4. Define verification steps

Post initial plan as issue comment:

```bash
gh issue comment {number} --repo "$GITHUB_ORG/{repo}" --body "## 🤖 Atlas Execution Started

### Plan
{execution plan}

### Context Used
- Knowledge: {knowledge sources}
- Files: {relevant files}

---
*Iteration 1 of {max_iterations}*"
```

### Step 5: Execute Iteratively

Enter the execution loop:

```
ITERATION = 1
MAX_ITERATIONS = --max-iterations or 20 (default)

while ITERATION <= MAX_ITERATIONS:
    1. Work on the current task from the plan
    2. Make changes to files
    3. Run tests if applicable
    4. Check acceptance criteria

    if all_criteria_met():
        break

    ITERATION += 1

    # Post progress every 5 iterations
    if ITERATION % 5 == 0:
        post_progress_comment()
```

#### Iteration Actions

Each iteration should:
1. Review current state
2. Identify next action
3. Execute action (write code, fix bug, add test)
4. Verify the action succeeded
5. Update internal state

Use the TodoWrite tool to track progress within the execution loop.

### Step 6: Verify Completion

Before marking complete, verify:

1. **All acceptance criteria checked**: Parse issue body for `- [ ]` items, ensure all are satisfiable
2. **Tests pass**: Run test suite if present
3. **Build succeeds**: Run build command if present
4. **No lint errors**: Run linter if configured

```bash
# Example verification commands
npm test 2>&1 || echo "TESTS_FAILED"
npm run build 2>&1 || echo "BUILD_FAILED"
npm run lint 2>&1 || echo "LINT_FAILED"
```

If verification fails, continue iterating to fix issues.

### Step 7: Create Pull Request

If working in a product repo, create a PR:

```bash
# Create branch for the work
git checkout -b atlas/issue-{number}

# Stage and commit changes
git add -A
git commit -m "feat: {issue title}

Closes #{number}

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push and create PR
git push -u origin atlas/issue-{number}

gh pr create \
  --repo "$GITHUB_ORG/{repo}" \
  --title "{issue title}" \
  --body "## Summary
{summary of changes}

## Changes
{list of changed files}

## Testing
{testing performed}

Closes #{number}

---
*Created by Atlas /execute command*"
```

### Step 8: Update Issue

Post completion comment and close if appropriate:

```bash
gh issue comment {number} --repo "$GITHUB_ORG/{repo}" --body "## ✅ Atlas Execution Complete

### Summary
{what was accomplished}

### Changes Made
{list of files modified}

### Verification
- Tests: {pass/fail}
- Build: {pass/fail}
- Lint: {pass/fail}

### Pull Request
{PR URL if created}

---
*Completed in {iteration_count} iterations*"
```

If all verification passes and PR is created:

```bash
gh issue close {number} --repo "$GITHUB_ORG/{repo}" --comment "Completed by Atlas. PR: {pr_url}"
```

## Execution State

Track execution state in `.atlas/execution-state.json`:

```json
{
  "issue_number": 42,
  "repo": "org/repo",
  "started_at": "2024-01-15T10:30:00Z",
  "iteration": 5,
  "max_iterations": 20,
  "plan": ["task1", "task2", "task3"],
  "completed_tasks": ["task1"],
  "current_task": "task2",
  "verification": {
    "tests": null,
    "build": null,
    "lint": null
  }
}
```

This allows resuming execution if interrupted.

## Error Handling

### Stuck Detection
If the same error occurs 3+ times:
1. Post a comment describing the blocker
2. Label issue with `needs-human`
3. Move to next issue or exit

### Max Iterations Reached
If max iterations reached without completion:
1. Post progress comment with current state
2. List remaining tasks
3. Ask user whether to continue or pause

### API Failures
If GitHub API calls fail:
1. Retry with exponential backoff
2. After 3 failures, exit gracefully with state saved

## Configuration

Uses settings from `~/.atlas/config.yaml`:

```yaml
github_org: your-org
product_repos:
  - ~/repos/main-app
execution:
  max_iterations: 20
  progress_interval: 5
  auto_close_issues: true
  create_prs: true
```

## Best Practices

1. **Start Small**: Test with simple issues first
2. **Set Limits**: Use `--max-iterations` to prevent runaway execution
3. **Review Progress**: Check issue comments for execution updates
4. **Clear Criteria**: Issues with clear acceptance criteria work best
5. **Label Appropriately**: Use `atlas` label for automation-ready issues

## Interrupt Handling

To stop execution:
1. The loop checks for a `.atlas/stop-execution` file
2. Create this file to gracefully stop: `touch .atlas/stop-execution`
3. Execution will complete current iteration and exit
4. State is saved for potential resume
