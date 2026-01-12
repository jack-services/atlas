#!/bin/bash
# Webhook handler for triggering re-indexing
# Usage: ./scripts/db/webhook-handler.sh [--port <port>]
#
# Starts a simple HTTP server that listens for webhook requests.
# When a POST is received, it triggers incremental indexing.
#
# For production use, consider using a proper webhook server
# or cloud function instead of this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment variables from .env files
# shellcheck source=../env-loader.sh
source "$SCRIPT_DIR/../env-loader.sh"

# Default values
PORT=8080
LOG_FILE=".atlas/webhook.log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --log)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --port <port>   Port to listen on (default: 8080)"
            echo "  --log <file>    Log file path (default: .atlas/webhook.log)"
            echo ""
            echo "Webhook endpoints:"
            echo "  POST /index     Trigger incremental indexing"
            echo "  POST /reindex   Trigger full reindexing"
            echo "  GET /status     Check service status"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Check for required tools
if ! command -v nc &>/dev/null && ! command -v ncat &>/dev/null; then
    echo "Error: netcat (nc or ncat) is required" >&2
    echo "Install with: brew install netcat (macOS) or apt install netcat (Linux)" >&2
    exit 1
fi

# Use ncat if available (more features), otherwise nc
NC_CMD="nc"
if command -v ncat &>/dev/null; then
    NC_CMD="ncat"
fi

log "Starting webhook handler on port $PORT"
log "Endpoints: POST /index, POST /reindex, GET /status"

# Handle requests in a loop
while true; do
    # Read the HTTP request
    REQUEST=$($NC_CMD -l -p "$PORT" 2>/dev/null || $NC_CMD -l "$PORT" 2>/dev/null || true)

    if [[ -z "$REQUEST" ]]; then
        continue
    fi

    # Parse the request
    METHOD=$(echo "$REQUEST" | head -1 | cut -d' ' -f1)
    PATH=$(echo "$REQUEST" | head -1 | cut -d' ' -f2)

    log "Received: $METHOD $PATH"

    RESPONSE_CODE="200 OK"
    RESPONSE_BODY=""

    case "$METHOD $PATH" in
        "GET /status")
            RESPONSE_BODY='{"status": "ok", "service": "atlas-webhook"}'
            ;;

        "POST /index")
            log "Triggering incremental index..."
            if "$SCRIPT_DIR/incremental-index.sh" >> "$LOG_FILE" 2>&1; then
                RESPONSE_BODY='{"success": true, "action": "incremental-index"}'
            else
                RESPONSE_CODE="500 Internal Server Error"
                RESPONSE_BODY='{"success": false, "error": "indexing failed"}'
            fi
            ;;

        "POST /reindex")
            log "Triggering full reindex..."
            if "$SCRIPT_DIR/incremental-index.sh" --full >> "$LOG_FILE" 2>&1; then
                RESPONSE_BODY='{"success": true, "action": "full-reindex"}'
            else
                RESPONSE_CODE="500 Internal Server Error"
                RESPONSE_BODY='{"success": false, "error": "indexing failed"}'
            fi
            ;;

        *)
            RESPONSE_CODE="404 Not Found"
            RESPONSE_BODY='{"error": "not found"}'
            ;;
    esac

    # Send response
    RESPONSE="HTTP/1.1 $RESPONSE_CODE\r\nContent-Type: application/json\r\nContent-Length: ${#RESPONSE_BODY}\r\nConnection: close\r\n\r\n$RESPONSE_BODY"

    echo -e "$RESPONSE" | $NC_CMD -l -p "$PORT" 2>/dev/null || echo -e "$RESPONSE" | $NC_CMD -l "$PORT" 2>/dev/null || true

    log "Responded: $RESPONSE_CODE"
done
