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

### Step 1: Identify Input Type

Determine if the input is:
- **Local file**: Path starting with `/`, `./`, `~/`, or a relative path
- **URL**: Starts with `http://` or `https://`

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

### Step 3: Copy to Knowledge Repo

Copy the file to the uploads/ directory in the knowledge repo:

```bash
# Get knowledge repo path from config
KNOWLEDGE_REPO=$(./scripts/config-reader.sh knowledge_repo)

# Create uploads directory if needed
mkdir -p "$KNOWLEDGE_REPO/uploads"

# Copy file with timestamp prefix
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cp "{source}" "$KNOWLEDGE_REPO/uploads/${TIMESTAMP}-{filename}"
```

### Step 4: Extract Text Content

Based on file type, extract text:

**Markdown (.md)**: Use directly (no extraction needed)

**Text (.txt)**: Use directly

**PDF (.pdf)**: Use pdftotext if available:
```bash
pdftotext "{file}" -
```

If pdftotext is not available, inform the user they need to install it:
```
brew install poppler  # macOS
apt install poppler-utils  # Debian/Ubuntu
```

**CSV (.csv)**: Convert to markdown table format

### Step 5: Index Content

Run the indexing pipeline for the new file:

```bash
./scripts/db/index.sh --repo knowledge "$KNOWLEDGE_REPO/uploads/{filename}"
```

Or chunk and embed directly:
```bash
./scripts/db/chunk.sh "{file}" | ./scripts/db/embed.sh
```

Then store in database using the embed output.

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
- Number of chunks indexed
- Sample search to verify indexing

## Supported File Types

| Type | Extension | Extraction Method |
|------|-----------|-------------------|
| Markdown | .md | Direct use |
| Plain text | .txt | Direct use |
| PDF | .pdf | pdftotext |
| CSV | .csv | Convert to markdown |

## Error Handling

- File not found: Show helpful error with path
- Unsupported format: List supported formats
- Extraction failed: Suggest installing required tools
- Indexing failed: Show database connection error

## Configuration

Uses knowledge repo path from `~/.atlas/config.yaml`:
```yaml
knowledge_repo: ~/repos/company-knowledge
```

## Notes

- Original files are preserved in `uploads/` directory
- Files are indexed automatically after upload
- Re-running on same file will update embeddings
