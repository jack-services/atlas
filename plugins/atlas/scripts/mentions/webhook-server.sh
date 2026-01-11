#!/bin/bash
# GitHub webhook server for @atlas mentions
# Usage: ./scripts/mentions/webhook-server.sh [--port <port>] [--secret <secret>]
#
# Listens for GitHub webhook events and processes @atlas mentions.
# For production, use a proper webhook service or GitHub App.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
PORT=9000
WEBHOOK_SECRET=""
LOG_FILE=".atlas/mentions.log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --secret)
            WEBHOOK_SECRET="$2"
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
            echo "  --port <port>     Port to listen on (default: 9000)"
            echo "  --secret <secret> GitHub webhook secret for verification"
            echo "  --log <file>      Log file path (default: .atlas/mentions.log)"
            echo ""
            echo "Setup:"
            echo "  1. Create a GitHub webhook in your repository settings"
            echo "  2. Set the webhook URL to http://your-server:$PORT/webhook"
            echo "  3. Select 'Issue comments' and 'Pull request review comments' events"
            echo "  4. Set a secret and pass it via --secret"
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

log "Starting @atlas mention webhook server on port $PORT"
echo ""
echo "Configure your GitHub webhook:"
echo "  URL: http://your-server:$PORT/webhook"
echo "  Content type: application/json"
echo "  Events: Issue comments, Pull request review comments"
if [[ -n "$WEBHOOK_SECRET" ]]; then
    echo "  Secret: (configured)"
else
    echo "  Secret: (not configured - webhook validation disabled)"
fi
echo ""

# Check for Python (needed for JSON parsing)
if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is required" >&2
    exit 1
fi

# Create a simple Python HTTP server for handling webhooks
python3 << 'PYTHON_SERVER'
import http.server
import json
import subprocess
import os
import sys
import hmac
import hashlib

PORT = int(os.environ.get('PORT', 9000))
WEBHOOK_SECRET = os.environ.get('WEBHOOK_SECRET', '')
SCRIPT_DIR = os.environ.get('SCRIPT_DIR', '.')
LOG_FILE = os.environ.get('LOG_FILE', '.atlas/mentions.log')

def log(msg):
    import datetime
    timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{timestamp}] {msg}"
    print(line)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def do_POST(self):
        if self.path != '/webhook':
            self.send_response(404)
            self.end_headers()
            return

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        # Verify webhook signature if secret is configured
        if WEBHOOK_SECRET:
            signature = self.headers.get('X-Hub-Signature-256', '')
            expected = 'sha256=' + hmac.new(
                WEBHOOK_SECRET.encode(),
                body,
                hashlib.sha256
            ).hexdigest()

            if not hmac.compare_digest(signature, expected):
                log("Webhook signature verification failed")
                self.send_response(401)
                self.end_headers()
                return

        try:
            payload = json.loads(body.decode('utf-8'))
        except json.JSONDecodeError:
            log("Invalid JSON payload")
            self.send_response(400)
            self.end_headers()
            return

        # Process the webhook
        event_type = self.headers.get('X-GitHub-Event', '')
        action = payload.get('action', '')

        log(f"Received webhook: {event_type} ({action})")

        # Handle comment events
        if event_type in ['issue_comment', 'pull_request_review_comment']:
            if action == 'created':
                comment = payload.get('comment', {})
                comment_body = comment.get('body', '')

                # Check for @atlas mention
                if '@atlas' in comment_body.lower():
                    log(f"Found @atlas mention in comment")
                    self.process_mention(payload, comment)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status": "ok"}')

    def process_mention(self, payload, comment):
        """Process an @atlas mention."""
        comment_body = comment.get('body', '')
        comment_url = comment.get('html_url', '')
        user = comment.get('user', {}).get('login', 'unknown')

        # Get issue/PR context
        issue = payload.get('issue', {})
        pr = payload.get('pull_request', {})
        repo = payload.get('repository', {})

        context = {
            'repo_full_name': repo.get('full_name', ''),
            'repo_name': repo.get('name', ''),
            'issue_number': issue.get('number') or pr.get('number'),
            'issue_title': issue.get('title') or pr.get('title'),
            'comment_body': comment_body,
            'comment_url': comment_url,
            'user': user,
            'comment_id': comment.get('id')
        }

        log(f"Processing mention from {user} in {context['repo_full_name']}#{context['issue_number']}")

        # Write context to temp file for processing
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(context, f)
            context_file = f.name

        # Call the mention handler script
        try:
            subprocess.Popen(
                [f'{SCRIPT_DIR}/process-mention.sh', context_file],
                stdout=open(LOG_FILE, 'a'),
                stderr=subprocess.STDOUT
            )
            log("Spawned mention processor")
        except Exception as e:
            log(f"Failed to process mention: {e}")

if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', PORT), WebhookHandler)
    log(f"Server listening on port {PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Server shutting down")
        server.shutdown()
PYTHON_SERVER
