# Atlas Ralph Prompts

## Test Run (Single Ticket)

Use this first to verify the workflow works:

```bash
/ralph-loop "You are building Atlas, a Claude Code plugin for company-aware AI agents.

WORKFLOW:
1. Check GitHub issues: gh issue list --repo jack-services/atlas --state open --json number,title
2. Pick the lowest numbered open issue
3. Read the issue details: gh issue view <number> --repo jack-services/atlas
4. Implement what the issue requires
5. Test your work (run any tests, verify files exist, etc.)
6. Commit changes with message referencing the issue (e.g., 'Implement plugin structure - closes #1')
7. Push to main
8. Close the issue: gh issue close <number> --repo jack-services/atlas --comment 'Completed by Ralph'
9. Output: <promise>TICKET_COMPLETE</promise>

RULES:
- One ticket per loop iteration
- Read the issue carefully before starting
- Test your work before committing
- If blocked, comment on the issue explaining why and skip to next ticket
- Reference the jack codebase at ../jack for patterns if needed
- Use GitHub MCP or gh CLI for all GitHub operations

CONTEXT:
- Atlas is a generic, open-source Claude Code plugin
- It connects to a company knowledge repo and product codebases
- It enables autonomous planning and execution of work
- See ../jack/CLAUDE.md for coding patterns to follow" --completion-promise "TICKET_COMPLETE" --max-iterations 30
```

## Full Run (All Tickets)

Once the test run works, use this to process all tickets:

```bash
/ralph-loop "You are building Atlas, a Claude Code plugin for company-aware AI agents.

WORKFLOW:
1. Check GitHub issues: gh issue list --repo jack-services/atlas --state open --json number,title
2. If no open issues, output <promise>ALL_TICKETS_COMPLETE</promise>
3. Pick the lowest numbered open issue
4. Read the issue details: gh issue view <number> --repo jack-services/atlas
5. Implement what the issue requires
6. Test your work (run any tests, verify files exist, etc.)
7. Commit changes with message referencing the issue (e.g., 'Implement plugin structure - closes #1')
8. Push to main
9. Close the issue: gh issue close <number> --repo jack-services/atlas --comment 'Completed by Ralph'
10. Loop back to step 1

RULES:
- One ticket per iteration
- Read the issue carefully before starting
- Test your work before committing
- If stuck on a ticket for more than 5 attempts, comment on the issue with blockers and skip to next
- Reference the jack codebase at ../jack for patterns if needed
- Use GitHub MCP or gh CLI for all GitHub operations

CONTEXT:
- Atlas is a generic, open-source Claude Code plugin
- It connects to a company knowledge repo and product codebases
- It enables autonomous planning and execution of work
- See ../jack/CLAUDE.md for coding patterns to follow

PHASES (for reference):
- Phase 1 (#1-2): Plugin skeleton
- Phase 2 (#3-4): Setup wizard
- Phase 3 (#5-6): Vector DB integration
- Phase 4 (#7-8): Knowledge management
- Phase 5 (#9-10): Planning system
- Phase 6 (#11-13): Execution loop
- Phase 7 (#14-15): Documentation" --completion-promise "ALL_TICKETS_COMPLETE" --max-iterations 300
```

## Quick Commands

```bash
# Check progress
gh issue list --repo jack-services/atlas --state all

# See what's done
gh issue list --repo jack-services/atlas --state closed

# See what's left
gh issue list --repo jack-services/atlas --state open

# Cancel ralph mid-run
/cancel-ralph
```
