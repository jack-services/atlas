#!/usr/bin/env bash
#
# Atlas Document Indexing Pipeline
#
# Usage:
#   ./scripts/db/index.sh [--full] [--repo <name>] [path]
#
# Options:
#   --full        Force full re-index (ignore cached hashes)
#   --repo <name> Repository name for source_repo field (default: "knowledge")
#   path          Path to knowledge repo (default: from config)
#
# The pipeline:
#   1. Scans for documents (.md, .txt)
#   2. Checks file hashes for changes (incremental)
#   3. Chunks documents into sections
#   4. Generates embeddings via OpenAI
#   5. Stores in PostgreSQL with pgvector
#
# Requires:
#   - ATLAS_DATABASE_URL or DATABASE_URL
#   - OPENAI_API_KEY
#   - psql, curl, jq, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATLAS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

info() {
    echo -e "${CYAN}$1${NC}"
}

# Default values
FULL_INDEX=false
REPO_NAME="knowledge"
KNOWLEDGE_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            FULL_INDEX=true
            shift
            ;;
        --repo)
            REPO_NAME="$2"
            shift 2
            ;;
        *)
            KNOWLEDGE_PATH="$1"
            shift
            ;;
    esac
done

# Get database URL
get_database_url() {
    if [[ -n "${ATLAS_DATABASE_URL:-}" ]]; then
        echo "$ATLAS_DATABASE_URL"
    elif [[ -n "${DATABASE_URL:-}" ]]; then
        echo "$DATABASE_URL"
    else
        # Try to read from config
        if [[ -x "$ATLAS_DIR/scripts/config-reader.sh" ]]; then
            "$ATLAS_DIR/scripts/config-reader.sh" vector_db.url 2>/dev/null || true
        fi
    fi
}

# Get knowledge repo path from config if not provided
get_knowledge_path() {
    if [[ -n "$KNOWLEDGE_PATH" ]]; then
        echo "$KNOWLEDGE_PATH"
    elif [[ -x "$ATLAS_DIR/scripts/config-reader.sh" ]]; then
        local path
        path=$("$ATLAS_DIR/scripts/config-reader.sh" knowledge_repo 2>/dev/null || echo "")
        # Expand ~ if present
        echo "${path/#\~/$HOME}"
    else
        error "No knowledge repo path provided and config not found"
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    for cmd in psql curl jq python3; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing[*]}"
    fi
}

# Get file hash
get_file_hash() {
    local file="$1"
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    else
        shasum -a 256 "$file" | cut -d' ' -f1
    fi
}

