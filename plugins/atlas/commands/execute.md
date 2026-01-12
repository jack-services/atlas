# Atlas Execute Command

Autonomously work on tasks using Ralph Wiggum's iteration loop.

## Usage

```
/atlas:execute "<task description>"           # Work on described task
/atlas:execute --issue <number>               # Work on specific GitHub issue
/atlas:execute                                # Pick next available issue
/atlas:execute "<task>" --max-iterations <n>  # Limit iterations
```

## Examples

```
/atlas:execute "Add a dark mode toggle to the settings page"
/atlas:execute "Refactor the authentication module to use JWT"
/atlas:execute "Fix the bug where users can't reset their password"
/atlas:execute --issue 42
/atlas:execute --max-iterations 10
```

## Execution Modes

Atlas supports two execution modes:

### Mode 1: Direct Task Description (Recommended)

When you provide a task description in quotes, Atlas works on exactly what you describe:

```
/atlas:execute "Add user avatar upload to the profile page"
```

This mode:
- Uses your description as the primary task
- Gathers relevant knowledge context
- Invokes Ralph Wiggum to iterate until complete
- Creates a PR when done (if in a git repo)

### Mode 2: GitHub Issue-Based

When you use `--issue` or provide no arguments, Atlas works from GitHub issues:

```
/atlas:execute --issue 42    # Specific issue
/atlas:execute               # Next available issue
```

Issue selection priority (when no issue specified):
1. Issues assigned to current user
2. Issues labeled with `atlas` or `automation`
3. Issues labeled with `good-first-issue`

---

## Workflow

When this command is invoked, follow these steps:

### Step 1: Load Configuration

```bash
# Get GitHub org from config
GITHUB_ORG=$(./scripts/config-reader.sh github_org)

# Get product repos
PRODUCT_REPOS=$(./scripts/config-reader.sh product_repos)
```

If config doesn't exist, guide user to run `/atlas:setup` first.

### Step 2: Determine Task Source

**If task description provided** (e.g., `"Add dark mode"`):
- Use the description as the task
- Set `TASK_MODE=direct`
- Set `TASK_DESCRIPTION` to the provided text

**If `--issue` provided**:
- Fetch that specific issue
- Set `TASK_MODE=issue`
- Extract task from issue body

**If no arguments**:
- Query for next available issue
- Set `TASK_MODE=issue`
- Extract task from issue body

```bash
# For issue mode
gh issue view {number} --repo "$GITHUB_ORG/{repo}" --json number,title,body,labels,assignees
```

### Step 3: Gather Context

#### 3a. Task Context
For direct mode:
- Parse the task description for key requirements
- Identify any mentioned files, features, or components

For issue mode:
- Parse the issue body for requirements
- Extract acceptance criteria (checkboxes)
- Extract verification section

#### 3b. Knowledge Context
Query the knowledge base for relevant information:

```bash
# Query based on task keywords
./scripts/knowledge/query.sh "{task keywords}" --limit 5 --format context

# Get any company-specific guidelines
./scripts/knowledge/query.sh "coding standards guidelines" --limit 3 --format context
```

#### 3c. Codebase Context
For each relevant product repo:
1. Read README and understand project structure
2. Identify files relevant to the task
3. Find similar implementations for reference
4. Note testing patterns

### Step 4: Construct Ralph Loop Prompt

Build a comprehensive prompt that includes all gathered context.

**For direct task mode:**

```
Work on the following task:

## Task
{task description}

## Knowledge Context
{knowledge query results}

## Codebase Context
{relevant files and patterns}

## Verification
{infer from task or use defaults: tests pass, build succeeds}

## Instructions
1. Implement the changes described in the task
2. Follow existing patterns in the codebase
3. Write tests if applicable
4. Run verification to ensure completion
5. Create a PR when done

Completion criteria: The task is fully implemented and verified.
```

**For issue mode:**

```
Work on GitHub issue #{number}: {title}

## Issue Description
{issue body}

## Knowledge Context
{knowledge query results}

## Codebase Context
{relevant files and patterns}

## Verification Criteria
{parsed from issue body or defaults}

## Instructions
1. Implement the changes described in the issue
2. Follow existing patterns in the codebase
3. Write tests if applicable
4. Run verification to ensure completion
5. Create a PR when done

When complete, close the issue with: gh issue close {number}
```

### Step 5: Invoke Ralph Wiggum Loop

Use the Skill tool to invoke Ralph Wiggum with the constructed prompt:

**For direct task mode:**
```
/ralph-wiggum:ralph-loop "{constructed_prompt}" --max-iterations {max_iterations} --completion-promise "Task complete: {summary of task}"
```

**For issue mode:**
```
/ralph-wiggum:ralph-loop "{constructed_prompt}" --max-iterations {max_iterations} --completion-promise "Issue #{number} is closed"
```

**IMPORTANT**: You MUST use the Skill tool to invoke `/ralph-wiggum:ralph-loop`. Do not attempt to implement your own iteration loop.

Example invocations:

```
# Direct task
Skill: ralph-wiggum:ralph-loop
Args: Work on task: Add dark mode toggle... --max-iterations 20 --completion-promise "Task complete: dark mode toggle added"

# Issue-based
Skill: ralph-wiggum:ralph-loop
Args: Work on issue #42: Add user authentication... --max-iterations 20 --completion-promise "Issue #42 is closed"
```

### Step 6: Post-Execution

**For direct task mode:**
- Summarize what was accomplished
- List files changed
- Provide PR link if created

**For issue mode:**
Post completion comment and close:

```bash
gh issue comment {number} --repo "$GITHUB_ORG/{repo}" --body "## ✅ Atlas Execution Complete

### Summary
{what was accomplished}

### Changes Made
{list of files modified}

### Pull Request
{PR URL if created}

---
*Completed via Atlas + Ralph Wiggum*"

gh issue close {number}
```

## Error Handling

### Task Unclear
If the task description is too vague, ask for clarification before starting.

### Issue Not Found
If the specified issue doesn't exist, inform the user and exit.

### No Issues Available
If no issues match the selection criteria, inform the user:
- Suggest using direct task mode instead
- Or create issues with `atlas` label
- Or assign existing issues to themselves

### Ralph Loop Exits Early
If Ralph exits without completing:
1. Check what was accomplished
2. Either resume with the same command or investigate blockers

## Configuration

Uses settings from `~/.atlas/config.yaml`:

```yaml
github_org: your-org
product_repos:
  - ~/repos/main-app
execution:
  max_iterations: 20
```

## Best Practices

1. **Be Specific**: Clear task descriptions yield better results
2. **Include Verification**: Mention how to verify completion (e.g., "tests should pass")
3. **Reasonable Scope**: One feature/fix per execution
4. **Set Limits**: Use `--max-iterations` to prevent runaway execution

## Dependency

This command requires the `ralph-wiggum` plugin to be installed and enabled.

```bash
claude plugin install ralph-wiggum@claude-code-plugins
```
