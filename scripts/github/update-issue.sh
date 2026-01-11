#!/bin/bash
# Update an issue with completion summary and status
# Usage: ./scripts/github/update-issue.sh --repo <owner/repo> --issue <number> [options]
#
# Adds completion comment, updates labels, and optionally closes the issue.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
REPO=""
ISSUE_NUMBER=""
STATUS=""
SUMMARY=""
VERIFICATION_REPORT=""
PR_URL=""
ADD_LABELS=""
REMOVE_LABELS=""
CLOSE_ISSUE="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO="$2"
            shift 2
            ;;
        --issue)
            ISSUE_NUMBER="$2"
            shift 2
            ;;
        --status)
            STATUS="$2"
            shift 2
            ;;
        --summary)
            SUMMARY="$2"
            shift 2
            ;;
        --verification-report)
            VERIFICATION_REPORT="$2"
            shift 2
            ;;
        --pr-url)
            PR_URL="$2"
            shift 2
            ;;
        --add-label)
            ADD_LABELS="$ADD_LABELS,$2"
            shift 2
            ;;
        --remove-label)
            REMOVE_LABELS="$REMOVE_LABELS,$2"
            shift 2
            ;;
        --close)
            CLOSE_ISSUE="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --repo <owner/repo> --issue <number> [options]"
            echo ""
            echo "Required:"
            echo "  --repo <owner/repo>         GitHub repository"
            echo "  --issue <number>            Issue number to update"
            echo ""
            echo "Options:"
            echo "  --status <text>             Status (e.g., 'completed', 'in-progress', 'blocked')"
            echo "  --summary <text>            Completion summary"
            echo "  --verification-report <path> Path to verification report JSON"
            echo "  --pr-url <url>              URL of related PR"
            echo "  --add-label <label>         Add label (can be used multiple times)"
            echo "  --remove-label <label>      Remove label (can be used multiple times)"
            echo "  --close                     Close the issue after updating"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$REPO" ]]; then
    echo "Error: --repo is required" >&2
    exit 1
fi

if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "Error: --issue is required" >&2
    exit 1
fi

# Build verification section
VERIFICATION_SECTION=""
if [[ -n "$VERIFICATION_REPORT" ]] && [[ -f "$VERIFICATION_REPORT" ]]; then
    VER_STATUS=$(python3 -c "import json; d=json.load(open('$VERIFICATION_REPORT')); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
    STEPS=$(python3 -c "
import json
d = json.load(open('$VERIFICATION_REPORT'))
steps = d.get('steps', {})
for name, status in steps.items():
    icon = '✓' if status == 'pass' else ('✗' if status == 'fail' else '-')
    print(f'| {name} | {icon} {status} |')
" 2>/dev/null || echo "")

    VERIFICATION_SECTION="### Verification Results

| Step | Status |
|------|--------|
$STEPS"
fi

# Build PR section
PR_SECTION=""
if [[ -n "$PR_URL" ]]; then
    PR_SECTION="### Pull Request

$PR_URL"
fi

# Determine status emoji
STATUS_EMOJI=""
case "$STATUS" in
    completed|complete|done) STATUS_EMOJI="✅" ;;
    in-progress|wip) STATUS_EMOJI="🔄" ;;
    blocked) STATUS_EMOJI="🚫" ;;
    failed) STATUS_EMOJI="❌" ;;
    *) STATUS_EMOJI="📝" ;;
esac

# Build the comment body
COMMENT_BODY="## $STATUS_EMOJI Atlas Update"

if [[ -n "$STATUS" ]]; then
    COMMENT_BODY="$COMMENT_BODY

**Status:** $STATUS"
fi

if [[ -n "$SUMMARY" ]]; then
    COMMENT_BODY="$COMMENT_BODY

### Summary

$SUMMARY"
fi

COMMENT_BODY="$COMMENT_BODY

$VERIFICATION_SECTION

$PR_SECTION

---
*Updated by Atlas*"

# Add comment to issue
echo "Adding comment to issue #$ISSUE_NUMBER..."
gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "$COMMENT_BODY"

# Update labels
if [[ -n "$ADD_LABELS" ]]; then
    # Remove leading comma
    ADD_LABELS="${ADD_LABELS#,}"
    echo "Adding labels: $ADD_LABELS"
    gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --add-label "$ADD_LABELS" 2>/dev/null || true
fi

if [[ -n "$REMOVE_LABELS" ]]; then
    # Remove leading comma
    REMOVE_LABELS="${REMOVE_LABELS#,}"
    echo "Removing labels: $REMOVE_LABELS"
    gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --remove-label "$REMOVE_LABELS" 2>/dev/null || true
fi

# Close issue if requested
if [[ "$CLOSE_ISSUE" == "true" ]]; then
    echo "Closing issue #$ISSUE_NUMBER..."
    gh issue close "$ISSUE_NUMBER" --repo "$REPO"
fi

echo "Issue #$ISSUE_NUMBER updated successfully"
echo '{"success": true}'
