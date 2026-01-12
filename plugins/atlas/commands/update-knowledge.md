# Atlas Update Knowledge Command

Add new knowledge to the Atlas system by uploading files or URLs.

## Usage

```
/atlas update-knowledge <path-or-url>
```

## Examples

```
/atlas update-knowledge ~/Documents/pitch-deck.pdf
/atlas update-knowledge https://docs.google.com/document/d/...
/atlas update-knowledge ./meeting-notes.md
```

## Workflow

When this command is invoked, follow these steps:

### Step 0: Verify Environment (REQUIRED)

Before processing any files, verify the Atlas environment is properly configured:

```bash
# Get Atlas plugin directory
ATLAS_PLUGIN_DIR="$(dirname "$(dirname "$0")")"  # Adjust based on execution context

# Check for database URL
DB_URL="${ATLAS_DATABASE_URL:-${DATABASE_URL:-}}"
if [[ -z "$DB_URL" ]]; then
    echo "WARNING: Database not configured for semantic search."
    echo ""
    echo "To enable search, set ATLAS_DATABASE_URL:"
    echo "  export ATLAS_DATABASE_URL='postgres://user:pass@host:5432/dbname'"
    echo ""
    echo "Or configure in ~/.atlas/config.yaml:"
    echo "  vector_db:"
    echo "    url: postgres://..."
    echo ""
    # Ask user if they want to continue without indexing
fi

# If DB is configured, verify table exists
if [[ -n "$DB_URL" ]]; then
    if ! psql "$DB_URL" -c "SELECT 1 FROM atlas_embeddings LIMIT 1" &>/dev/null; then
        echo "Database table 'atlas_embeddings' not found."
        echo ""
        echo "Run the migration to create it:"
        echo "  $ATLAS_PLUGIN_DIR/scripts/db/migrate.sh"
        echo ""
        # Ask user if they want to run migration now
    fi
fi
```

**If database is not configured:** Ask the user if they want to:
1. Continue with file-only storage (no semantic search)
2. Stop and configure the database first

### Step 1: Identify Input Type

Determine if the input is:
- **Local file**: Path starting with `/`, `./`, `~/`, or a relative path
- **URL**: Starts with `http://` or `https://`
- **Directory**: A folder containing multiple files to index

### Step 2: Fetch/Validate Content

For local files:
```bash
# Check file exists
test -f "{path}" && echo "File found"

# Get file type
file --brief "{path}"
```

For URLs:
```bash
# Download to temporary location
curl -L -o /tmp/atlas-upload "{url}"
```

For directories:
```bash
# List indexable files
find "{path}" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.pdf" \) -not -path "*/.git/*"
```

### Step 3: Copy to Knowledge Repo

Copy the file to the uploads/ directory in the knowledge repo:

```bash
# Get knowledge repo path from config
KNOWLEDGE_REPO=$(./scripts/config-reader.sh knowledge_repo)

# Expand ~ if present
KNOWLEDGE_REPO="${KNOWLEDGE_REPO/#\~/$HOME}"

# Create uploads directory if needed
mkdir -p "$KNOWLEDGE_REPO/uploads"

# Copy file with timestamp prefix
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cp "{source}" "$KNOWLEDGE_REPO/uploads/${TIMESTAMP}-{filename}"
```

### Step 4: Extract Text Content

Based on file type, extract text for indexing:

**Markdown (.md)**: Use directly (no extraction needed)

**Text (.txt)**: Use directly

**PDF (.pdf)**:

Option A - Use pdftotext if available:
```bash
pdftotext "{file}" - > "{file}.txt"
```

Option B - If pdftotext is not available, use Claude's native PDF reading:
1. Read the PDF using the Read tool (Claude can read PDFs natively)
2. Create a markdown summary of the content
3. Save the markdown file alongside the PDF for indexing

```bash
# Check if pdftotext is available
if ! command -v pdftotext &>/dev/null; then
    echo "pdftotext not found. Using Claude's native PDF reading."
    echo "Creating markdown extraction for indexing..."
    # Use Read tool on the PDF, then Write the extracted content to .md
fi
```

**CSV (.csv)**: Convert to markdown table format

### Step 5: Index Content (REQUIRED for Search)

**This step is critical for enabling semantic search.**

Run the indexing pipeline for the knowledge repo:

```bash
# Get the Atlas plugin directory (where scripts are located)
ATLAS_PLUGIN_DIR="path/to/plugins/atlas"

# Run indexing
"$ATLAS_PLUGIN_DIR/scripts/db/index.sh" --repo knowledge "$KNOWLEDGE_REPO"
```

Verify indexing succeeded:
```bash
DB_URL="${ATLAS_DATABASE_URL:-$DATABASE_URL}"
psql "$DB_URL" -t -c "
    SELECT COUNT(*) as chunks
    FROM atlas_embeddings
    WHERE source_path LIKE '%{filename}%'
"
```

**Report indexing status:**
- Number of chunks created
- Confirm: "Content is now searchable via /atlas search"

**If indexing fails:**
- Show the error message
- Check if `OPENAI_API_KEY` is set (required for embeddings)
- Suggest running migration if table doesn't exist

### Step 6: Commit to Knowledge Repo

Commit the new file to git:

```bash
cd "$KNOWLEDGE_REPO"
git add "uploads/{filename}"
git commit -m "Add {filename} via Atlas update-knowledge"
```

Ask the user if they want to push to remote.

### Step 7: Confirmation

Report success with:
- File location in knowledge repo
- Number of chunks indexed (or "0 - database not configured")
- Searchable: Yes/No
- If searchable, show a sample search command: `/atlas search "relevant query"`

Example success message:
```
Knowledge updated successfully!

File: ~/Projects/company/org/uploads/20240115-143022-investor-update.pdf
Chunks indexed: 24
Searchable: Yes

Try searching: /atlas search "Q4 revenue metrics"
```

## Supported File Types

| Type | Extension | Extraction Method |
|------|-----------|-------------------|
| Markdown | .md | Direct use |
| Plain text | .txt | Direct use |
| PDF | .pdf | pdftotext OR Claude native reading |
| CSV | .csv | Convert to markdown |

## Error Handling

- **File not found**: Show helpful error with the exact path tried
- **Unsupported format**: List supported formats and suggest conversion
- **Database not configured**: Offer to continue with file-only storage
- **Table not found**: Prompt to run migration script
- **Extraction failed**: Suggest installing required tools or use Claude fallback
- **Indexing failed**: Show database connection error and troubleshooting steps
- **Embedding failed**: Check OPENAI_API_KEY is set

## Configuration

Uses knowledge repo path from `~/.atlas/config.yaml`:
```yaml
knowledge_repo: ~/repos/company-knowledge

vector_db:
  url: ${ATLAS_DATABASE_URL}  # Or hardcoded connection string
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ATLAS_DATABASE_URL` | For search | PostgreSQL connection with pgvector |
| `OPENAI_API_KEY` | For search | Used to generate embeddings |

## Notes

- Original files are preserved in `uploads/` directory
- Files are indexed automatically after upload (if database configured)
- Re-running on same file will update embeddings
- PDFs can be processed via pdftotext or Claude's native PDF reading
- Without database configuration, files are stored but not searchable
