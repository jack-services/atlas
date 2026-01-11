#!/usr/bin/env bash
#
# Atlas Database Migration Script
#
# Usage:
#   ./scripts/db/migrate.sh
#
# Requires:
#   - DATABASE_URL or ATLAS_DATABASE_URL environment variable
#   - psql command available
#
# The database must have pgvector extension available.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/schema.sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

# Get database URL from environment
get_database_url() {
    if [[ -n "${ATLAS_DATABASE_URL:-}" ]]; then
        echo "$ATLAS_DATABASE_URL"
    elif [[ -n "${DATABASE_URL:-}" ]]; then
        echo "$DATABASE_URL"
    else
        error "No database URL found.

Set one of:
  export ATLAS_DATABASE_URL='postgres://user:pass@host:5432/dbname'
  export DATABASE_URL='postgres://user:pass@host:5432/dbname'

Or configure in ~/.atlas/config.yaml"
    fi
}

# Check dependencies
check_dependencies() {
    if ! command -v psql &> /dev/null; then
        error "psql is required but not installed.

Install with:
  brew install postgresql    # macOS
  apt install postgresql-client    # Debian/Ubuntu"
    fi
}

# Check if pgvector extension is available
check_pgvector() {
    local db_url="$1"

    echo "Checking pgvector extension..."

    if ! psql "$db_url" -c "SELECT 1 FROM pg_extension WHERE extname = 'vector'" -t | grep -q 1; then
        warn "pgvector extension not installed. Attempting to create..."

        if ! psql "$db_url" -c "CREATE EXTENSION IF NOT EXISTS vector" 2>/dev/null; then
            error "Could not create pgvector extension.

pgvector must be installed on your PostgreSQL server.
See: https://github.com/pgvector/pgvector#installation"
        fi
    fi

    success "pgvector extension is available"
}

# Run migrations
run_migrations() {
    local db_url="$1"

    echo "Running Atlas database migrations..."

    if psql "$db_url" -f "$SCHEMA_FILE"; then
        success "Migrations completed successfully!"
    else
        error "Migration failed. Check the output above for details."
    fi
}

# Show current state
show_status() {
    local db_url="$1"

    echo ""
    echo "Database Status:"
    echo "================"

    # Check if table exists
    if psql "$db_url" -c "SELECT 1 FROM atlas_embeddings LIMIT 1" &>/dev/null; then
        echo "Table: atlas_embeddings exists"

        # Get stats
        local stats
        stats=$(psql "$db_url" -t -c "SELECT COUNT(*) FROM atlas_embeddings")
        echo "Embeddings: $stats"
    else
        echo "Table: atlas_embeddings does not exist yet"
    fi
}

main() {
    check_dependencies

    local db_url
    db_url=$(get_database_url)

    echo "Atlas Database Migration"
    echo "========================"
    echo ""

    check_pgvector "$db_url"
    run_migrations "$db_url"
    show_status "$db_url"
}

main "$@"
