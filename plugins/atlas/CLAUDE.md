# Atlas - Company-Aware AI Agent Plugin

> **Read this file first before making any changes to Atlas or using Atlas commands.**

## Overview

Atlas is a Claude Code plugin that connects AI agents to company knowledge repositories and product codebases. It enables autonomous planning and execution of work by providing context-aware AI assistance.

## Quick Start

1. Run `/atlas:setup` to configure Atlas for your organization
2. Use `/atlas:plan "<goal>"` to break down work into GitHub issues
3. Use `/atlas:execute "<task>"` to autonomously work on any task

**Dependency:** `/atlas:execute` requires the `ralph-wiggum` plugin for iteration.

## Project Structure

```
atlas/
├── .claude-plugin/
│   └── manifest.json         # Plugin metadata and commands
├── commands/
│   ├── setup/                # Interactive configuration wizard
│   ├── plan/                 # Goal → GitHub issues breakdown
│   ├── execute/              # Autonomous issue execution loop
│   └── update-knowledge/     # Add documents to knowledge base
├── hooks/                    # Event hooks (pre/post actions)
├── scripts/
│   ├── config-reader.sh      # Read ~/.atlas/config.yaml
│   ├── db/                   # Database and indexing scripts
│   ├── github/               # PR and issue management
│   ├── knowledge/            # Knowledge base querying
│   └── verify/               # Verification scripts
├── CLAUDE.md                 # This file
└── README.md                 # User-facing documentation
```

---

## Configuration

Atlas configuration is stored at `~/.atlas/config.yaml`.

### Reading Configuration

```bash
# Validate and display all config
./scripts/config-reader.sh

# Read specific values
./scripts/config-reader.sh knowledge_repo
./scripts/config-reader.sh github_org
./scripts/config-reader.sh product_repos
./scripts/config-reader.sh vector_db.url
```

### Configuration Keys

| Key | Description | Required |
|-----|-------------|----------|
| `knowledge_repo` | Path to knowledge repository | Yes |
| `github_org` | GitHub organization name | Yes |
| `product_repos` | List of product repository paths | No |
| `vector_db.url` | PostgreSQL connection URL for embeddings | No |
| `verification.screenshots.urls` | URLs to screenshot for verification | No |
| `verification.custom` | Custom verification steps | No |

### Environment Variables

Environment variables in config are interpolated automatically:
```yaml
vector_db:
  url: ${ATLAS_DATABASE_URL}
```

---

## Available Commands

### `/atlas setup`
Interactive wizard to configure Atlas for your organization.

**When to use:** First-time setup or reconfiguring Atlas.

**What it does:**
1. Prompts for GitHub organization
2. Configures knowledge repository path
3. Sets up product repository connections
4. Optionally configures vector database
5. Writes `~/.atlas/config.yaml`

### `/atlas plan "<goal>"`
Transforms a high-level goal into actionable GitHub issues.

**When to use:** Starting new feature work, breaking down projects.

**What it does:**
1. Queries knowledge base for relevant context
2. Analyzes product repositories for patterns
3. Breaks goal into discrete tickets
4. Presents plan for approval
5. Creates GitHub issues when confirmed

**Example:**
```
/atlas plan "Add user authentication with OAuth"
```

### `/atlas execute "<task>" [--issue <number>] [--max-iterations <n>]`
Autonomous task execution powered by Ralph Wiggum's iteration loop.

**When to use:** Working on any task - either described directly or from GitHub issues.

**Two execution modes:**

**Mode 1: Direct Task Description (Recommended)**
```
/atlas:execute "Add a dark mode toggle to settings"
/atlas:execute "Fix the login timeout bug"
```

**Mode 2: GitHub Issue-Based**
```
/atlas:execute --issue 42    # Specific issue
/atlas:execute               # Next available issue
```

**What it does:**
1. Gathers knowledge and codebase context for the task
2. Invokes `/ralph-wiggum:ralph-loop` with full context
3. Ralph iterates until verification passes
4. Creates PR and closes issue (if issue-based)

**Dependency:** Requires the `ralph-wiggum` plugin to be installed.

**Priority order for issue selection (when no task/issue specified):**
1. Issues assigned to current user
2. Issues labeled `atlas` or `automation`
3. Issues labeled `good-first-issue`

### `/atlas update-knowledge <path-or-url>`
Add new documents to the knowledge repository.

**When to use:** Adding documentation, specs, or meeting notes.

