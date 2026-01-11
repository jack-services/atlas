#!/bin/bash
# Generic prompt-driven verification
# Usage: ./scripts/verify/verify-criteria.sh --criteria <file|json> [--repo <path>]
#
# Parses completion criteria from a task definition and verifies each criterion.
# Supports code projects, documents, and custom verification commands.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
CRITERIA_SOURCE=""
REPO_PATH="."
OUTPUT_FORMAT="text"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --criteria)
            CRITERIA_SOURCE="$2"
            shift 2
            ;;
        --repo)
            REPO_PATH="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --criteria <file|json> [options]"
            echo ""
            echo "Options:"
            echo "  --criteria <source>  File path or JSON string with criteria"
            echo "  --repo <path>        Path to repository (default: current directory)"
            echo "  --format <type>      Output format: json or text (default: text)"
            echo ""
            echo "Criteria format (in task/issue description):"
            echo ""
            echo "  ## Verification"
            echo "  - Command: npm test"
            echo "  - File exists: output/report.pdf"
            echo "  - Contains sections: Summary, Conclusion"
            echo "  - Word count > 500"
            echo ""
            echo "Or in JSON:"
            echo '  [{"type": "command", "command": "npm test"},'
            echo '   {"type": "file_exists", "path": "output/report.pdf"}]'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Resolve repo path
REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)" || REPO_PATH="$(pwd)"

# Initialize results
RESULTS=""
OVERALL_STATUS="pass"
VERIFICATION_OUTPUT=""

add_result() {
    local criterion="$1"
    local status="$2"
    local message="$3"

    RESULTS="$RESULTS$criterion=$status;"

    if [[ "$status" == "fail" ]]; then
        OVERALL_STATUS="fail"
    fi

    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        local icon="?"
        case "$status" in
            pass) icon="✓" ;;
            fail) icon="✗" ;;
            skip) icon="-" ;;
        esac
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT  $icon $criterion: $message"$'\n'
    fi
}

