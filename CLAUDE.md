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
