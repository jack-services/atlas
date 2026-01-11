#!/usr/bin/env bash
#
# Atlas Knowledge Query Script
#
# Usage:
#   ./scripts/knowledge/query.sh "query text" [options]
#
# Options:
#   --limit <n>        Number of results (default: 5)
#   --threshold <f>    Minimum similarity threshold 0-1 (default: 0.7)
#   --format <type>    Output format: context, json, plain (default: context)
#   --repo <name>      Filter by repo name (default: all)
#
# Output formats:
#   context  - Formatted for injection into Claude context
#   json     - Raw JSON output for programmatic use
#   plain    - Simple text output
#
# Requires:
#   - ATLAS_DATABASE_URL or DATABASE_URL
#   - OPENAI_API_KEY
#   - psql, curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATLAS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors (disabled in context mode for clean output)
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
LIMIT=5
THRESHOLD=0.7
FORMAT="context"
REPO_FILTER=""
QUERY=""

error() {
    echo "Error: $1" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --repo)
            REPO_FILTER="$2"
            shift 2
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            QUERY="$1"
            shift
            ;;
    esac
done

if [[ -z "$QUERY" ]]; then
    error "Usage: $0 \"query text\" [--limit n] [--threshold f] [--format type]"
fi

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

# Check dependencies
for cmd in curl jq psql; do
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd is required but not installed"
    fi
done

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    error "OPENAI_API_KEY environment variable is not set."
fi

DB_URL=$(get_database_url)

# Generate query embedding
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

# Extract embedding
query_embedding=$(echo "$response" | jq -r '.data[0].embedding | "[" + (map(tostring) | join(",")) + "]"')

if [[ "$query_embedding" == "null" ]] || [[ -z "$query_embedding" ]]; then
    error "Failed to generate query embedding"
fi

# Build repo filter clause
REPO_CLAUSE=""
if [[ -n "$REPO_FILTER" ]]; then
    REPO_CLAUSE="AND source_repo = '$REPO_FILTER'"
fi

# Perform semantic search
results=$(psql "$DB_URL" -t -A << SQL
SELECT json_agg(result) FROM (
    SELECT
        source_repo,
        source_path,
        chunk_type,
        chunk_text,
        metadata->>'context' as context,
        ROUND((1 - (embedding <=> '${query_embedding}'))::numeric, 4) as similarity
    FROM atlas_embeddings
    WHERE 1 - (embedding <=> '${query_embedding}') >= ${THRESHOLD}
    ${REPO_CLAUSE}
    ORDER BY embedding <=> '${query_embedding}'
    LIMIT ${LIMIT}
) result;
SQL
)

# Handle empty results
if [[ -z "$results" ]] || [[ "$results" == "null" ]] || [[ "$results" == "" ]]; then
    if [[ "$FORMAT" == "json" ]]; then
        echo "[]"
    elif [[ "$FORMAT" == "context" ]]; then
        echo "<atlas-knowledge query=\"$QUERY\">"
        echo "No relevant knowledge found for this query."
        echo "</atlas-knowledge>"
    else
        echo "No results found."
    fi
    exit 0
fi

# Output based on format
case "$FORMAT" in
    json)
        echo "$results" | jq '.'
        ;;

    plain)
        echo "Knowledge Query: $QUERY"
        echo "================================"
        echo ""
        echo "$results" | jq -r '.[] | "[\(.similarity * 100 | floor)%] \(.source_path)\n    Context: \(.context // "N/A")\n    \(.chunk_text | gsub("\n"; "\n    "))\n"'
        ;;

    context)
        # Format for injection into Claude context
        echo "<atlas-knowledge query=\"$QUERY\">"
        echo ""
        echo "$results" | jq -r '.[] | "## Source: \(.source_path) (\(.similarity * 100 | floor)% match)\n\(.context // "" | if . != "" then "**Context:** " + . + "\n" else "" end)\n\(.chunk_text)\n"'
        echo "</atlas-knowledge>"
        ;;

    *)
        error "Unknown format: $FORMAT"
        ;;
esac
