# Bug Fix Issue Template

Use this template when Atlas creates bug fix issues.

## Template

```markdown
## Bug Description

{Clear description of the bug and its impact}

## Expected Behavior

{What should happen}

## Current Behavior

{What actually happens}

## Reproduction Steps

1. {Step 1}
2. {Step 2}
3. {Step 3}

## Root Cause Analysis

{Hypothesis or known cause if identified}

## Tasks

- [ ] Reproduce the bug locally
- [ ] Identify root cause
- [ ] Implement fix
- [ ] Add regression test
- [ ] Verify fix in staging/preview

## Acceptance Criteria

- [ ] Bug no longer occurs following reproduction steps
- [ ] Regression test added and passing
- [ ] No new bugs introduced
- [ ] Fix works across {relevant browsers/platforms}

## Verification Steps

1. Follow reproduction steps above
2. Verify expected behavior occurs
3. Run test suite: `{test command}`
4. Check related functionality still works

## Technical Notes

### Relevant Files

- `{path/to/file}:{line}` - {suspected location}
- `{path/to/test}` - {existing tests if any}

### Related Issues

- #{issue_number} - {if related}

## Labels

- `type:bug`
- `priority:{high|medium|low}`
- `{area label}`

---
*Created by Atlas /plan command*
```

## Usage Guidelines

1. **Reproduction**: Must be specific enough to reproduce reliably
2. **Root Cause**: Include hypothesis if not confirmed
3. **Regression Test**: Always require a test to prevent recurrence
4. **Priority**: Set based on impact and frequency
