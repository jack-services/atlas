#!/usr/bin/env bash
#
# Atlas Configuration Reader
#
# Usage:
#   ./scripts/config-reader.sh [key]
#
# Examples:
#   ./scripts/config-reader.sh                    # Validate and display full config
#   ./scripts/config-reader.sh knowledge_repo     # Get specific value
#   ./scripts/config-reader.sh vector_db.url      # Get nested value
#
# Environment variables in config are interpolated automatically.
# Use ${VAR_NAME} syntax in config.yaml for environment variable substitution.

set -euo pipefail

# Load environment variables from .env files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env-loader.sh
source "$SCRIPT_DIR/env-loader.sh"

CONFIG_FILE="${ATLAS_CONFIG_FILE:-$HOME/.atlas/config.yaml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}$1${NC}"
}

# Check if config file exists
check_config_exists() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found at $CONFIG_FILE

To get started:
  1. Create the config directory: mkdir -p ~/.atlas
  2. Copy the example config: cp config/config.example.yaml ~/.atlas/config.yaml
  3. Edit the config with your settings: \$EDITOR ~/.atlas/config.yaml"
    fi
}

# Check for required dependencies
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        error "yq is required but not installed.

Install with:
  brew install yq      # macOS
  apt install yq       # Debian/Ubuntu
  snap install yq      # Snap"
    fi
}

# Interpolate environment variables in a string
# Replaces ${VAR_NAME} with the value of VAR_NAME environment variable
interpolate_env_vars() {
    local value="$1"
    local result="$value"

    # Find all ${VAR_NAME} patterns and replace them
    while [[ "$result" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"

        if [[ -z "$var_value" ]]; then
            warn "Environment variable $var_name is not set"
        fi

        result="${result//\$\{$var_name\}/$var_value}"
    done

    echo "$result"
}

# Read a value from the config file
# Supports dot notation for nested values (e.g., vector_db.url)
read_config() {
    local key="$1"
    local raw_value

    # Convert dot notation to yq path notation
    local yq_key=".$key"
    yq_key="${yq_key//./[\"}"
    yq_key="${yq_key//\[\"/.\"}\"}"
    yq_key="${yq_key#.}"

    # Use simpler approach: just replace dots with actual yq path
    raw_value=$(yq ".$key" "$CONFIG_FILE" 2>/dev/null)

    if [[ "$raw_value" == "null" ]] || [[ -z "$raw_value" ]]; then
        return 1
    fi

    # Interpolate environment variables
    interpolate_env_vars "$raw_value"
}

# Validate the configuration file
validate_config() {
    local errors=0

    echo "Validating Atlas configuration..."
    echo "Config file: $CONFIG_FILE"
    echo ""

    # Check required fields
    local required_fields=("knowledge_repo" "github_org")

    for field in "${required_fields[@]}"; do
        if ! read_config "$field" > /dev/null 2>&1; then
            echo -e "${RED}[MISSING]${NC} $field"
            ((errors++))
        else
            local value
            value=$(read_config "$field")
            echo -e "${GREEN}[OK]${NC} $field = $value"
        fi
    done

    # Check optional but recommended fields
    local optional_fields=("product_repos" "vector_db.url")

    for field in "${optional_fields[@]}"; do
        if ! read_config "$field" > /dev/null 2>&1; then
            echo -e "${YELLOW}[NOT SET]${NC} $field (optional)"
        else
            local value
            value=$(read_config "$field")
            # Mask sensitive values
            if [[ "$field" == *"url"* ]] || [[ "$field" == *"password"* ]]; then
                echo -e "${GREEN}[OK]${NC} $field = ****"
            else
                echo -e "${GREEN}[OK]${NC} $field = $value"
            fi
        fi
    done

    echo ""

    if [[ $errors -gt 0 ]]; then
        error "Configuration validation failed with $errors error(s)"
    else
        success "Configuration is valid!"
    fi
}

# Display full config with interpolated values (masking sensitive data)
display_config() {
    echo "Atlas Configuration"
    echo "==================="
    echo "File: $CONFIG_FILE"
    echo ""

    # Read and display each top-level key
    for key in $(yq 'keys | .[]' "$CONFIG_FILE"); do
        local value
        value=$(read_config "$key")

        # Handle arrays
        if [[ "$value" == *$'\n'* ]] || [[ "$value" == "["* ]]; then
            echo "$key:"
            yq ".$key[]" "$CONFIG_FILE" 2>/dev/null | while read -r item; do
                echo "  - $(interpolate_env_vars "$item")"
            done
        # Handle objects
        elif yq ".$key | type" "$CONFIG_FILE" 2>/dev/null | grep -q "!!map"; then
            echo "$key:"
            for subkey in $(yq ".$key | keys | .[]" "$CONFIG_FILE"); do
                local subvalue
                subvalue=$(read_config "$key.$subkey")
                # Mask sensitive values
                if [[ "$subkey" == *"url"* ]] || [[ "$subkey" == *"password"* ]]; then
                    if [[ -n "$subvalue" ]]; then
                        echo "  $subkey: ****"
                    else
                        echo "  $subkey: (not set)"
                    fi
                else
                    echo "  $subkey: $subvalue"
                fi
            done
        else
            echo "$key: $value"
        fi
    done
}

# Main execution
main() {
    check_dependencies
    check_config_exists

    if [[ $# -eq 0 ]]; then
        # No arguments - validate and display config
        validate_config
    else
        # Get specific key
        local key="$1"
        local value

        if value=$(read_config "$key"); then
            echo "$value"
        else
            error "Key '$key' not found in configuration"
        fi
    fi
}

main "$@"
