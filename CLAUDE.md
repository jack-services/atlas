# Atlas - Company-Aware AI Agent Plugin

> **Read this file first before making any changes to Atlas.**

## Overview

Atlas is a Claude Code plugin that connects AI agents to company knowledge repositories and product codebases. It enables autonomous planning and execution of work by providing context-aware AI assistance.

## Project Structure

```
atlas/
├── .claude-plugin/
│   └── manifest.json       # Plugin metadata and configuration
├── commands/               # Slash command implementations
├── hooks/                  # Event hooks (pre/post command execution)
├── scripts/                # Utility scripts for setup and maintenance
├── CLAUDE.md               # This file - plugin instructions
└── README.md               # Project overview and setup
```

## Plugin Architecture

Atlas follows the Claude Code plugin specification:

- **Commands**: Registered slash commands that extend Claude Code functionality
- **Hooks**: Event handlers that run before/after specific actions
- **Scripts**: Shell scripts for automation and setup tasks

## Development Guidelines

### Adding Commands

Commands are defined in the `commands/` directory. Each command should:

1. Have a clear, single purpose
2. Include proper validation and error handling
3. Follow the naming convention: `command-name.md` or `command-name/`

### Adding Hooks

Hooks in the `hooks/` directory respond to Claude Code events:

1. Use descriptive names matching the event they handle
2. Keep hooks lightweight and fast
3. Handle errors gracefully to avoid blocking execution

### Scripts

Utility scripts in `scripts/` should:

1. Be executable (`chmod +x`)
2. Include usage documentation at the top
3. Follow shell scripting best practices

## DO NOT

1. Commit sensitive data (API keys, credentials)
2. Modify manifest.json structure without updating docs
3. Create commands without proper error handling

## DO

1. Follow existing patterns in the codebase
2. Test commands locally before committing
3. Update CLAUDE.md when adding new functionality
4. Write clear, concise code

## Knowledge Retrieval

Atlas can query company knowledge to provide context-aware assistance. Use the knowledge retrieval system when you need information about:

- Company vision, values, and strategy
- Product specifications and roadmaps
- Team processes and runbooks
- Historical decisions and rationale

### How to Query Knowledge

Run the query script to retrieve relevant context:

```bash
./scripts/knowledge/query.sh "your question here"
```

Options:
- `--limit <n>` - Number of results (default: 5)
- `--threshold <f>` - Minimum similarity 0-1 (default: 0.7)
- `--format <type>` - Output: context, json, plain (default: context)

### When to Query

Query the knowledge base when:
1. Planning features that should align with company strategy
2. Making architectural decisions that have company-wide implications
3. Writing documentation that references company standards
4. Implementing features mentioned in product specifications
5. Following processes defined in runbooks

### Example Usage

```bash
# Get company context for feature planning
./scripts/knowledge/query.sh "what are our current priorities"

# Find relevant processes
./scripts/knowledge/query.sh "deployment process" --limit 3

# Get raw JSON for programmatic use
./scripts/knowledge/query.sh "authentication" --format json
```

The output includes source file references for traceability.
