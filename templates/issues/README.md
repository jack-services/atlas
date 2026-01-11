# Atlas Issue Templates

This directory contains templates for GitHub issues created by Atlas commands.

## Available Templates

| Template | Use Case |
|----------|----------|
| `feature.md` | New functionality implementation |
| `bug.md` | Bug fixes and defect resolution |
| `refactor.md` | Code improvements without behavior changes |
| `research.md` | Investigation and discovery work |

## Template Structure

All templates follow a consistent structure:

1. **Context** - Why this work matters
2. **Tasks** - Checkboxes for trackable work items
3. **Acceptance Criteria** - What defines "done"
4. **Verification Steps** - How to verify completion
5. **Related Files** - Code references
6. **Labels** - Suggested labels to apply

## Using Templates

Atlas commands automatically select the appropriate template based on issue type. The `/atlas plan` command will:

1. Analyze the goal to determine issue type(s)
2. Select appropriate template(s)
3. Fill in template fields with context
4. Present for user review before creating

## Customizing Templates

To customize templates for your organization:

1. Copy the template you want to modify
2. Edit to match your team's conventions
3. Atlas will use the modified templates

## Best Practices

- **Be Specific**: Vague issues lead to confusion
- **Include Context**: Help future readers understand the "why"
- **Link Related Work**: Reference related issues and PRs
- **Keep Atomic**: One issue = one logical unit of work
