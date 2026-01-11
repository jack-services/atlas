#!/bin/bash
# Run build verification
# Usage: ./scripts/verify/run-build.sh [--repo <path>] [--format json|text]
#
# Returns exit code 0 if build succeeds, non-zero otherwise.
# Output includes build results summary.

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
        echo "=== Build Verification ==="
        echo "Status: $status"
        echo "Runner: $runner"
        echo "Exit Code: $exit_code"
        echo ""
        echo "Output:"
        echo "$output"
    fi
}

# Detect build system and run build
run_build() {
    cd "$REPO_PATH"

    # Check for package.json (Node.js project)
    if [[ -f "package.json" ]]; then
        # Check for build script
        if grep -q '"build"' package.json 2>/dev/null; then
            local build_output
            local exit_code=0

            build_output=$(npm run build 2>&1) || exit_code=$?
            output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "npm run build" "$build_output" "$exit_code"
            return $exit_code
        fi

        # Check for TypeScript compilation
        if [[ -f "tsconfig.json" ]]; then
            if command -v npx &>/dev/null; then
                local build_output
                local exit_code=0

                build_output=$(npx tsc --noEmit 2>&1) || exit_code=$?
                output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "tsc --noEmit" "$build_output" "$exit_code"
                return $exit_code
            fi
        fi
    fi

    # Check for Cargo.toml (Rust project)
    if [[ -f "Cargo.toml" ]]; then
        local build_output
        local exit_code=0

        build_output=$(cargo build 2>&1) || exit_code=$?
        output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "cargo build" "$build_output" "$exit_code"
        return $exit_code
    fi

    # Check for go.mod (Go project)
    if [[ -f "go.mod" ]]; then
        local build_output
        local exit_code=0

        build_output=$(go build ./... 2>&1) || exit_code=$?
        output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "go build" "$build_output" "$exit_code"
        return $exit_code
    fi

    # Check for Makefile with build target
    if [[ -f "Makefile" ]]; then
        if grep -q "^build:" Makefile 2>/dev/null; then
            local build_output
            local exit_code=0

            build_output=$(make build 2>&1) || exit_code=$?
            output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "make build" "$build_output" "$exit_code"
            return $exit_code
        elif grep -q "^all:" Makefile 2>/dev/null; then
            local build_output
            local exit_code=0

            build_output=$(make all 2>&1) || exit_code=$?
            output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "make all" "$build_output" "$exit_code"
            return $exit_code
        fi
    fi

    # Check for Python setup.py
    if [[ -f "setup.py" ]]; then
        local build_output
        local exit_code=0

        build_output=$(python setup.py build 2>&1) || exit_code=$?
        output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "python setup.py build" "$build_output" "$exit_code"
        return $exit_code
    fi

    # Check for pyproject.toml with build
    if [[ -f "pyproject.toml" ]]; then
        if command -v python -m build &>/dev/null; then
            local build_output
            local exit_code=0

            build_output=$(python -m build 2>&1) || exit_code=$?
            output_result "$([ $exit_code -eq 0 ] && echo "pass" || echo "fail")" "python -m build" "$build_output" "$exit_code"
            return $exit_code
        fi
    fi

    # No build system found
    output_result "skip" "none" "No build system detected" 0
    return 0
}

# Run build
run_build
