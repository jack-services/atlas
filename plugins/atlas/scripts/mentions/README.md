# @atlas Mention Handler

Capture discussions from GitHub issues, PRs, and comments to your knowledge repository.

## Overview

When someone mentions `@atlas` in a GitHub comment, Atlas can:
- **Capture decisions** to the knowledge repo
- **Save discussions** for future reference
- **Summarize threads** into documentation

## Setup

### Option 1: GitHub Webhook (Recommended)

1. Start the webhook server:
   ```bash
   ./scripts/mentions/webhook-server.sh --port 9000 --secret YOUR_SECRET
   ```

2. Configure a GitHub webhook in your repository:
   - Go to Settings → Webhooks → Add webhook
   - Payload URL: `http://your-server:9000/webhook`
   - Content type: `application/json`
   - Secret: Your webhook secret
   - Events: Select "Issue comments" and "Pull request review comments"

3. Test by mentioning `@atlas help` in an issue comment.

### Option 2: GitHub Action (Alternative)

Copy the example workflow to your repository:

```yaml
# .github/workflows/atlas-mentions.yml
name: Process Atlas Mentions

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

jobs:
  process:
    if: contains(github.event.comment.body, '@atlas')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: jack-services/atlas

      - name: Process mention
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo '${{ toJSON(github.event) }}' > /tmp/context.json
          ./scripts/mentions/process-mention.sh /tmp/context.json
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `@atlas capture this` | Capture content above the mention | `@atlas capture this` |
| `@atlas capture this to <section>` | Capture to specific section | `@atlas capture this to decisions` |
| `@atlas summarize this` | Capture the full thread | `@atlas summarize this thread` |
| `@atlas help` | Show available commands | `@atlas help` |

## Usage Examples

### Capturing a Decision

In a GitHub issue discussion:

```markdown
After discussion, we decided to use PostgreSQL with pgvector for our
embedding storage. This integrates with our existing infrastructure
and avoids adding another database service.

@atlas capture this to decisions
```

Atlas will:
1. Extract the content above the mention
2. Create a file in `knowledge-repo/decisions/`
3. Commit and push the change
4. Reply with a link to the captured content

### Summarizing a Thread

```markdown
@atlas summarize this thread
```

Atlas will:
1. Fetch all comments in the issue/PR
2. Create a summary document
3. Commit to `knowledge-repo/summaries/`
4. Reply with a link

## Captured Content Format

Files are created with this structure:

```markdown
# Issue/PR Title

> Captured from owner/repo#123 by @username

[Content captured from the comment]

---

**Source:** https://github.com/owner/repo/issues/123#issuecomment-456
**Captured:** 2024-01-15 10:30:00
```

## Sections

Content is organized into sections based on the command:

| Section | Path | Used For |
|---------|------|----------|
| captures | `captures/` | General content (default) |
| decisions | `decisions/` | Decision records |
| architecture | `architecture/` | Architecture decisions |
| processes | `processes/` | Process documentation |
| summaries | `summaries/` | Thread summaries |

## Troubleshooting

### Atlas doesn't respond

1. Check webhook server logs: `tail -f .atlas/mentions.log`
2. Verify webhook is configured correctly in GitHub
3. Ensure the server is accessible from GitHub

### "No knowledge repository configured"

Run `/atlas setup` to configure the knowledge repository path.

### Commits fail to push

1. Ensure the knowledge repo has a configured remote
2. Verify push access to the repository
3. Check for authentication issues

## Security

- Webhook signature verification is recommended (use `--secret`)
- The server only processes comments containing `@atlas`
- All actions are logged to `.atlas/mentions.log`
