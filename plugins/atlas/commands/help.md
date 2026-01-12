# Atlas Help Command

Display available Atlas commands and usage information.

## Available Commands

When this command is invoked, display the following help information:

---

## Atlas - Company-Aware AI Agent Plugin

Atlas connects Claude Code to your company's knowledge repositories and product codebases for autonomous planning and execution.

### Commands

| Command | Description |
|---------|-------------|
| `/atlas:setup` | Interactive wizard to configure Atlas |
| `/atlas:check-setup` | Verify configuration and dependencies |
| `/atlas:plan "<goal>"` | Break down a goal into GitHub issues |
| `/atlas:execute` | Autonomously work through issues |
| `/atlas:update-knowledge <path>` | Add documents to knowledge base |
| `/atlas:search "<query>"` | Search knowledge base |
| `/atlas:help` | Show this help message |

### Quick Start

1. **Configure Atlas:**
   ```
   /atlas:setup
   ```

2. **Plan work:**
   ```
   /atlas:plan "Add user authentication with OAuth"
   ```

3. **Execute autonomously:**
   ```
   /atlas:execute
   ```

### Configuration

Atlas configuration is stored at `~/.atlas/config.yaml`.

Required settings:
- `knowledge_repo`: Path to your knowledge repository
- `github_org`: Your GitHub organization name

### Documentation

For detailed documentation, see:
- `CLAUDE.md` in the Atlas plugin directory
- https://github.com/jack-services/atlas

---

Display this information formatted nicely for the user.
