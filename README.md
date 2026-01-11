# Atlas

Company-aware AI agent plugin for Claude Code.

## What is Atlas?

Atlas connects Claude Code to your company's knowledge repositories and product codebases, enabling autonomous planning and execution of work. It provides:

- **Knowledge Integration**: Connect to company documentation, wikis, and knowledge bases
- **Codebase Awareness**: Understand your product architecture and patterns
- **Autonomous Execution**: Plan and execute work with full context

## Installation

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- Git

### Setup

1. Clone this repository:

```bash
git clone https://github.com/jack-services/atlas.git
cd atlas
```

2. Install the plugin in Claude Code:

```bash
claude plugin install ./atlas
```

3. Configure your knowledge sources (coming soon):

```bash
/atlas setup
```

## Usage

Once installed, Atlas provides slash commands in Claude Code:

- `/atlas setup` - Configure knowledge sources and connections (coming soon)
- `/atlas plan` - Generate an execution plan for a task (coming soon)
- `/atlas execute` - Execute a plan autonomously (coming soon)

## Project Structure

```
atlas/
├── .claude-plugin/
│   └── manifest.json       # Plugin configuration
├── commands/               # Slash command implementations
├── hooks/                  # Event hooks
├── scripts/                # Utility scripts
├── CLAUDE.md               # Development instructions
└── README.md               # This file
```

## Development

See [CLAUDE.md](./CLAUDE.md) for development guidelines.

## License

MIT
