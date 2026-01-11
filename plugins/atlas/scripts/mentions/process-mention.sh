#!/bin/bash
# Process @atlas mentions from GitHub comments
# Usage: ./scripts/mentions/process-mention.sh <context-file>
#
# Parses the mention, captures content, commits to knowledge repo,
# and replies with confirmation.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Handle help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $0 <context-file>"
    echo ""
    echo "Process @atlas mentions from GitHub comments."
    echo ""
    echo "The context file should be a JSON file with:"
    echo "  repo_full_name, issue_number, issue_title,"
    echo "  comment_body, comment_url, user, comment_id"
    echo ""
    echo "This script is typically called by webhook-server.sh"
    exit 0
fi

CONTEXT_FILE="$1"

if [[ -z "$CONTEXT_FILE" ]] || [[ ! -f "$CONTEXT_FILE" ]]; then
    echo "Error: Context file not found: $CONTEXT_FILE" >&2
    echo "Usage: $0 <context-file>" >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Parse context
REPO_FULL_NAME=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('repo_full_name', ''))")
ISSUE_NUMBER=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('issue_number', ''))")
ISSUE_TITLE=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('issue_title', ''))")
COMMENT_BODY=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('comment_body', ''))")
COMMENT_URL=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('comment_url', ''))")
USER=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('user', ''))")
COMMENT_ID=$(python3 -c "import json; print(json.load(open('$CONTEXT_FILE')).get('comment_id', ''))")

log "Processing mention from $USER"
log "Repo: $REPO_FULL_NAME"
log "Issue/PR: #$ISSUE_NUMBER - $ISSUE_TITLE"

# Parse the @atlas command
# Supported formats:
#   @atlas capture this
#   @atlas capture this to <path>
#   @atlas summarize this
#   @atlas summarize this thread
#   @atlas add to <section>

COMMAND=$(echo "$COMMENT_BODY" | grep -ioE '@atlas\s+\w+(\s+\w+)*' | head -1 | sed 's/@atlas\s*//i')
COMMAND=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

log "Command: $COMMAND"

# Get knowledge repo path
KNOWLEDGE_REPO=""
if [[ -x "$ROOT_DIR/scripts/config-reader.sh" ]]; then
    KNOWLEDGE_REPO=$("$ROOT_DIR/scripts/config-reader.sh" knowledge_repo 2>/dev/null || echo "")
fi

if [[ -z "$KNOWLEDGE_REPO" ]]; then
    log "Error: No knowledge repository configured"
    reply_error "No knowledge repository configured. Please run \`/atlas setup\` first."
    exit 1
fi

KNOWLEDGE_REPO=$(eval echo "$KNOWLEDGE_REPO")

# Helper function to reply to the comment
reply_to_comment() {
    local message="$1"
    log "Replying: $message"

    gh issue comment "$ISSUE_NUMBER" --repo "$REPO_FULL_NAME" --body "$message" 2>/dev/null || \
    gh pr comment "$ISSUE_NUMBER" --repo "$REPO_FULL_NAME" --body "$message" 2>/dev/null || true
}

reply_error() {
    reply_to_comment "I couldn't process your request: $1"
}

reply_success() {
    local file_path="$1"
    local file_url="$2"
    reply_to_comment "Captured to \`$file_path\`. [View in knowledge repo]($file_url)"
}

# Extract content to capture
# Get the content above the @atlas mention (the decision/content being captured)
extract_content() {
    # Get everything before the @atlas mention
    local content
    content=$(echo "$COMMENT_BODY" | sed 's/@atlas.*//')

    # If empty, try to get quoted content
    if [[ -z "$(echo "$content" | tr -d '[:space:]')" ]]; then
        content=$(echo "$COMMENT_BODY" | grep -E '^>' | sed 's/^>\s*//')
    fi

    # Clean up
    content=$(echo "$content" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    echo "$content"
}

# Determine target path based on command
determine_target_path() {
    local command="$1"
    local default_section="captures"

    # Check for "to <path>" pattern
    if echo "$command" | grep -iq 'to '; then
        local path
        path=$(echo "$command" | sed 's/.*to\s*//' | tr ' ' '-')
        echo "$path"
        return
    fi

    # Check for known sections
    if echo "$command" | grep -iq 'decision'; then
        echo "decisions"
        return
    fi

    if echo "$command" | grep -iq 'architecture'; then
        echo "architecture"
        return
    fi

    if echo "$command" | grep -iq 'process'; then
        echo "processes"
        return
    fi

    echo "$default_section"
}

# Generate filename based on content
generate_filename() {
    local title="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)

    # Sanitize title for filename
    local safe_title
    safe_title=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 50)

    if [[ -z "$safe_title" ]]; then
        safe_title="capture"
    fi

    echo "${timestamp}-${safe_title}.md"
}

