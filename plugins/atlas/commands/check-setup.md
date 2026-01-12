# Atlas Check Setup Command

Verify that Atlas is properly configured and all dependencies are available.

## Usage

```
/atlas check-setup
```

## Workflow

Run through each verification step and report status:

### Step 1: Check Configuration File

```bash
CONFIG_FILE="$HOME/.atlas/config.yaml"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "Config file: $CONFIG_FILE"
else
    echo "Config file: NOT FOUND"
    echo ""
    echo "Run /atlas setup to create configuration"
fi
```

### Step 2: Check Knowledge Repository

```bash
# Read from config
KNOWLEDGE_REPO=$(./scripts/config-reader.sh knowledge_repo 2>/dev/null || echo "")
KNOWLEDGE_REPO="${KNOWLEDGE_REPO/#\~/$HOME}"

if [[ -z "$KNOWLEDGE_REPO" ]]; then
    echo "Knowledge repo: NOT CONFIGURED"
elif [[ ! -d "$KNOWLEDGE_REPO" ]]; then
    echo "Knowledge repo: $KNOWLEDGE_REPO (NOT FOUND)"
elif [[ ! -d "$KNOWLEDGE_REPO/.git" ]]; then
    echo "Knowledge repo: $KNOWLEDGE_REPO (NOT A GIT REPO)"
else
    echo "Knowledge repo: $KNOWLEDGE_REPO"

    # Check for remote
    REMOTE=$(cd "$KNOWLEDGE_REPO" && git remote get-url origin 2>/dev/null || echo "none")
    echo "  Remote: $REMOTE"

    # Count files
    FILE_COUNT=$(find "$KNOWLEDGE_REPO" -type f -not -path "*/.git/*" | wc -l | tr -d ' ')
    echo "  Files: $FILE_COUNT"
fi
```

### Step 3: Check Database Configuration

```bash
DB_URL="${ATLAS_DATABASE_URL:-${DATABASE_URL:-}}"

if [[ -z "$DB_URL" ]]; then
    echo "Database URL: NOT SET"
    echo ""
    echo "To enable semantic search, set:"
    echo "  export ATLAS_DATABASE_URL='postgres://user:pass@host:5432/dbname'"
else
    # Mask password in display
    MASKED_URL=$(echo "$DB_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')
    echo "Database URL: $MASKED_URL"

    # Test connection
    if psql "$DB_URL" -c "SELECT 1" &>/dev/null; then
        echo "  Connection: OK"

        # Check pgvector
        if psql "$DB_URL" -t -c "SELECT 1 FROM pg_extension WHERE extname = 'vector'" | grep -q 1; then
            echo "  pgvector: INSTALLED"
        else
            echo "  pgvector: NOT INSTALLED"
        fi

        # Check table
        if psql "$DB_URL" -c "SELECT 1 FROM atlas_embeddings LIMIT 1" &>/dev/null; then
            # Get stats
            CHUNK_COUNT=$(psql "$DB_URL" -t -A -c "SELECT COUNT(*) FROM atlas_embeddings")
            DOC_COUNT=$(psql "$DB_URL" -t -A -c "SELECT COUNT(DISTINCT source_path) FROM atlas_embeddings")
            echo "  Table: atlas_embeddings (${DOC_COUNT} documents, ${CHUNK_COUNT} chunks)"
        else
            echo "  Table: NOT FOUND"
            echo ""
            echo "  Run migration: ./plugins/atlas/scripts/db/migrate.sh"
        fi
    else
        echo "  Connection: FAILED"
    fi
fi
```

### Step 4: Check OpenAI API Key

```bash
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    # Show first/last 4 chars
    KEY_PREVIEW="${OPENAI_API_KEY:0:4}...${OPENAI_API_KEY: -4}"
    echo "OpenAI API Key: $KEY_PREVIEW"
else
    echo "OpenAI API Key: NOT SET"
    echo ""
    echo "Required for generating embeddings. Set:"
    echo "  export OPENAI_API_KEY='sk-...'"
fi
```

### Step 5: Check Required Tools

```bash
echo ""
echo "Required tools:"

for cmd in psql curl jq git; do
    if command -v "$cmd" &>/dev/null; then
        VERSION=$($cmd --version 2>&1 | head -1)
        echo "  $cmd: OK ($VERSION)"
    else
        echo "  $cmd: NOT FOUND"
    fi
done

echo ""
echo "Optional tools:"

if command -v pdftotext &>/dev/null; then
    echo "  pdftotext: OK (for PDF indexing)"
else
    echo "  pdftotext: NOT FOUND (PDFs will use Claude's native reading)"
fi
```

### Step 6: Summary

Provide an overall status:

```
Atlas Setup Status
==================

Configuration: OK / INCOMPLETE
Knowledge Repo: OK / NOT CONFIGURED / NOT FOUND
Database: OK / NOT CONFIGURED / CONNECTION FAILED / TABLE MISSING
OpenAI API: OK / NOT SET
Required Tools: OK / MISSING: [list]

Overall: READY / NEEDS SETUP
```

If not ready, provide specific next steps:

```
Next Steps:
1. Run /atlas setup to create configuration
2. Set ATLAS_DATABASE_URL environment variable
3. Run ./plugins/atlas/scripts/db/migrate.sh
4. Set OPENAI_API_KEY environment variable
```

## Output Format

Use colors/formatting for clarity:
- Green checkmark for OK items
- Yellow warning for optional missing items
- Red X for required missing items

Example output:

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

Your Atlas installation is fully configured and ready to use.
Try: /atlas update-knowledge ~/path/to/document.md
```

## Notes

- This command is read-only and makes no changes
- Run after `/atlas setup` to verify configuration
- Run when troubleshooting indexing or search issues
- Database connection is tested with a simple query, not a full health check
