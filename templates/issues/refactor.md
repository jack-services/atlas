# Refactoring Issue Template

Use this template when Atlas creates refactoring issues.

## Template

```markdown
## Context

{Why this refactoring is needed - tech debt, maintainability, performance}

## Current State

{Description of current implementation and its problems}

## Proposed Changes

{High-level description of the refactoring approach}

## Tasks

- [ ] {Specific refactoring task 1}
- [ ] {Specific refactoring task 2}
- [ ] {Specific refactoring task 3}
- [ ] Update affected tests
- [ ] Update documentation if needed
- [ ] Verify no behavior changes (unless intentional)

## Acceptance Criteria

- [ ] Existing tests still pass
- [ ] No behavior changes (unless specified)
- [ ] Code follows project conventions
- [ ] {Specific improvement metric if applicable}

## Verification Steps

1. Run full test suite: `{test command}`
2. Compare behavior before/after refactoring
3. {Additional verification for specific changes}

## Technical Notes

### Files to Modify

- `{path/to/file1}` - {what changes}
- `{path/to/file2}` - {what changes}

### Breaking Changes

{List any breaking changes if applicable, or "None expected"}

### Migration Notes

{Any migration steps if needed}

## Labels

- `type:refactor`
- `{area label}`

---
*Created by Atlas /plan command*
```

## Usage Guidelines

1. **Justification**: Clearly explain why refactoring is worth the effort
2. **Scope**: Keep refactors focused; split large refactors into phases
3. **Testing**: Refactors should not change behavior unless specified
4. **Breaking Changes**: Call out any API/interface changes