**What it does:**
1. Verifies environment (database, API keys)
2. Validates the file or URL
3. Copies to knowledge repo uploads/
4. Extracts text content (PDFs via pdftotext or Claude native)
5. Indexes for semantic search (if database configured)
6. Commits to knowledge repo
7. Reports indexing status

**Supported formats:** `.md`, `.txt`, `.pdf`, `.csv`

**Note:** If database is not configured, files are stored but not searchable. Run `/atlas check-setup` to verify configuration.

### `/atlas check-setup`
Verify Atlas configuration and dependencies.

**When to use:** After initial setup, or when troubleshooting issues.

**What it checks:**
1. Configuration file exists (`~/.atlas/config.yaml`)
2. Knowledge repository exists and is git-initialized
3. Database connection and table existence
4. OpenAI API key (for embeddings)
5. Required tools (psql, curl, jq, git)
6. Optional tools (pdftotext)

**Example output:**
```
Atlas Setup Check
=================

[OK] Config file: ~/.atlas/config.yaml
[OK] Knowledge repo: ~/Projects/company/org (15 files)
[OK] Database: Connected (3 documents, 47 chunks)
[OK] OpenAI API Key: sk-p...Xk4m
[OK] Required tools: psql, curl, jq, git
[--] Optional: pdftotext not found

Status: READY
```

### `/atlas search "<query>"`
Search the knowledge base for relevant information.

**When to use:** Finding specific information, gathering context for planning.

**What it does:**
1. Verifies database is configured
2. Executes semantic search using embeddings
3. Returns ranked results with similarity scores
4. Displays source file paths for attribution

**Options:**
- `--limit N` - Number of results (default: 5)
- `--threshold 0.X` - Minimum similarity (default: 0.7)
- `--format context|json|plain` - Output format

**Example:**
```
/atlas search "Q4 revenue metrics"
/atlas search "authentication" --limit 10 --format json
```

---

## Knowledge Retrieval

### When to Query Knowledge Base

Query the knowledge base when you need:
- Company vision, values, strategy
- Product specifications and roadmaps
- Team processes and runbooks
- Historical decisions and rationale
- Coding standards and guidelines

### How to Query

```bash
./scripts/knowledge/query.sh "your question here"
```

**Options:**
- `--limit <n>` - Number of results (default: 5)
- `--threshold <f>` - Minimum similarity 0-1 (default: 0.7)
- `--format <type>` - Output format: `context`, `json`, `plain`

### Query vs Direct Load

| Scenario | Approach |
|----------|----------|
| Need specific facts about a topic | Query with specific question |
| Need broad context for planning | Query with topic keywords |
| Know exact document location | Read file directly |
| Need multiple related topics | Multiple queries in parallel |

### Example Queries

```bash
# Strategic context
./scripts/knowledge/query.sh "company priorities Q1" --limit 3

# Technical standards
./scripts/knowledge/query.sh "API design guidelines" --format context

# Process documentation
./scripts/knowledge/query.sh "deployment process production" --limit 5

# Programmatic use
./scripts/knowledge/query.sh "authentication" --format json
```

---

## Verification Requirements

Before marking work complete, verification must pass. Atlas uses **prompt-driven verification** - the task defines what "done" means.

### Prompt-Driven Verification

Parse completion criteria from the task/issue description:

```bash
./scripts/verify/verify-criteria.sh --criteria issue-body.txt --repo /path/to/repo
```

Or with JSON criteria:

```bash
./scripts/verify/verify-criteria.sh --criteria '[{"type": "tests"}, {"type": "file_exists", "path": "output.pdf"}]'
```

### Criteria Format

Include a verification section in task descriptions:

```markdown
## Verification
- Command: npm test
- File exists: output/report.pdf
- Contains sections: Summary, Conclusion
- Word count > 500
```

### Supported Criteria Types

| Type | Description | Example |
|------|-------------|---------|
| `command` | Run a command, check exit code 0 | `Command: npm test` |
| `file_exists` | Check file exists | `File exists: dist/app.js` |
| `sections` | Check document has sections | `Contains sections: Summary, Goals` |
| `word_count` | Check document length | `Word count > 500` |
| `tests` | Run test suite | `All tests pass` |
| `build` | Run build | `Build succeeds` |

### Example Verification Criteria

**Web app:**
```markdown
## Verification
- Command: pnpm test
- Command: pnpm build
- All tests pass
```