# Main processing logic
case "$COMMAND" in
    capture*|add*)
        log "Processing capture command"

        CONTENT=$(extract_content)
        if [[ -z "$CONTENT" ]]; then
            reply_error "No content found to capture. Please include the content above the @atlas mention."
            exit 1
        fi

        SECTION=$(determine_target_path "$COMMAND")
        FILENAME=$(generate_filename "$ISSUE_TITLE")
        TARGET_PATH="$SECTION/$FILENAME"

        log "Target: $TARGET_PATH"

        # Create the directory if needed
        mkdir -p "$KNOWLEDGE_REPO/$SECTION"

        # Create the file
        cat > "$KNOWLEDGE_REPO/$TARGET_PATH" << CONTENT_EOF
# $ISSUE_TITLE

> Captured from $REPO_FULL_NAME#$ISSUE_NUMBER by @$USER

$CONTENT

---

**Source:** $COMMENT_URL
**Captured:** $(date '+%Y-%m-%d %H:%M:%S')
CONTENT_EOF

        # Commit to knowledge repo
        cd "$KNOWLEDGE_REPO"
        git add "$TARGET_PATH"
        git commit -m "Capture: $ISSUE_TITLE

Source: $COMMENT_URL
Captured by: @$USER via @atlas mention" || {
            log "Nothing to commit"
            reply_error "Failed to commit content. It may already exist."
            exit 1
        }

        # Push to remote
        git push origin HEAD 2>/dev/null || log "Warning: Could not push to remote"

        # Get file URL for the reply
        KNOWLEDGE_REPO_URL=$(git config --get remote.origin.url | sed 's/\.git$//' | sed 's/git@github.com:/https:\/\/github.com\//')
        FILE_URL="$KNOWLEDGE_REPO_URL/blob/main/$TARGET_PATH"

        reply_success "$TARGET_PATH" "$FILE_URL"
        log "Successfully captured to $TARGET_PATH"
        ;;

    summarize*)
        log "Processing summarize command"

        # Get the full thread context
        THREAD_CONTENT=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO_FULL_NAME" --json body,comments --jq '.body + "\n\n---\n\n" + ([.comments[].body] | join("\n\n---\n\n"))' 2>/dev/null || echo "")

        if [[ -z "$THREAD_CONTENT" ]]; then
            reply_error "Could not fetch thread content."
            exit 1
        fi

        SECTION="summaries"
        FILENAME=$(generate_filename "$ISSUE_TITLE")
        TARGET_PATH="$SECTION/$FILENAME"

        mkdir -p "$KNOWLEDGE_REPO/$SECTION"

        # Create summary file (full thread, can be summarized by AI later)
        cat > "$KNOWLEDGE_REPO/$TARGET_PATH" << CONTENT_EOF
# Summary: $ISSUE_TITLE

> Thread from $REPO_FULL_NAME#$ISSUE_NUMBER

## Discussion

$THREAD_CONTENT

---

**Source:** https://github.com/$REPO_FULL_NAME/issues/$ISSUE_NUMBER
**Captured:** $(date '+%Y-%m-%d %H:%M:%S')
**Requested by:** @$USER
CONTENT_EOF

        cd "$KNOWLEDGE_REPO"
        git add "$TARGET_PATH"
        git commit -m "Summary: $ISSUE_TITLE

Source: https://github.com/$REPO_FULL_NAME/issues/$ISSUE_NUMBER
Captured by: @$USER via @atlas mention" || {
            log "Nothing to commit"
            exit 1
        }

        git push origin HEAD 2>/dev/null || log "Warning: Could not push to remote"

        KNOWLEDGE_REPO_URL=$(git config --get remote.origin.url | sed 's/\.git$//' | sed 's/git@github.com:/https:\/\/github.com\//')
        FILE_URL="$KNOWLEDGE_REPO_URL/blob/main/$TARGET_PATH"

        reply_success "$TARGET_PATH" "$FILE_URL"
        log "Successfully captured thread summary to $TARGET_PATH"
        ;;

    help|"")
        reply_to_comment "## Atlas Mention Commands

Use these commands to capture content to the knowledge repo:

- \`@atlas capture this\` - Capture the content above this comment
- \`@atlas capture this to <section>\` - Capture to a specific section
- \`@atlas summarize this\` - Capture the full thread

**Examples:**
\`\`\`
@atlas capture this to decisions
@atlas capture this to architecture
@atlas summarize this thread
\`\`\`"
        ;;

    *)
        reply_error "Unknown command: \`$COMMAND\`. Try \`@atlas help\` for available commands."
        ;;
esac

# Cleanup
rm -f "$CONTEXT_FILE"
