# Atlas

Company-aware AI agent plugin for Claude Code.

## What is Atlas?

Atlas connects Claude Code to your company's knowledge repositories and product codebases, enabling autonomous planning and execution of work. It provides:

- **Knowledge Integration**: Connect to company documentation, wikis, and knowledge bases
- **Codebase Awareness**: Understand your product architecture and patterns
- **Autonomous Execution**: Plan and execute work with full context
- **Verification**: Ensure work is complete before marking done

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Installation

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- Git
- GitHub CLI (`gh`) authenticated
- yq (for YAML parsing): `brew install yq`
- Optional: PostgreSQL for vector search

### Install Atlas

```bash
# Step 1: Add the Atlas marketplace
claude plugin marketplace add jack-services/atlas

# Step 2: Install the plugin
claude plugin install atlas@atlas-marketplace

# Step 3: Restart Claude Code to load the plugin
```

**Verify Installation**

After restarting Claude Code, the `/atlas:*` commands will be available:
- `/atlas:setup`
- `/atlas:plan`
- `/atlas:execute`
- `/atlas:update-knowledge`
- `/atlas:help`

**Install from Local Clone (for development)**

```bash
# Clone the repository
git clone https://github.com/jack-services/atlas.git

# Add as local marketplace
claude plugin marketplace add /path/to/atlas

# Install the plugin
claude plugin install atlas@atlas-marketplace
```

## Quick Start

### Step 1: Configure Atlas

Run the setup wizard:

```
/atlas:setup
```

The wizard will prompt you for:
- **GitHub Organization**: Your GitHub org name
- **Knowledge Repository**: Path to your company knowledge repo
- **Product Repositories**: Paths to codebases Atlas should understand
- **Vector Database** (optional): PostgreSQL connection for semantic search

### Step 2: Index Your Knowledge

If you have existing documentation:

```
/atlas:update-knowledge ~/docs/company-handbook.md
/atlas:update-knowledge ~/docs/api-spec.pdf
```

### Step 3: Plan Work

Transform goals into actionable GitHub issues:

```
/atlas:plan "Add user authentication with OAuth"
```

Atlas will:
1. Query your knowledge base for relevant context
2. Analyze your codebase for patterns
3. Break the goal into discrete tickets
4. Create GitHub issues when you approve

### Step 4: Execute Work

Work on tasks directly or from GitHub issues:

```
/atlas:execute "Add user avatar upload to the profile page"
```

Or work through GitHub issues:

```
/atlas:execute --issue 42
/atlas:execute  # picks next available issue
```

Atlas will:
1. Gather knowledge and codebase context
2. Invoke Ralph Wiggum's iteration loop
3. Write code iteratively until verification passes
4. Create a PR and close the issue

## Commands

### `/atlas:setup`

Interactive configuration wizard.

```
/atlas:setup
```

Creates `~/.atlas/config.yaml` with your settings.

### `/atlas:plan "<goal>"`

Break down a goal into GitHub issues.

```
/atlas:plan "Implement dark mode for the dashboard"
/atlas:plan "Add rate limiting to the API"
/atlas:plan "Refactor authentication to use JWT"
```

**Options:**
- Presents plan for approval before creating issues
- Links issues with dependencies
- Includes acceptance criteria

### `/atlas:execute`

Autonomously work on tasks using Ralph Wiggum's iteration loop.

**Direct task mode (recommended):**
```
/atlas:execute "Add a dark mode toggle to settings"
/atlas:execute "Fix the password reset bug"
/atlas:execute "Refactor the auth module to use JWT"
```

**Issue-based mode:**
```
/atlas:execute --issue 42         # Work on specific issue
/atlas:execute                    # Pick next issue automatically
/atlas:execute --max-iterations 10  # Limit iterations
```

**Issue selection priority (when no task specified):**
1. Issues assigned to you
2. Issues labeled `atlas` or `automation`
3. Issues labeled `good-first-issue`

**Dependency:** Requires the `ralph-wiggum` plugin:
```bash
claude plugin install ralph-wiggum@claude-code-plugins
```

### `/atlas:update-knowledge <path>`

Add documents to the knowledge base.

```
/atlas:update-knowledge ./docs/spec.md
/atlas:update-knowledge ~/Downloads/meeting-notes.pdf
/atlas:update-knowledge https://docs.google.com/document/d/...
```

**Supported formats:** Markdown, Text, PDF, CSV

### `/atlas:help`

Display available commands and usage information.

```
/atlas:help
```

## Configuration

Configuration is stored at `~/.atlas/config.yaml`.

### Example Configuration

