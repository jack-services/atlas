#!/bin/bash
# Main verification orchestrator
# Usage: ./scripts/verify/verify.sh [--repo <path>] [--config <path>] [--format json|text] [--skip <step>]
#
# Runs all verification steps:
# 1. Tests (run-tests.sh)
# 2. Build (run-build.sh)
# 3. Screenshots (screenshot.sh) - if configured
# 4. Custom verification steps from config
#
# Returns exit code 0 only if ALL required verifications pass.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
REPO_PATH="."
CONFIG_PATH="$HOME/.atlas/config.yaml"
OUTPUT_FORMAT="text"
SKIP_STEPS=""
REQUIRED_STEPS="tests,build"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO_PATH="$2"
            shift 2
            ;;
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --skip)
            SKIP_STEPS="$SKIP_STEPS,$2"
            shift 2
            ;;
        --require)
            REQUIRED_STEPS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --repo <path>      Path to repository (default: current directory)"
            echo "  --config <path>    Path to config file (default: ~/.atlas/config.yaml)"
            echo "  --format <type>    Output format: json or text (default: text)"
            echo "  --skip <step>      Skip a verification step (can be used multiple times)"
            echo "  --require <steps>  Comma-separated list of required steps"
            echo ""
            echo "Available steps: tests, build, screenshots, lint, custom"
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

# Initialize results as colon-separated key=value pairs
RESULTS=""
OVERALL_STATUS="pass"
VERIFICATION_OUTPUT=""

# Function to check if step should be skipped
should_skip() {
    local step="$1"
    echo "$SKIP_STEPS" | grep -q ",$step\|^$step," && return 0
    [[ "$SKIP_STEPS" == "$step" ]] && return 0
    return 1
}

# Function to check if step is required
is_required() {
    local step="$1"
    echo "$REQUIRED_STEPS" | grep -q ",$step\|^$step,\|^$step$" && return 0
    return 1
}

# Function to add result
add_result() {
    local step="$1"
    local status="$2"
    local message="$3"

    RESULTS="$RESULTS$step=$status;"

    if [[ "$status" == "fail" ]] && is_required "$step"; then
        OVERALL_STATUS="fail"
    fi

    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        local icon="?"
        case "$status" in
            pass) icon="✓" ;;
            fail) icon="✗" ;;
            skip) icon="-" ;;
        esac
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT  $icon $step: $message"$'\n'
    fi
}

# Load custom verification from config
load_custom_verification() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        return
    fi

    # For now, use config-reader if available
    if [[ -x "$ROOT_DIR/scripts/config-reader.sh" ]]; then
        # Read screenshot URLs
        SCREENSHOT_URLS=$("$ROOT_DIR/scripts/config-reader.sh" verification.screenshots.urls 2>/dev/null || echo "")
        export SCREENSHOT_URLS

        # Read custom steps (as JSON array)
        CUSTOM_STEPS=$("$ROOT_DIR/scripts/config-reader.sh" verification.custom --format json 2>/dev/null || echo "[]")
        export CUSTOM_STEPS
    fi
}

