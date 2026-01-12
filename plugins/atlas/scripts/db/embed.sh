#!/usr/bin/env bash
#
# Atlas Embedding Generation Script
#
# Usage:
#   echo '{"chunk_text": "..."}' | ./scripts/db/embed.sh
#   ./scripts/db/chunk.sh file.md | ./scripts/db/embed.sh
#
# Generates embeddings using OpenAI's text-embedding-3-small model.
# Input: JSON lines with chunk_text field
# Output: JSON lines with embedding field added
#
# Requires:
#   - OPENAI_API_KEY environment variable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env files
# shellcheck source=../env-loader.sh
source "$SCRIPT_DIR/../env-loader.sh"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

# Check for API key
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    error "OPENAI_API_KEY environment variable is not set.

Get your API key from: https://platform.openai.com/api-keys
Then: export OPENAI_API_KEY='sk-...'"
fi

# Check for required commands
if ! command -v curl &> /dev/null; then
    error "curl is required but not installed"
fi

if ! command -v jq &> /dev/null; then
    error "jq is required but not installed"
fi

# Process each line of input
while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Extract text to embed
    text=$(echo "$line" | jq -r '.chunk_text // empty')

    if [[ -z "$text" ]]; then
        warn "Skipping line without chunk_text"
        continue
    fi

    # Truncate text if too long (max ~8000 tokens, roughly 32000 chars)
    if [[ ${#text} -gt 30000 ]]; then
        text="${text:0:30000}"
        warn "Truncated text to 30000 characters"
    fi

    # Prepare request body
    request_body=$(jq -n \
        --arg text "$text" \
        '{
            "input": $text,
            "model": "text-embedding-3-small"
        }')

    # Call OpenAI API
    response=$(curl -s -X POST "https://api.openai.com/v1/embeddings" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$request_body")

    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        error_msg=$(echo "$response" | jq -r '.error.message')
        warn "API error: $error_msg"
        continue
    fi

    # Extract embedding
    embedding=$(echo "$response" | jq -c '.data[0].embedding')

    if [[ "$embedding" == "null" ]] || [[ -z "$embedding" ]]; then
        warn "No embedding returned for chunk"
        continue
    fi

    # Add embedding to original JSON and output
    echo "$line" | jq -c --argjson embedding "$embedding" '. + {embedding: $embedding}'

done