**iOS app:**
```markdown
## Verification
- Command: xcodebuild test -scheme MyApp
- All tests pass
```

**Strategy document:**
```markdown
## Verification
- File exists: strategy/q1-2026.md
- Contains sections: Executive Summary, Goals, Risks, Timeline
- Word count > 500
```

**No explicit verification:**
```markdown
## Verification
none
```
(Relies on completion promise)

### Legacy Verification

The original verification system is still available:

```bash
./scripts/verify/verify.sh --repo /path/to/repo --format text
```

This auto-detects tests/build for code projects.

### Custom Verification in Config

Add project-wide custom steps in `~/.atlas/config.yaml`:

```yaml
verification:
  screenshots:
    urls:
      - http://localhost:3000
  custom:
    - name: lint
      command: npm run lint
      required: true
```

### Verification Output

```
=== Atlas Verification Report ===
Repository: /path/to/repo

Criteria:
  ✓ command: npm test
  ✓ file_exists: dist/app.js exists
  ✓ word_count: 750 words (> 500)

Overall: ✓ PASSED
```

---

## GitHub Integration

### Creating PRs

```bash
./scripts/github/create-pr.sh \
  --repo owner/repo \
  --issue 42 \
  --verification-report .atlas/verification.json
```

### Updating Issues

```bash
./scripts/github/update-issue.sh \
  --repo owner/repo \
  --issue 42 \
  --status completed \
  --summary "Implemented feature X" \
  --close
```

### Attaching Evidence

```bash
./scripts/github/attach-evidence.sh \
  --repo owner/repo \
  --pr 123 \
  --verification-report .atlas/verification.json \
  --screenshots-dir .atlas/screenshots
```

---

## Error Handling

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "Configuration file not found" | No config | Run `/atlas setup` |
| "yq is required" | Missing dependency | Install: `brew install yq` |
| "Key not found" | Invalid config key | Check config key name |
| "No test runner detected" | Unknown project type | Add test script to package.json |

### When Verification Fails

1. **Tests fail**: Fix the failing tests, do not skip
2. **Build fails**: Resolve compilation errors
3. **Stuck for 3+ iterations**:
   - Post blocker comment on issue
   - Add `needs-human` label
   - Move to next issue

### Error Recovery

If execution is interrupted:
- State is saved to `.atlas/execution-state.json`
- Resume by running `/atlas execute` again
- Manual cleanup: delete `.atlas/execution-state.json`

---

## Development Guidelines

### Adding Commands

1. Create directory: `commands/command-name/`
2. Add prompt file: `command-name.md`
3. Register in `.claude-plugin/manifest.json`
4. Update this file with documentation

### Adding Scripts

1. Create executable script in `scripts/`
2. Add help with `-h|--help` flag
3. Include usage docs at top of file
4. Use `set -e` for error handling

### Code Standards

**DO:**
- Follow existing patterns in codebase
- Test commands locally before committing
- Update CLAUDE.md for new functionality
- Use config-reader for configuration access
- Run verification before marking complete

**DO NOT:**
- Commit sensitive data (API keys, credentials)
- Modify manifest.json without updating docs
- Skip verification to close issues faster
- Mark work complete without passing tests

---

## Execution Loop Best Practices

### Before Starting

1. Ensure config is valid: `./scripts/config-reader.sh`
2. Verify database connection if using vector search
3. Check GitHub authentication: `gh auth status`

### During Execution

1. Read issues carefully before starting
2. Query knowledge base for context
3. Make incremental changes
4. Run verification frequently
5. Update issue with progress

### After Completion

1. Verify all acceptance criteria are met
2. Create PR with clear description
3. Attach verification evidence
4. Close issue with completion comment

### Interrupting Execution

Create stop file to gracefully exit:
```bash
touch .atlas/stop-execution
```
Execution will complete current iteration and save state.

---

## Troubleshooting

### Debug Mode

Set `ATLAS_DEBUG=1` for verbose output:
```bash
ATLAS_DEBUG=1 ./scripts/verify/verify.sh
```

### Checking Logs

```bash
# Recent execution
tail -50 .atlas/execution.log

# Verification output
cat .atlas/verification.json
```

### Resetting State

```bash
# Clear execution state
rm -f .atlas/execution-state.json

# Clear screenshots
rm -rf .atlas/screenshots

# Full reset (keeps config)
rm -rf .atlas/*.json .atlas/screenshots
```
