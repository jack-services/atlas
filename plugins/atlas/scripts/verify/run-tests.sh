#!/bin/bash
# Run test suite verification
# Usage: ./scripts/verify/run-tests.sh [--repo <path>] [--format json|text]
#
# Returns exit code 0 if tests pass, non-zero otherwise.
# Output includes test results summary.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
REPO_PATH="."
OUTPUT_FORMAT="text"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO_PATH="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--repo <path>] [--format json|text]"
            echo ""
            echo "Options:"
            echo "  --repo <path>     Path to repository (default: current directory)"
            echo "  --format <type>   Output format: json or text (default: text)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Resolve repo path
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# Function to output result
output_result() {
    local status="$1"
    local runner="$2"
    local output="$3"
    local exit_code="$4"

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        # Escape output for JSON
        local escaped_output
        escaped_output=$(echo "$output" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
        echo "{\"status\": \"$status\", \"runner\": \"$runner\", \"output\": $escaped_output, \"exit_code\": $exit_code}"
    else
        echo "=== Test Verification ==="
        echo "Status: $status"
        echo "Runner: $runner"
        echo "Exit Code: $exit_code"
        echo ""
        echo "Output:"
        echo "$output"
    fi
}

# Detect test runner and run tests
run_tests() {
    cd "$REPO_PATH"

    # Check for package.json (Node.js project)
    if [[ -f "package.json" ]]; then
        # Check for test script
        if grep -q '"test"' package.json 2>/dev/null; then
            local test_output
            local exit_code=0

            # Try npm test
            test_output=$(npm test 2>&1) || exit_code=$?
            output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "npm test" "$test_output" "$exit_code"
            return $exit_code
        fi
    fi

    # Check for pytest (Python project)
    if [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]] || [[ -d "tests" ]]; then
        if command -v pytest &>/dev/null; then
            local test_output
            local exit_code=0

            test_output=$(pytest 2>&1) || exit_code=$?
            output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "pytest" "$test_output" "$exit_code"
            return $exit_code
        fi
    fi

    # Check for Cargo.toml (Rust project)
    if [[ -f "Cargo.toml" ]]; then
        local test_output
        local exit_code=0

        test_output=$(cargo test 2>&1) || exit_code=$?
        output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "cargo test" "$test_output" "$exit_code"
        return $exit_code
    fi

    # Check for go.mod (Go project)
    if [[ -f "go.mod" ]]; then
        local test_output
        local exit_code=0

        test_output=$(go test ./... 2>&1) || exit_code=$?
        output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "go test" "$test_output" "$exit_code"
        return $exit_code
    fi

    # Check for Makefile with test target
    if [[ -f "Makefile" ]] && grep -q "^test:" Makefile 2>/dev/null; then
        local test_output
        local exit_code=0

        test_output=$(make test 2>&1) || exit_code=$?
        output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "make test" "$test_output" "$exit_code"
        return $exit_code
    fi

    # No test runner found
    output_result "skip" "none" "No test runner detected" 0
    return 0
}

# Run tests
run_tests
