#!/usr/bin/env bash
#
# Atlas Semantic Search Script
#
# Usage:
#   ./scripts/db/search.sh "query text" [limit]
#
# Performs semantic search over indexed knowledge.
# Returns the most relevant chunks based on cosine similarity.
#
# Requires:
#   - ATLAS_DATABASE_URL or DATABASE_URL environment variable
#   - OPENAI_API_KEY environment variable
#   - psql and curl commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Usage: $0 \"query text\" [limit]

Example:
  $0 \"How do we handle authentication?\"
  $0 \"deployment process\" 5"
fi

QUERY="$1"
LIMIT="${2:-5}"

# Get database URL
get_database_url() {
    if [[ -n "${ATLAS_DATABASE_URL:-}" ]]; then
        echo "$ATLAS_DATABASE_URL"
    elif [[ -n "${DATABASE_URL:-}" ]]; then
        echo "$DATABASE_URL"
    else
        error "No database URL found. Set ATLAS_DATABASE_URL or DATABASE_URL."
    fi
}

# Check for required environment variables
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    error "OPENAI_API_KEY environment variable is not set."
fi

# Check for required commands
for cmd in curl jq psql; do
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd is required but not installed"
    fi
done

DB_URL=$(get_database_url)

# Generate embedding for query
echo -e "${CYAN}Generating query embedding...${NC}" >&2

request_body=$(jq -n \
    --arg text "$QUERY" \
    '{
        "input": $text,
        "model": "text-embedding-ada-002"
    }')

response=$(curl -s -X POST "https://api.openai.com/v1/embeddings" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$request_body")

# Check for errors
if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
    error_msg=$(echo "$response" | jq -r '.error.message')
    error "OpenAI API error: $error_msg"
fi

# Extract embedding as PostgreSQL vector format
query_embedding=$(echo "$response" | jq -r '.data[0].embedding | "[" + (map(tostring) | join(",")) + "]"')

if [[ "$query_embedding" == "null" ]] || [[ -z "$query_embedding" ]]; then
    error "Failed to generate query embedding"
fi

echo -e "${CYAN}Searching knowledge base...${NC}" >&2

# Perform semantic search
results=$(psql "$DB_URL" -t -A -F $'\t' << SQL
SELECT
    source_repo,
    source_path,
    chunk_text,
    metadata->>'context' as context,
    1 - (embedding <=> '${query_embedding}') as similarity
FROM atlas_embeddings
ORDER BY embedding <=> '${query_embedding}'
LIMIT ${LIMIT};
SQL
)

if [[ -z "$results" ]]; then
    echo -e "${CYAN}No results found.${NC}"
    exit 0
fi

# Format and display results
echo ""
echo -e "${GREEN}Search Results for:${NC} \"$QUERY\""
echo "================================================"
echo ""

count=1
while IFS=$'\t' read -r repo path text context similarity; do
    # Format similarity as percentage
    sim_pct=$(echo "$similarity" | awk '{printf "%.1f", $1 * 100}')

    echo -e "${GREEN}[$count]${NC} ${CYAN}$path${NC} (${sim_pct}% match)"
    if [[ -n "$context" ]]; then
        echo -e "    Context: $context"
    fi
    echo ""
    # Truncate long text for display
    if [[ ${#text} -gt 300 ]]; then
        echo "    ${text:0:300}..."
    else
        echo "    $text"
    fi
    echo ""
    echo "------------------------------------------------"
    echo ""
    ((count++))
done <<< "$results"