# Run tests verification
run_tests_verification() {
    if should_skip "tests"; then
        add_result "tests" "skip" "Skipped by user"
        return 0
    fi

    local output
    local exit_code=0

    output=$("$SCRIPT_DIR/run-tests.sh" --repo "$REPO_PATH" --format json 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local status
        status=$(echo "$output" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status","unknown"))' 2>/dev/null || echo "unknown")

        if [[ "$status" == "pass" ]]; then
            add_result "tests" "pass" "All tests passed"
        elif [[ "$status" == "skip" ]]; then
            add_result "tests" "skip" "No test runner detected"
        else
            add_result "tests" "fail" "Tests failed"
            return 1
        fi
    else
        add_result "tests" "fail" "Tests failed with exit code $exit_code"
        return 1
    fi
    return 0
}

# Run build verification
run_build_verification() {
    if should_skip "build"; then
        add_result "build" "skip" "Skipped by user"
        return 0
    fi

    local output
    local exit_code=0

    output=$("$SCRIPT_DIR/run-build.sh" --repo "$REPO_PATH" --format json 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local status
        status=$(echo "$output" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status","unknown"))' 2>/dev/null || echo "unknown")

        if [[ "$status" == "pass" ]]; then
            add_result "build" "pass" "Build succeeded"
        elif [[ "$status" == "skip" ]]; then
            add_result "build" "skip" "No build system detected"
        else
            add_result "build" "fail" "Build failed"
            return 1
        fi
    else
        add_result "build" "fail" "Build failed with exit code $exit_code"
        return 1
    fi
    return 0
}

# Run screenshot verification
run_screenshot_verification() {
    if should_skip "screenshots"; then
        add_result "screenshots" "skip" "Skipped by user"
        return 0
    fi

    # Check if screenshots are configured
    if [[ -z "$SCREENSHOT_URLS" ]] && [[ ! -f "$REPO_PATH/.atlas/screenshot-urls.txt" ]]; then
        add_result "screenshots" "skip" "No screenshot URLs configured"
        return 0
    fi

    local urls_arg=""
    if [[ -n "$SCREENSHOT_URLS" ]]; then
        # Parse URLs from config (comma-separated or newline)
        for url in $(echo "$SCREENSHOT_URLS" | tr ',' '\n'); do
            urls_arg="$urls_arg --url $url"
        done
    elif [[ -f "$REPO_PATH/.atlas/screenshot-urls.txt" ]]; then
        urls_arg="--urls-file $REPO_PATH/.atlas/screenshot-urls.txt"
    fi

    local output
    local exit_code=0

    output=$("$SCRIPT_DIR/screenshot.sh" $urls_arg --output-dir "$REPO_PATH/.atlas/screenshots" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        add_result "screenshots" "pass" "Screenshots captured"
    else
        add_result "screenshots" "fail" "Screenshot capture failed"
    fi
    return 0
}

# Run custom verification steps
run_custom_verification() {
    if should_skip "custom"; then
        return 0
    fi

    if [[ -z "$CUSTOM_STEPS" ]] || [[ "$CUSTOM_STEPS" == "[]" ]]; then
        return 0
    fi

    # Parse and run each custom step
    local num_steps
    num_steps=$(echo "$CUSTOM_STEPS" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "0")

    local i=0
    while [[ $i -lt $num_steps ]]; do
        local name command required
        name=$(echo "$CUSTOM_STEPS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('name','step$i'))")
        command=$(echo "$CUSTOM_STEPS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i].get('command',''))")
        required=$(echo "$CUSTOM_STEPS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d[$i].get('required',False)).lower())")

        if [[ -n "$command" ]]; then
            # Add to required steps if needed
            if [[ "$required" == "true" ]]; then
                REQUIRED_STEPS="$REQUIRED_STEPS,$name"
            fi

            local exit_code=0
            cd "$REPO_PATH" && eval "$command" >/dev/null 2>&1 || exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                add_result "$name" "pass" "Custom step succeeded"
            else
                add_result "$name" "fail" "Custom step failed"
            fi
        fi

        i=$((i + 1))
    done
}

# Build JSON output from results
build_json_output() {
    local steps_json="{"
    local first=true

    # Parse results string (format: step=status;step=status;)
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

    echo "{\"status\": \"$OVERALL_STATUS\", \"steps\": $steps_json}"
}

# Main verification flow
main() {
    load_custom_verification

    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        VERIFICATION_OUTPUT="=== Atlas Verification Report ==="$'\n'
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Repository: $REPO_PATH"$'\n'
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT"$'\n'
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Steps:"$'\n'
    fi

    # Run all verification steps
    run_tests_verification || true
    run_build_verification || true
    run_screenshot_verification || true
    run_custom_verification || true

    # Output results
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        build_json_output
    else
        VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT"$'\n'
        if [[ "$OVERALL_STATUS" == "pass" ]]; then
            VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Overall: ✓ PASSED"$'\n'
        else
            VERIFICATION_OUTPUT="$VERIFICATION_OUTPUT""Overall: ✗ FAILED"$'\n'
        fi

        echo "$VERIFICATION_OUTPUT"
    fi

    # Return appropriate exit code
    if [[ "$OVERALL_STATUS" == "pass" ]]; then
        exit 0
    else
        exit 1
    fi
}

main