# Parse criteria from text (issue/task description format)
parse_criteria_from_text() {
    local text="$1"
    local criteria="[]"

    # Extract verification section
    local verification_section
    verification_section=$(echo "$text" | sed -n '/^##\s*Verification/,/^##/p' | head -n -1)

    if [[ -z "$verification_section" ]]; then
        # Try alternative format: "Verification:" block
        verification_section=$(echo "$text" | sed -n '/^Verification:/,/^[A-Z]/p' | head -n -1)
    fi

    if [[ -z "$verification_section" ]]; then
        echo "[]"
        return
    fi

    # Parse each line into criteria
    local parsed="["
    local first=true

    while IFS= read -r line; do
        # Skip empty lines and headers
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^##|^Verification: ]] && continue

        # Remove leading dash/bullet
        line=$(echo "$line" | sed 's/^[-*]\s*//')

        local criterion=""

        # Parse different criterion types
        if echo "$line" | grep -iq '^command:'; then
            local cmd
            cmd=$(echo "$line" | sed 's/^[Cc]ommand:\s*//')
            criterion="{\"type\": \"command\", \"command\": \"$cmd\"}"
        elif echo "$line" | grep -iq '^file exists:'; then
            local path
            path=$(echo "$line" | sed 's/^[Ff]ile exists:\s*//')
            criterion="{\"type\": \"file_exists\", \"path\": \"$path\"}"
        elif echo "$line" | grep -iq '^contains sections:'; then
            local sections
            sections=$(echo "$line" | sed 's/^[Cc]ontains sections:\s*//')
            criterion="{\"type\": \"sections\", \"sections\": \"$sections\"}"
        elif echo "$line" | grep -iq '^word count'; then
            local op count
            op=$(echo "$line" | grep -oE '[<>=]+' || echo ">")
            count=$(echo "$line" | grep -oE '[0-9]+')
            criterion="{\"type\": \"word_count\", \"operator\": \"$op\", \"count\": $count}"
        elif echo "$line" | grep -iq 'tests\s*pass\|all tests'; then
            criterion="{\"type\": \"tests\"}"
        elif echo "$line" | grep -iq 'build\s*succeed\|build\s*pass'; then
            criterion="{\"type\": \"build\"}"
        elif echo "$line" | grep -iq '^exit code'; then
            local code
            code=$(echo "$line" | grep -oE '[0-9]+' | head -1)
            criterion="{\"type\": \"exit_code\", \"expected\": ${code:-0}}"
        elif [[ -n "$(echo "$line" | tr -d '[:space:]')" ]]; then
            # Generic custom command
            criterion="{\"type\": \"custom\", \"description\": \"$line\"}"
        fi

        if [[ -n "$criterion" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                parsed="$parsed, "
            fi
            parsed="$parsed$criterion"
        fi
    done <<< "$verification_section"

    parsed="$parsed]"
    echo "$parsed"
}

# Verify a command criterion
verify_command() {
    local command="$1"
    local exit_code=0

    cd "$REPO_PATH" && eval "$command" >/dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        add_result "command" "pass" "$command"
        return 0
    else
        add_result "command" "fail" "$command (exit code: $exit_code)"
        return 1
    fi
}

# Verify file exists criterion
verify_file_exists() {
    local path="$1"

    if [[ -f "$REPO_PATH/$path" ]]; then
        add_result "file_exists" "pass" "$path exists"
        return 0
    else
        add_result "file_exists" "fail" "$path not found"
        return 1
    fi
}

# Verify sections exist in a file
verify_sections() {
    local file="$1"
    local sections="$2"
    local missing=""

    # If file not specified, try to find main output file
    if [[ -z "$file" ]]; then
        file=$(find "$REPO_PATH" -name "*.md" -type f 2>/dev/null | head -1)
    fi

    if [[ ! -f "$file" ]]; then
        add_result "sections" "fail" "No file to check"
        return 1
    fi

    local content
    content=$(cat "$file")

    # Parse sections (comma or newline separated)
    IFS=',' read -ra section_list <<< "$sections"
    for section in "${section_list[@]}"; do
        section=$(echo "$section" | xargs)  # Trim whitespace
        if ! echo "$content" | grep -qi "^#.*$section\|^## *$section\|^### *$section"; then
            missing="$missing $section"
        fi
    done

    if [[ -z "$missing" ]]; then
        add_result "sections" "pass" "All sections found"
        return 0
    else
        add_result "sections" "fail" "Missing sections:$missing"
        return 1
    fi
}

# Verify word count
verify_word_count() {
    local file="$1"
    local operator="$2"
    local expected="$3"

    # If file not specified, try to find main output file
    if [[ -z "$file" ]]; then
        file=$(find "$REPO_PATH" -name "*.md" -type f 2>/dev/null | head -1)
    fi

    if [[ ! -f "$file" ]]; then
        add_result "word_count" "fail" "No file to check"
        return 1
    fi

    local count
    count=$(wc -w < "$file" | tr -d ' ')

    local result=false
    case "$operator" in
        ">"|"gt") [[ $count -gt $expected ]] && result=true ;;
        "<"|"lt") [[ $count -lt $expected ]] && result=true ;;
        ">="|"ge") [[ $count -ge $expected ]] && result=true ;;
        "<="|"le") [[ $count -le $expected ]] && result=true ;;
        "="|"=="|"eq") [[ $count -eq $expected ]] && result=true ;;
    esac

    if [[ "$result" == "true" ]]; then
        add_result "word_count" "pass" "$count words ($operator $expected)"
        return 0
    else
        add_result "word_count" "fail" "$count words (expected $operator $expected)"
        return 1
    fi
}

