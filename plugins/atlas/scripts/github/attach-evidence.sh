#!/bin/bash
# Attach verification evidence to a PR or issue
# Usage: ./scripts/github/attach-evidence.sh --repo <owner/repo> --pr <number> [options]
#
# Attaches screenshots and verification reports as PR comments.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
REPO=""
PR_NUMBER=""
ISSUE_NUMBER=""
SCREENSHOTS_DIR=""
VERIFICATION_REPORT=""
TEST_OUTPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO="$2"
            shift 2
            ;;
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        --issue)
            ISSUE_NUMBER="$2"
            shift 2
            ;;
        --screenshots-dir)
            SCREENSHOTS_DIR="$2"
            shift 2
            ;;
        --verification-report)
            VERIFICATION_REPORT="$2"
            shift 2
            ;;
        --test-output)
            TEST_OUTPUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --repo <owner/repo> [--pr <number> | --issue <number>] [options]"
            echo ""
            echo "Required:"
            echo "  --repo <owner/repo>          GitHub repository"
            echo "  --pr <number> OR --issue <number>"
            echo ""
            echo "Options:"
            echo "  --screenshots-dir <path>     Directory containing screenshots"
            echo "  --verification-report <path> Path to verification report JSON"
            echo "  --test-output <path>         Path to test output file"
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

if [[ -z "$PR_NUMBER" ]] && [[ -z "$ISSUE_NUMBER" ]]; then
    echo "Error: Either --pr or --issue is required" >&2
    exit 1
fi

# Determine target (PR or issue)
TARGET_TYPE=""
TARGET_NUMBER=""
if [[ -n "$PR_NUMBER" ]]; then
    TARGET_TYPE="pr"
    TARGET_NUMBER="$PR_NUMBER"
else
    TARGET_TYPE="issue"
    TARGET_NUMBER="$ISSUE_NUMBER"
fi

# Build evidence comment
EVIDENCE_PARTS=""
ATTACHMENT_COUNT=0

# Add verification report if present
if [[ -n "$VERIFICATION_REPORT" ]] && [[ -f "$VERIFICATION_REPORT" ]]; then
    VER_STATUS=$(python3 -c "import json; d=json.load(open('$VERIFICATION_REPORT')); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
    VER_STEPS=$(python3 -c "
import json
d = json.load(open('$VERIFICATION_REPORT'))
steps = d.get('steps', {})
lines = []
for name, status in steps.items():
    icon = '✓' if status == 'pass' else ('✗' if status == 'fail' else '-')
    lines.append(f'| {name} | {icon} {status} |')
print('\n'.join(lines))
" 2>/dev/null || echo "")

    STATUS_ICON="✅"
    if [[ "$VER_STATUS" == "fail" ]]; then
        STATUS_ICON="❌"
    elif [[ "$VER_STATUS" == "skip" ]]; then
        STATUS_ICON="⏭️"
    fi

    EVIDENCE_PARTS="$EVIDENCE_PARTS
### $STATUS_ICON Verification Report

| Step | Status |
|------|--------|
$VER_STEPS
"
    ATTACHMENT_COUNT=$((ATTACHMENT_COUNT + 1))
fi

# Add test output if present
if [[ -n "$TEST_OUTPUT" ]] && [[ -f "$TEST_OUTPUT" ]]; then
    TEST_CONTENT=$(head -100 "$TEST_OUTPUT" 2>/dev/null || echo "Unable to read test output")
    TEST_LINES=$(wc -l < "$TEST_OUTPUT" 2>/dev/null | tr -d ' ' || echo "0")

    EVIDENCE_PARTS="$EVIDENCE_PARTS
### 🧪 Test Output

<details>
<summary>View test output ($TEST_LINES lines)</summary>

\`\`\`
$TEST_CONTENT
\`\`\`

</details>
"
    ATTACHMENT_COUNT=$((ATTACHMENT_COUNT + 1))
fi

# Handle screenshots
if [[ -n "$SCREENSHOTS_DIR" ]] && [[ -d "$SCREENSHOTS_DIR" ]]; then
    SCREENSHOT_FILES=$(ls -1 "$SCREENSHOTS_DIR"/*.png 2>/dev/null || echo "")

    if [[ -n "$SCREENSHOT_FILES" ]]; then
        SCREENSHOT_COUNT=$(echo "$SCREENSHOT_FILES" | wc -l | tr -d ' ')

        # Note: GitHub doesn't support direct file uploads via API in gh CLI
        # Screenshots need to be uploaded separately or hosted externally
        # This section provides instructions for manual attachment

        EVIDENCE_PARTS="$EVIDENCE_PARTS
### 📸 Screenshots ($SCREENSHOT_COUNT captured)

Screenshots are available in: \`$SCREENSHOTS_DIR\`

**Files:**
"
        while IFS= read -r file; do
            filename=$(basename "$file")
            EVIDENCE_PARTS="$EVIDENCE_PARTS
- \`$filename\`"
        done <<< "$SCREENSHOT_FILES"

        EVIDENCE_PARTS="$EVIDENCE_PARTS

*Note: Screenshots can be manually attached by dragging into this PR.*
"
        ATTACHMENT_COUNT=$((ATTACHMENT_COUNT + 1))
    fi
fi

# If no evidence to attach, exit
if [[ $ATTACHMENT_COUNT -eq 0 ]]; then
    echo "No evidence to attach"
    echo '{"success": true, "attachments": 0}'
    exit 0
fi

# Build full comment
COMMENT_BODY="## 📋 Verification Evidence
$EVIDENCE_PARTS
---
*Evidence attached by Atlas*"

# Add comment to PR or issue
echo "Attaching evidence to $TARGET_TYPE #$TARGET_NUMBER..."

if [[ "$TARGET_TYPE" == "pr" ]]; then
    gh pr comment "$TARGET_NUMBER" --repo "$REPO" --body "$COMMENT_BODY"
else
    gh issue comment "$TARGET_NUMBER" --repo "$REPO" --body "$COMMENT_BODY"
fi

echo "Evidence attached successfully"
echo "{\"success\": true, \"attachments\": $ATTACHMENT_COUNT}"
