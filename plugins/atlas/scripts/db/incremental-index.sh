#!/bin/bash
# Incremental indexing for knowledge repository
# Usage: ./scripts/db/incremental-index.sh [--since <commit>] [--repo <path>]
#
# Indexes only files that have changed since the specified commit or last index.
# Maintains a state file to track the last indexed commit.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment variables from .env files
# shellcheck source=../env-loader.sh
source "$SCRIPT_DIR/../env-loader.sh"

# Default values
SINCE_COMMIT=""
REPO_PATH=""
STATE_FILE=".atlas/last-index-commit"
FORCE_FULL="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --since)
            SINCE_COMMIT="$2"
            shift 2
            ;;
        --repo)
            REPO_PATH="$2"
            shift 2
            ;;
        --state-file)
            STATE_FILE="$2"
            shift 2
            ;;
        --full)
            FORCE_FULL="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --since <commit>    Index files changed since this commit"
            echo "  --repo <path>       Path to knowledge repository"
            echo "  --state-file <path> Path to state file (default: .atlas/last-index-commit)"
            echo "  --full              Force full reindex"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Get repo path from config if not specified
if [[ -z "$REPO_PATH" ]]; then
    if [[ -x "$ROOT_DIR/scripts/config-reader.sh" ]]; then
        REPO_PATH=$("$ROOT_DIR/scripts/config-reader.sh" knowledge_repo 2>/dev/null || echo "")
    fi

    if [[ -z "$REPO_PATH" ]]; then
        echo "Error: No repository path specified. Use --repo or configure knowledge_repo." >&2
        exit 1
    fi
fi

# Resolve repo path
REPO_PATH=$(eval echo "$REPO_PATH")  # Expand ~ and variables

if [[ ! -d "$REPO_PATH" ]]; then
    echo "Error: Repository not found at $REPO_PATH" >&2
    exit 1
fi

cd "$REPO_PATH"

# Get the reference commit
if [[ -z "$SINCE_COMMIT" ]]; then
    if [[ "$FORCE_FULL" == "true" ]]; then
        SINCE_COMMIT=""
    elif [[ -f "$STATE_FILE" ]]; then
        SINCE_COMMIT=$(cat "$STATE_FILE")
        echo "Last indexed commit: $SINCE_COMMIT"
    fi
fi

# Get current HEAD
CURRENT_COMMIT=$(git rev-parse HEAD)
echo "Current commit: $CURRENT_COMMIT"

# Get list of files to index
FILES_TO_INDEX=""
if [[ "$FORCE_FULL" == "true" ]] || [[ -z "$SINCE_COMMIT" ]]; then
    echo "Mode: Full reindex"
    FILES_TO_INDEX=$(find . -type f \( -name "*.md" -o -name "*.txt" \) -not -path "./.git/*" -not -path "./.atlas/*" 2>/dev/null)
else
    echo "Mode: Incremental (since $SINCE_COMMIT)"

    # Check if the commit exists
    if ! git cat-file -e "$SINCE_COMMIT" 2>/dev/null; then
        echo "Warning: Commit $SINCE_COMMIT not found, falling back to full reindex"
        FILES_TO_INDEX=$(find . -type f \( -name "*.md" -o -name "*.txt" \) -not -path "./.git/*" -not -path "./.atlas/*" 2>/dev/null)
    else
        # Get changed files (Added, Copied, Modified, Renamed)
        FILES_TO_INDEX=$(git diff --name-only --diff-filter=ACMR "$SINCE_COMMIT" HEAD 2>/dev/null | grep -E '\.(md|txt)$' || true)

        # Also get deleted files for cleanup
        DELETED_FILES=$(git diff --name-only --diff-filter=D "$SINCE_COMMIT" HEAD 2>/dev/null | grep -E '\.(md|txt)$' || true)

        if [[ -n "$DELETED_FILES" ]]; then
            echo "Deleted files to remove from index:"
            echo "$DELETED_FILES"
            # TODO: Implement deletion from vector database
        fi
    fi
fi

# Count files
FILE_COUNT=$(echo "$FILES_TO_INDEX" | grep -c '.' || echo "0")
echo "Files to index: $FILE_COUNT"

if [[ "$FILE_COUNT" -eq 0 ]]; then
    echo "No files to index."
    # Update state file even if no changes
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$CURRENT_COMMIT" > "$STATE_FILE"
    exit 0
fi

# Index each file
INDEXED=0
FAILED=0

echo ""
echo "Indexing files..."
echo "---"

while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # Skip if file doesn't exist (might be deleted)
    if [[ ! -f "$file" ]]; then
        continue
    fi

    echo "Processing: $file"

    # Use the main index script
    if "$SCRIPT_DIR/index.sh" --file "$file" --repo knowledge 2>&1; then
        INDEXED=$((INDEXED + 1))
        echo "  ✓ Indexed"
    else
        FAILED=$((FAILED + 1))
        echo "  ✗ Failed"
    fi
done <<< "$FILES_TO_INDEX"

echo "---"
echo "Indexing complete: $INDEXED succeeded, $FAILED failed"

# Update state file on success
if [[ $FAILED -eq 0 ]] || [[ $INDEXED -gt 0 ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$CURRENT_COMMIT" > "$STATE_FILE"
    echo "Updated state file: $STATE_FILE"
fi

# Report result
if [[ $FAILED -gt 0 ]]; then
    echo '{"success": false, "indexed": '$INDEXED', "failed": '$FAILED'}'
    exit 1
else
    echo '{"success": true, "indexed": '$INDEXED', "failed": 0}'
    exit 0
fi
