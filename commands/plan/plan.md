# Atlas Plan Command

Transform high-level goals into actionable GitHub issues with full company context.

## Usage

```
/atlas plan "<goal description>"
```

## Examples

```
/atlas plan "Add user authentication to the app"
/atlas plan "Improve dashboard performance"
/atlas plan "Add dark mode support"
```

## Workflow

When this command is invoked, follow these steps:

### Step 1: Parse the Goal

Extract the goal description from the command arguments. The goal should be a high-level description of what needs to be accomplished.

### Step 2: Gather Company Context

Query the knowledge base for relevant context:

```bash
# Get strategic context
./scripts/knowledge/query.sh "company priorities strategy" --limit 3 --format context

# Get relevant constraints or guidelines
./scripts/knowledge/query.sh "{goal keywords}" --limit 5 --format context
```

Include this context when generating the plan to ensure alignment with company strategy.

### Step 3: Analyze Product Repositories

For each product repo in the config:

```bash
# Get repo paths from config
REPOS=$(./scripts/config-reader.sh product_repos)
```

For each relevant repo:
1. Read the README to understand the project
2. Explore the codebase structure
3. Identify files that would be affected
4. Note existing patterns and conventions

Use the Glob and Read tools to explore:
- `src/` or main source directory
- Existing similar features
- Test patterns
- Configuration files

### Step 4: Break Down into Tickets

Based on the gathered context, decompose the goal into discrete, actionable tickets. Each ticket should:

1. Be completable in a single PR
2. Have clear acceptance criteria
3. Reference specific files when relevant
4. Include necessary context from knowledge base
5. Follow the company's issue conventions

Recommended ticket structure:
- **Research/Discovery** ticket if needed
- **Implementation** tickets (feature work)
- **Testing** tickets if complex
- **Documentation** ticket if user-facing

### Step 5: Present Plan to User

Before creating issues, present the plan:

```
## Proposed Plan for: {goal}

Based on company context and codebase analysis:

### Context from Knowledge Base
{relevant snippets}

### Affected Files/Areas
{list of relevant files}

### Proposed Tickets

1. **[Title]**
   - Description: ...
   - Acceptance Criteria: ...
   - Files: ...

2. **[Title]**
   ...
```

Ask the user to confirm or modify the plan using AskUserQuestion:
- "Create all issues as proposed"
- "Let me modify the plan first"
- "Cancel"

### Step 6: Create GitHub Issues

If user confirms, create issues using GitHub MCP or gh CLI:

```bash
# Get GitHub org from config
GITHUB_ORG=$(./scripts/config-reader.sh github_org)

# Create each issue
gh issue create \
  --repo "$GITHUB_ORG/{repo}" \
  --title "{ticket title}" \
  --body "{ticket body}"
```

Issue body template:
```markdown
## Description
{description}

## Context
{relevant knowledge base snippets}

## Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}
- [ ] {criterion 3}

## Relevant Files
{list of affected files}

---
*Created by Atlas /plan command*
```

### Step 7: Report Results

After creating issues, report:
- List of created issues with URLs
- Any issues that failed to create
- Suggested order of implementation

## Configuration

Uses settings from `~/.atlas/config.yaml`:

```yaml
github_org: your-org
product_repos:
  - ~/repos/main-app
knowledge_repo: ~/repos/company-knowledge
```

## Best Practices

1. **Start Specific**: More specific goals produce better plans
2. **Provide Context**: Mention relevant constraints or requirements
3. **Review Before Creating**: Always review the proposed tickets
4. **Iterate**: Run multiple times to refine the plan

## Error Handling

- Missing config: Guide user to run `/atlas setup`
- No knowledge context: Proceed with codebase analysis only
- Issue creation fails: Show error, offer to retry
