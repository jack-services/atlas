# GitHub Actions for Atlas

This directory contains example GitHub Actions workflows for automating Atlas tasks.

## Available Workflows

### `index-knowledge.yml`

Automatically indexes your knowledge repository when files change.

**Copy to your knowledge repository:**
```bash
mkdir -p .github/workflows
cp index-knowledge.yml <your-knowledge-repo>/.github/workflows/
```

**Required secrets:**
- `ATLAS_DATABASE_URL`: PostgreSQL connection string for vector database
- `OPENAI_API_KEY`: API key for generating embeddings (if using OpenAI)

**Triggers:**
- Push to main/master branch
- Merged pull requests
- Manual workflow dispatch

**Features:**
- Incremental indexing (only changed files)
- Full reindex option via manual trigger
- Status reporting

## Setup Instructions

1. Copy the workflow file to your knowledge repository:
   ```bash
   cp examples/github-actions/index-knowledge.yml ~/your-knowledge-repo/.github/workflows/
   ```

2. Configure repository secrets in GitHub:
   - Go to your knowledge repo on GitHub
   - Settings → Secrets and variables → Actions
   - Add `ATLAS_DATABASE_URL` with your PostgreSQL connection string
   - Add `OPENAI_API_KEY` if using OpenAI for embeddings

3. Push the workflow file:
   ```bash
   cd ~/your-knowledge-repo
   git add .github/workflows/index-knowledge.yml
   git commit -m "Add Atlas auto-indexing workflow"
   git push
   ```

4. Test the workflow:
   - Make a change to any `.md` file in your knowledge repo
   - Push the change
   - Check the Actions tab to see the workflow run

## Alternative: Webhook Handler

For non-GitHub hosted repositories, use the webhook handler:

```bash
# Start the webhook server
./scripts/db/webhook-handler.sh --port 8080

# Trigger indexing via HTTP
curl -X POST http://localhost:8080/index

# Trigger full reindex
curl -X POST http://localhost:8080/reindex
```

## Troubleshooting

### Workflow doesn't trigger
- Ensure the workflow file is in `.github/workflows/`
- Check that the branch is `main` or `master`
- Verify file extensions match the path filters (`.md`, `.txt`, `.pdf`)

### Indexing fails
- Check the workflow logs in the Actions tab
- Verify the `ATLAS_DATABASE_URL` secret is set correctly
- Ensure the database is accessible from GitHub Actions runners
