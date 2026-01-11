#!/bin/bash
# Create a pull request with verification evidence
# Usage: ./scripts/github/create-pr.sh --repo <owner/repo> --issue <number> [options]
#
# Creates a PR from the current branch, links it to an issue, and includes
# verification evidence in the description.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
REPO=""
ISSUE_NUMBER=""
BRANCH=""
BASE_BRANCH="main"
TITLE=""
BODY=""
VERIFICATION_REPORT=""
SCREENSHOTS_DIR=""
DRAFT="false"

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
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --base)
            BASE_BRANCH="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        --body)
            BODY="$2"
            shift 2
            ;;
        --verification-report)
            VERIFICATION_REPORT="$2"
            shift 2
            ;;
        --screenshots-dir)
            SCREENSHOTS_DIR="$2"
            shift 2
            ;;
        --draft)
            DRAFT="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --repo <owner/repo> --issue <number> [options]"
            echo ""
            echo "Required:"
            echo "  --repo <owner/repo>         GitHub repository (e.g., 'acme/app')"
            echo "  --issue <number>            Issue number to link"
            echo ""
            echo "Options:"
            echo "  --branch <name>             Branch name (default: current branch)"
            echo "  --base <name>               Base branch (default: main)"
            echo "  --title <text>              PR title (default: from issue)"
            echo "  --body <text>               Additional body text"
            echo "  --verification-report <path> Path to verification report JSON"
            echo "  --screenshots-dir <path>    Directory containing screenshots"
            echo "  --draft                     Create as draft PR"
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

# Get current branch if not specified
if [[ -z "$BRANCH" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

# Fetch issue details if title not provided
if [[ -z "$TITLE" ]]; then
    ISSUE_DATA=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json title,body 2>/dev/null || echo '{}')
    TITLE=$(echo "$ISSUE_DATA" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("title",""))' 2>/dev/null || echo "")

    if [[ -z "$TITLE" ]]; then
        echo "Error: Could not fetch issue title and --title not provided" >&2
        exit 1
    fi
fi

# Build verification section
VERIFICATION_SECTION=""
if [[ -n "$VERIFICATION_REPORT" ]] && [[ -f "$VERIFICATION_REPORT" ]]; then
    STATUS=$(python3 -c "import json; d=json.load(open('$VERIFICATION_REPORT')); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
    STEPS=$(python3 -c "
import json
d = json.load(open('$VERIFICATION_REPORT'))
steps = d.get('steps', {})
for name, status in steps.items():
    icon = '✓' if status == 'pass' else ('✗' if status == 'fail' else '-')
    print(f'- {icon} {name}: {status}')
" 2>/dev/null || echo "")

    if [[ "$STATUS" == "pass" ]]; then
        VERIFICATION_SECTION="## ✅ Verification Passed

$STEPS"
    else
        VERIFICATION_SECTION="## ⚠️ Verification Status: $STATUS

$STEPS"
    fi
fi

# Build screenshots section
SCREENSHOTS_SECTION=""
if [[ -n "$SCREENSHOTS_DIR" ]] && [[ -d "$SCREENSHOTS_DIR" ]]; then
    SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOTS_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$SCREENSHOT_COUNT" -gt 0 ]]; then
        SCREENSHOTS_SECTION="## 📸 Screenshots

*$SCREENSHOT_COUNT screenshot(s) captured. See attached files.*"
    fi
fi

# Get list of changed files
CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"..."$BRANCH" 2>/dev/null | head -20)
CHANGED_FILES_SECTION=""
if [[ -n "$CHANGED_FILES" ]]; then
    CHANGED_FILES_SECTION="## 📁 Changed Files

\`\`\`
$CHANGED_FILES
\`\`\`"
fi

# Build full PR body
PR_BODY="## Summary

$BODY

Closes #$ISSUE_NUMBER

$VERIFICATION_SECTION

$SCREENSHOTS_SECTION

$CHANGED_FILES_SECTION

---
*Created by Atlas /execute command*"

# Create the PR
DRAFT_FLAG=""
if [[ "$DRAFT" == "true" ]]; then
    DRAFT_FLAG="--draft"
fi

# Check if branch is pushed
if ! git ls-remote --exit-code --heads origin "$BRANCH" &>/dev/null; then
    echo "Pushing branch $BRANCH to origin..."
    git push -u origin "$BRANCH"
fi

# Create the PR
echo "Creating PR..."
PR_URL=$(gh pr create \
    --repo "$REPO" \
    --head "$BRANCH" \
    --base "$BASE_BRANCH" \
    --title "$TITLE" \
    --body "$PR_BODY" \
    $DRAFT_FLAG)

if [[ -n "$PR_URL" ]]; then
    echo "PR created: $PR_URL"

    # Output JSON for programmatic use
    PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
    echo "{\"success\": true, \"url\": \"$PR_URL\", \"number\": $PR_NUMBER}"
else
    echo "Failed to create PR" >&2
    echo '{"success": false, "error": "PR creation failed"}'
    exit 1
fi
