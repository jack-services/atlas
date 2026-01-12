# Atlas Search Command

Search the knowledge base for relevant information using semantic search.

## Usage

```
/atlas search "<query>" [--limit N] [--threshold 0.X] [--format context|json|plain]
```

## Examples

```
/atlas search "Q4 revenue metrics"
/atlas search "authentication implementation" --limit 10
/atlas search "company mission" --format context
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--limit N` | 5 | Number of results to return |
| `--threshold 0.X` | 0.7 | Minimum similarity score (0-1) |
| `--format <type>` | context | Output format: `context`, `json`, `plain` |

## Workflow

When this command is invoked, follow these steps:

### Step 1: Verify Database Configuration

```bash
DB_URL="${ATLAS_DATABASE_URL:-${DATABASE_URL:-}}"

if [[ -z "$DB_URL" ]]; then
    echo "Database not configured for semantic search."
    echo ""
    echo "To enable search, set up the database:"
    echo "  1. Set ATLAS_DATABASE_URL environment variable"
    echo "  2. Run ./plugins/atlas/scripts/db/migrate.sh"
    echo "  3. Index your knowledge: /atlas update-knowledge <path>"
    echo ""
    echo "Run /atlas check-setup for full configuration status."
    exit 1
fi

# Verify table exists
if ! psql "$DB_URL" -c "SELECT 1 FROM atlas_embeddings LIMIT 1" &>/dev/null; then
    echo "Knowledge base not initialized."
    echo ""
    echo "Run the migration to create the database:"
    echo "  ./plugins/atlas/scripts/db/migrate.sh"
    exit 1
fi
```

### Step 2: Check for Indexed Content

```bash
CHUNK_COUNT=$(psql "$DB_URL" -t -A -c "SELECT COUNT(*) FROM atlas_embeddings")

if [[ "$CHUNK_COUNT" -eq 0 ]]; then
    echo "Knowledge base is empty."
    echo ""
    echo "Add content with:"
    echo "  /atlas update-knowledge ~/path/to/document.md"
    exit 1
fi
```

### Step 3: Execute Search Query

Run the knowledge query script:

```bash
ATLAS_PLUGIN_DIR="path/to/plugins/atlas"

"$ATLAS_PLUGIN_DIR/scripts/knowledge/query.sh" \
    "$QUERY" \
    --limit "$LIMIT" \
    --threshold "$THRESHOLD" \
    --format "$FORMAT"
```

### Step 4: Format and Display Results

**For `--format context` (default):**

Display results in a readable format for use as context:

```
Search Results for: "Q4 revenue metrics"
=========================================

[1] company-history.md (similarity: 0.89)
────────────────────────────────────────
**October Metrics:**
| Metric | Result | Trend |
| Jobs per Week | 15 | Steady growth |
| Monthly Revenue | $12,000 | +100% MoM |
...

[2] investor-update-november.md (similarity: 0.84)
────────────────────────────────────────
Our focus on Thumbtack and Yelp is paying off...
...

Found 5 results (showing top 5)
```

**For `--format json`:**

Return structured JSON for programmatic use:

```json
{
  "query": "Q4 revenue metrics",
  "results": [
    {
      "source_path": "company-history.md",
      "chunk_index": 12,
      "similarity": 0.89,
      "content": "**October Metrics:**..."
    }
  ],
  "total_results": 5
}
```

**For `--format plain`:**

Return just the text content, suitable for piping:

```
**October Metrics:**
| Metric | Result | Trend |
...
---
Our focus on Thumbtack and Yelp is paying off...
```

### Step 5: Handle No Results

If no results match the threshold:

```
No results found for: "obscure query"

Suggestions:
- Try broader search terms
- Lower the threshold: /atlas search "query" --threshold 0.5
- Check what's indexed: /atlas check-setup
```

## Error Handling

| Error | Message | Solution |
|-------|---------|----------|
| No database URL | "Database not configured" | Set ATLAS_DATABASE_URL |
| Table doesn't exist | "Knowledge base not initialized" | Run migration script |
| No content indexed | "Knowledge base is empty" | Run update-knowledge |
| No results found | "No results found" | Try different query terms |
| Query too short | "Query too short" | Provide more context |

## Output Format Details

### Context Format

Designed to be copy-pasted as context for other prompts:

```
## Relevant Knowledge

The following information was retrieved from the company knowledge base:

### From: company-history.md
[content...]

### From: investor-update.md
[content...]
```

### JSON Format

Full metadata for programmatic use:

```json
{
  "query": "string",
  "timestamp": "ISO-8601",
  "results": [
    {
      "source_repo": "knowledge",
      "source_path": "path/to/file.md",
      "chunk_index": 0,
      "chunk_type": "paragraph",
      "similarity": 0.85,
      "content": "text content",
      "metadata": {}
    }
  ],
  "total_results": 10,
  "returned_results": 5,
  "threshold": 0.7
}
```

## Notes

- Search uses OpenAI embeddings for semantic similarity
- Results are ranked by cosine similarity score
- Higher threshold = more relevant but fewer results
- Lower threshold = more results but potentially less relevant
- The `context` format is optimized for use with Claude