```yaml
# Required settings
knowledge_repo: ~/repos/company-knowledge
github_org: acme-corp

# Product repositories to analyze
product_repos:
  - ~/repos/main-app
  - ~/repos/api-service
  - ~/repos/mobile-app

# Vector database for semantic search (optional)
vector_db:
  url: ${ATLAS_DATABASE_URL}
  table: atlas_embeddings
  dimensions: 1536

# Verification settings (optional)
verification:
  screenshots:
    urls:
      - http://localhost:3000
      - http://localhost:3000/dashboard
  custom:
    - name: lint
      command: npm run lint
      required: true
    - name: typecheck
      command: npm run typecheck
      required: true
```

### Configuration Options

| Key | Description | Required |
|-----|-------------|----------|
| `knowledge_repo` | Path to knowledge repository | Yes |
| `github_org` | GitHub organization name | Yes |
| `product_repos` | List of product repository paths | No |
| `vector_db.url` | PostgreSQL connection URL | No |
| `vector_db.table` | Embeddings table name | No |
| `verification.screenshots.urls` | URLs to capture for visual verification | No |
| `verification.custom` | Custom verification steps | No |

### Environment Variables

Use `${VAR_NAME}` syntax for environment variables in config files:

```yaml
vector_db:
  url: ${ATLAS_DATABASE_URL}
```

Atlas automatically loads environment variables from `.env` files in these locations (in order):

1. `~/.atlas/.env` - User-level configuration
2. Atlas repository `.env` - Project-level configuration
3. Current directory `.env` - Local overrides

**Setting up your .env file:**

```bash
# Copy the example file
cp .env.example .env

# Edit with your credentials
$EDITOR .env
```

**Example .env file:**

```bash
# PostgreSQL connection for vector search
ATLAS_DATABASE_URL=postgresql://user:password@host:5432/dbname?sslmode=require

# OpenAI API key for embeddings (optional)
OPENAI_API_KEY=sk-...
```

> **Security Note:** The `.env` file is gitignored and should never be committed. Use `.env.example` as a template.

## Troubleshooting

### "Configuration file not found"

Run the setup wizard:

```
/atlas:setup
```

Or manually create `~/.atlas/config.yaml`.

### "yq is required but not installed"

Install yq:

```bash
# macOS
brew install yq

# Debian/Ubuntu
apt install yq

# Snap
snap install yq
```

### "GitHub authentication failed"

Authenticate the GitHub CLI:

```bash
gh auth login
```

### "No test runner detected"

Atlas couldn't detect your test framework. Ensure your project has:

- `package.json` with a `test` script (Node.js)
- `pytest.ini` or `tests/` directory (Python)
- `Cargo.toml` (Rust)
- `go.mod` (Go)
- `Makefile` with a `test` target

### "Vector database connection failed"

1. Verify your PostgreSQL is running
2. Check the connection URL in config
3. Ensure the `pgvector` extension is installed:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### Execution seems stuck

Check the execution state:

```bash
cat .atlas/execution-state.json
```

Reset if needed:

```bash
rm -f .atlas/execution-state.json
```

### How to stop execution

Create a stop file:

```bash
touch .atlas/stop-execution
```

Atlas will complete the current iteration and exit.

## Project Structure

```
atlas/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace metadata
├── plugins/
│   └── atlas/
│       ├── .claude-plugin/
│       │   └── plugin.json   # Plugin metadata
│       ├── commands/
│       │   ├── setup.md      # Configuration wizard
│       │   ├── plan.md       # Goal → issues breakdown
│       │   ├── execute.md    # Autonomous execution loop
│       │   ├── update-knowledge.md  # Knowledge ingestion
│       │   └── help.md       # Help command
│       ├── scripts/
│       │   ├── config-reader.sh      # Config management
│       │   ├── db/                   # Database scripts
│       │   ├── github/               # PR/issue management
│       │   ├── knowledge/            # Knowledge querying
│       │   └── verify/               # Verification scripts
│       ├── hooks/            # Event hooks
│       └── CLAUDE.md         # Agent instructions
├── CLAUDE.md                 # Project instructions
└── README.md                 # This file
```

## Contributing

We welcome contributions! Here's how to get started:

### Development Setup

1. Fork and clone the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make changes following the patterns in CLAUDE.md
4. Test your changes locally
5. Submit a pull request

### Guidelines

- Follow existing code patterns
- Add documentation for new features
- Include tests where applicable
- Update CLAUDE.md for agent-facing changes
- Update README.md for user-facing changes

### Adding Commands

1. Create file: `plugins/atlas/commands/your-command.md`
2. Document in CLAUDE.md and README.md
3. Commands are auto-discovered by filename (e.g., `foo.md` → `/atlas:foo`)

### Adding Scripts

1. Create executable in `scripts/`
2. Add `--help` flag with usage info
3. Include usage docs at top of file
4. Use `set -e` for error handling

### Code Standards

- Shell scripts: POSIX-compatible where possible
- Error handling: Always check for failures
- Documentation: Comment complex logic
- Security: Never commit credentials

## License

MIT
