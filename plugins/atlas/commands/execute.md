# Atlas Execute Command

Search for and work through GitHub issues using Ralph Wiggum's iteration loop.

## Usage

```
/atlas:execute "<search query>"              # Search issues and work on matches
/atlas:execute --issue <number>              # Work on specific issue
/atlas:execute                               # Pick next available issue
/atlas:execute "<query>" --max-iterations <n>  # Limit iterations
```

## Examples

```
/atlas:execute "authentication"              # Find and work on auth-related issues
/atlas:execute "fix login bug"               # Search for login bug issues
/atlas:execute "dark mode"                   # Find dark mode issues
/atlas:execute --issue 42                    # Work on specific issue #42
/atlas:execute                               # Pick next assigned/labeled issue
```

## How It Works

When you provide a search query, Atlas:
1. Searches open GitHub issues matching your description
2. Presents matching issues for you to select
3. Works through selected issues using Ralph Wiggum's loop

---

## Workflow

When this command is invoked, follow these steps:

### Step 1: Load Configuration

```bash
# Get GitHub org from config
GITHUB_ORG=$(./scripts/config-reader.sh github_org)

# Get default repo (or use current directory's repo)
DEFAULT_REPO=$(./scripts/config-reader.sh default_repo 2>/dev/null || basename $(pwd))
```

If config doesn't exist, guide user to run `/atlas:setup` first.

### Step 2: Determine Execution Mode

**If search query provided** (e.g., `"authentication"`):
- Set `MODE=search`
- Search for matching issues

**If `--issue <number>` provided**:
- Set `MODE=specific`
- Fetch that exact issue

**If no arguments**:
- Set `MODE=auto`
- Get next available issue by priority

### Step 3: Search for Issues (Search Mode)

When a search query is provided, search GitHub issues:

```bash
# Search open issues matching the query
gh issue list \
  --repo "$GITHUB_ORG/$REPO" \
  --state open \
  --search "$SEARCH_QUERY" \
  --json number,title,body,labels,assignees \
  --limit 10
```

**Present results to user:**

```
Found 5 issues matching "authentication":

1. #42 - Add OAuth2 authentication flow
   Labels: feature, auth

2. #38 - Fix session timeout on login
   Labels: bug, auth

3. #35 - Implement password reset endpoint
   Labels: feature, auth

4. #29 - Add rate limiting to auth endpoints
   Labels: security, auth

5. #15 - Update auth documentation
   Labels: docs

Which issue(s) would you like to work on? (Enter numbers, e.g., "1" or "1,2,3")
```

Use the AskUserQuestion tool to let the user select which issues to work on.

**If no issues match:**
```
No open issues found matching "authentication".

Suggestions:
- Try different search terms
- Check if issues exist: gh issue list --repo org/repo
- Use /atlas:execute --issue <number> for a specific issue
```

### Step 4: Select Issue (Auto Mode)

When no query is provided, select by priority:

```bash
# Priority 1: Assigned to current user
gh issue list --repo "$GITHUB_ORG/$REPO" --assignee @me --state open --limit 5

# Priority 2: Labeled for atlas automation
gh issue list --repo "$GITHUB_ORG/$REPO" --label "atlas" --state open --limit 5

# Priority 3: Good first issues
gh issue list --repo "$GITHUB_ORG/$REPO" --label "good-first-issue" --state open --limit 5
```

### Step 5: Gather Context for Selected Issue

Once an issue is selected:

#### 5a. Issue Context
Parse the issue body for:
- Description and requirements
- Acceptance criteria (checkboxes)
- Verification section (what "done" means)
- Referenced files or areas
- Related issues or PRs

#### 5b. Knowledge Context
Query the knowledge base for relevant information:

```bash
# Query based on issue title and keywords
./scripts/knowledge/query.sh "{issue title}" --limit 5 --format context

# Get coding guidelines
./scripts/knowledge/query.sh "coding standards" --limit 3 --format context
```

#### 5c. Codebase Context
For relevant product repos:
1. Read README and project structure
2. Identify files mentioned in the issue
3. Find similar implementations
4. Note testing patterns

### Step 6: Construct Ralph Loop Prompt

Build a comprehensive prompt with all context:

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

### Step 7: Invoke Ralph Wiggum Loop

Use the Skill tool to invoke Ralph Wiggum:

```
/ralph-wiggum:ralph-loop "{constructed_prompt}" --max-iterations {max_iterations} --completion-promise "Issue #{number} is closed"
```

**IMPORTANT**: You MUST use the Skill tool to invoke `/ralph-wiggum:ralph-loop`. Do not implement your own iteration loop.

Example:
```
Skill: ralph-wiggum:ralph-loop
Args: Work on issue #42: Add OAuth2 authentication... --max-iterations 20 --completion-promise "Issue #42 is closed"
```

### Step 8: Post-Execution

After Ralph completes (issue closed), post a summary:

```bash
gh issue comment {number} --repo "$GITHUB_ORG/$REPO" --body "## ✅ Atlas Execution Complete

### Summary
{what was accomplished}

### Changes Made
{list of files modified}

### Pull Request
{PR URL if created}

---
*Completed via Atlas + Ralph Wiggum*"
```

### Step 9: Continue to Next Issue (if multiple selected)

If user selected multiple issues (e.g., "1,2,3"):
1. After completing first issue, move to next
2. Repeat steps 5-8 for each issue
3. Report final summary when all complete

---

## Error Handling

### No Matching Issues
If search returns no results:
- Suggest alternative search terms
- Offer to list all open issues
- Suggest creating a new issue

### Issue Not Found
If `--issue <number>` doesn't exist:
- Inform user and exit
- Suggest searching instead

### No Issues Available (Auto Mode)
If no assigned or labeled issues exist:
- Inform user
- Suggest using search mode
- Suggest creating issues with `atlas` label

### Ralph Loop Exits Early
If Ralph exits without closing the issue:
1. Check what was accomplished
2. Either resume with `/atlas:execute --issue {number}` or investigate blockers

---

## Configuration

Uses settings from `~/.atlas/config.yaml`:

```yaml
github_org: your-org
default_repo: main-app
product_repos:
  - ~/repos/main-app
execution:
  max_iterations: 20
```

## Best Practices

1. **Be Descriptive**: Search queries like "fix login" work better than "bug"
2. **Use Labels**: Label issues with `atlas` for easy auto-selection
3. **Clear Verification**: Issues with `## Verification` sections work best
4. **Reasonable Scope**: One issue at a time for complex work

## Dependency

This command requires the `ralph-wiggum` plugin:

```bash
claude plugin install ralph-wiggum@claude-code-plugins
```