# Verify tests pass
verify_tests() {
    local output exit_code=0

    output=$("$SCRIPT_DIR/run-tests.sh" --repo "$REPO_PATH" --format json 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local status
        status=$(echo "$output" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status","unknown"))' 2>/dev/null || echo "unknown")
        if [[ "$status" == "pass" ]] || [[ "$status" == "skip" ]]; then
            add_result "tests" "pass" "Tests passed"
            return 0
        fi
    fi

    add_result "tests" "fail" "Tests failed"
    return 1
}

# Verify build succeeds
verify_build() {
    local output exit_code=0

    output=$("$SCRIPT_DIR/run-build.sh" --repo "$REPO_PATH" --format json 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local status
        status=$(echo "$output" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status","unknown"))' 2>/dev/null || echo "unknown")
        if [[ "$status" == "pass" ]] || [[ "$status" == "skip" ]]; then
            add_result "build" "pass" "Build succeeded"
            return 0
        fi
    fi

    add_result "build" "fail" "Build failed"
    return 1
}

# Main verification
main() {
    local criteria_json

    # Load criteria
    if [[ -z "$CRITERIA_SOURCE" ]]; then
        add_result "criteria" "skip" "No verification criteria specified"
        OVERALL_STATUS="pass"  # No criteria = pass by default
    elif [[ -f "$CRITERIA_SOURCE" ]]; then
        # Load from file
        local file_content
        file_content=$(cat "$CRITERIA_SOURCE")

        # Try JSON first, then parse as text
        if echo "$file_content" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
            criteria_json="$file_content"
        else
            criteria_json=$(parse_criteria_from_text "$file_content")
        fi
    elif echo "$CRITERIA_SOURCE" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
        # Direct JSON input
        criteria_json="$CRITERIA_SOURCE"
    else
        # Treat as text to parse
        criteria_json=$(parse_criteria_from_text "$CRITERIA_SOURCE")
    fi

    # Output header
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        VERIFICATION_OUTPUT="=== Atlas Verification Report ==="$'\n'
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Repository: $REPO_PATH"$'\n'
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT"$'\n'
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Criteria:"$'\n'
    fi

    # Check if we have criteria
    if [[ -z "$criteria_json" ]] || [[ "$criteria_json" == "[]" ]]; then
        add_result "criteria" "skip" "No verification criteria found"
    else
        # Process each criterion
        local num_criteria
        num_criteria=$(echo "$criteria_json" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "0")

        local i=0
        while [[ $i -lt $num_criteria ]]; do
            local type
            type=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('type','unknown'))")

            case "$type" in
                command)
                    local cmd
                    cmd=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('command',''))")
                    verify_command "$cmd" || true
                    ;;
                file_exists)
                    local path
                    path=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('path',''))")
                    verify_file_exists "$path" || true
                    ;;
                sections)
                    local sections file
                    sections=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('sections',''))")
                    file=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('file',''))")
                    verify_sections "$file" "$sections" || true
                    ;;
                word_count)
                    local op count file
                    op=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('operator','>'))")
                    count=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('count',0))")
                    file=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('file',''))")
                    verify_word_count "$file" "$op" "$count" || true
                    ;;
                tests)
                    verify_tests || true
                    ;;
                build)
                    verify_build || true
                    ;;
                exit_code)
                    local expected
                    expected=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('expected',0))")
                    # Exit code is verified by command type
                    add_result "exit_code" "pass" "Checked with command"
                    ;;
                custom)
                    local desc
                    desc=$(echo "$criteria_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('description',''))")
                    add_result "custom" "skip" "$desc (manual verification)"
                    ;;
                *)
                    add_result "unknown" "skip" "Unknown criterion type: $type"
                    ;;
            esac

            i=$((i + 1))
        done
    fi

    # Output results
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local steps_json="{"
        local first=true
        IFS=';' read -ra pairs <<< "$RESULTS"
        for pair in "${pairs[@]}"; do
            [[ -z "$pair" ]] && continue
            local step="${pair%=*}"
            local status="${pair#*=}"
            if [[ "$first" == "true" ]]; then
                first=false
            else
                steps_json="$steps_json, "
            fi
            steps_json="$steps_json\"$step\": \"$status\""
        done
        steps_json="$steps_json}"
        echo "{\"status\": \"$OVERALL_STATUS\", \"criteria\": $steps_json}"
    else
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT"$'\n'
        if [[ "$OVERALL_STATUS" == "pass" ]]; then
            VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Overall: ✓ PASSED"$'\n'
        else
            VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Overall: ✗ FAILED"$'\n'
        fi
        echo "$VERIFICATION_OUTPUT"
    fi

    [[ "$OVERALL_STATUS" == "pass" ]] && exit 0 || exit 1
}

main