# Check if file needs indexing (hash changed)
needs_indexing() {
    local db_url="$1"
    local source_path="$2"
    local current_hash="$3"

    if [[ "$FULL_INDEX" == "true" ]]; then
        return 0
    fi

    # Check if file exists in DB with same hash
    local db_hash
    db_hash=$(psql "$db_url" -t -A -c "
        SELECT DISTINCT source_hash
        FROM atlas_embeddings
        WHERE source_repo = '$REPO_NAME'
        AND source_path = '$source_path'
        LIMIT 1
    " 2>/dev/null || echo "")

    if [[ "$db_hash" == "$current_hash" ]]; then
        return 1  # No indexing needed
    fi

    return 0  # Needs indexing
}

# Delete old embeddings for a file
delete_old_embeddings() {
    local db_url="$1"
    local source_path="$2"

    psql "$db_url" -c "
        DELETE FROM atlas_embeddings
        WHERE source_repo = '$REPO_NAME'
        AND source_path = '$source_path'
    " &>/dev/null
}

# Store embedding in database
store_embedding() {
    local db_url="$1"
    local json="$2"

    # Parse JSON
    local source_path source_hash chunk_index chunk_type chunk_text metadata embedding
    source_path=$(echo "$json" | jq -r '.source_path')
    source_hash=$(echo "$json" | jq -r '.source_hash')
    chunk_index=$(echo "$json" | jq -r '.chunk_index')
    chunk_type=$(echo "$json" | jq -r '.chunk_type')
    chunk_text=$(echo "$json" | jq -r '.chunk_text' | sed "s/'/''/g")  # Escape quotes
    metadata=$(echo "$json" | jq -c '.metadata')
    embedding=$(echo "$json" | jq -c '.embedding')

    # Insert into database
    psql "$db_url" -c "
        INSERT INTO atlas_embeddings (source_repo, source_path, source_hash, chunk_index, chunk_type, chunk_text, metadata, embedding)
        VALUES ('$REPO_NAME', '$source_path', '$source_hash', $chunk_index, '$chunk_type', '$chunk_text', '$metadata', '$embedding')
        ON CONFLICT (source_repo, source_path, chunk_index)
        DO UPDATE SET
            source_hash = EXCLUDED.source_hash,
            chunk_type = EXCLUDED.chunk_type,
            chunk_text = EXCLUDED.chunk_text,
            metadata = EXCLUDED.metadata,
            embedding = EXCLUDED.embedding,
            updated_at = NOW()
    " &>/dev/null
}

# Index a single file
index_file() {
    local db_url="$1"
    local file="$2"
    local relative_path="$3"

    info "  Indexing: $relative_path"

    # Chunk the file
    local chunks
    chunks=$("$SCRIPT_DIR/chunk.sh" "$file" 2>/dev/null)

    if [[ -z "$chunks" ]]; then
        warn "  No chunks extracted from $relative_path"
        return
    fi

    local chunk_count=0

    # Process each chunk
    while IFS= read -r chunk; do
        [[ -z "$chunk" ]] && continue

        # Generate embedding
        local embedded
        embedded=$(echo "$chunk" | "$SCRIPT_DIR/embed.sh" 2>/dev/null)

        if [[ -z "$embedded" ]]; then
            warn "  Failed to generate embedding for chunk"
            continue
        fi

        # Store in database
        store_embedding "$db_url" "$embedded"
        ((chunk_count++))

    done <<< "$chunks"

    success "    Indexed $chunk_count chunks"
}

# Main indexing function
main() {
    check_dependencies

    # Get configuration
    local db_url knowledge_path
    db_url=$(get_database_url)
    knowledge_path=$(get_knowledge_path)

    if [[ -z "$db_url" ]]; then
        error "No database URL configured. Set ATLAS_DATABASE_URL or configure in ~/.atlas/config.yaml"
    fi

    if [[ ! -d "$knowledge_path" ]]; then
        error "Knowledge repo not found at: $knowledge_path"
    fi

    echo "Atlas Document Indexing Pipeline"
    echo "================================="
    echo "Knowledge repo: $knowledge_path"
    echo "Repository name: $REPO_NAME"
    echo "Full re-index: $FULL_INDEX"
    echo ""

    # Find all indexable files
    local files_indexed=0
    local files_skipped=0

    # Index markdown files
    while IFS= read -r -d '' file; do
        local relative_path="${file#$knowledge_path/}"
        local file_hash
        file_hash=$(get_file_hash "$file")

        if needs_indexing "$db_url" "$relative_path" "$file_hash"; then
            # Delete old embeddings first
            delete_old_embeddings "$db_url" "$relative_path"

            # Index the file
            index_file "$db_url" "$file" "$relative_path"
            ((files_indexed++))
        else
            ((files_skipped++))
        fi
    done < <(find "$knowledge_path" -type f \( -name "*.md" -o -name "*.txt" \) -not -path "*/.git/*" -print0)

    echo ""
    echo "================================="
    success "Indexing complete!"
    echo "Files indexed: $files_indexed"
    echo "Files skipped (unchanged): $files_skipped"

    # Show stats
    echo ""
    info "Database stats:"
    psql "$db_url" -c "SELECT * FROM atlas_embedding_stats WHERE source_repo = '$REPO_NAME'" 2>/dev/null || true
}

main "$@"
