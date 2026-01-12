#!/usr/bin/env bash
#
# Atlas Environment Loader
#
# Sources .env files from standard locations.
# Call this at the start of scripts that need environment variables.
#
# Usage (source this file):
#   source "$(dirname "$0")/env-loader.sh"
#
# Search order (first found wins for each variable):
#   1. Already set in environment (not overwritten)
#   2. ~/.atlas/.env
#   3. Atlas repo .env (if ATLAS_PLUGIN_DIR is set)
#   4. Current directory .env

# Load a .env file if it exists
# Does not override existing environment variables
load_env_file() {
    local env_file="$1"

    if [[ -f "$env_file" ]]; then
        # Read each line, skip comments and empty lines
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            # Extract variable name and value
            if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"

                # Remove surrounding quotes if present
                var_value="${var_value#\"}"
                var_value="${var_value%\"}"
                var_value="${var_value#\'}"
                var_value="${var_value%\'}"

                # Only set if not already defined (using eval for compatibility)
                eval "local current_val=\"\${$var_name:-}\""
                if [[ -z "$current_val" ]]; then
                    export "$var_name=$var_value"
                fi
            fi
        done < "$env_file"

        return 0
    fi

    return 1
}

# Load environment files from standard locations
load_atlas_env() {
    local loaded=0

    # 1. ~/.atlas/.env (user-level config)
    if load_env_file "$HOME/.atlas/.env"; then
        loaded=$((loaded + 1))
    fi

    # 2. Atlas plugin directory .env (if we can find it)
    # Try to find the atlas repo from script location
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Walk up to find the atlas repo root (contains .git)
    local check_dir="$script_dir"
    while [[ "$check_dir" != "/" ]]; do
        if [[ -d "$check_dir/.git" ]]; then
            if load_env_file "$check_dir/.env"; then
                loaded=$((loaded + 1))
            fi
            break
        fi
        check_dir="$(dirname "$check_dir")"
    done

    # 3. Current directory .env
    if load_env_file ".env"; then
        loaded=$((loaded + 1))
    fi

    return 0
}

# Auto-load when sourced
load_atlas_env
