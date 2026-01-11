#!/bin/bash
# Screenshot verification using Puppeteer
# Usage: ./scripts/verify/screenshot.sh [--url <url>] [--urls-file <path>] [--output-dir <path>]
#
# Captures screenshots of configured URLs for visual verification.
# Requires Node.js and Puppeteer to be installed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
URLS=()
URLS_FILE=""
OUTPUT_DIR=".atlas/screenshots"
TIMEOUT=30000
VIEWPORT_WIDTH=1280
VIEWPORT_HEIGHT=800

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            URLS+=("$2")
            shift 2
            ;;
        --urls-file)
            URLS_FILE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --viewport)
            # Format: WIDTHxHEIGHT
            VIEWPORT_WIDTH="${2%x*}"
            VIEWPORT_HEIGHT="${2#*x}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --url <url>         URL to screenshot (can be used multiple times)"
            echo "  --urls-file <path>  File containing URLs (one per line)"
            echo "  --output-dir <path> Directory for screenshots (default: .atlas/screenshots)"
            echo "  --timeout <ms>      Page load timeout in ms (default: 30000)"
            echo "  --viewport WxH      Viewport size (default: 1280x800)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Load URLs from file if specified
if [[ -n "$URLS_FILE" ]] && [[ -f "$URLS_FILE" ]]; then
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        URLS+=("$line")
    done < "$URLS_FILE"
fi

# Check if we have any URLs
if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "No URLs specified. Use --url or --urls-file to specify URLs."
    echo "Skipping screenshot verification."
    echo '{"status": "skip", "message": "No URLs configured"}'
    exit 0
fi

# Check for Node.js
if ! command -v node &>/dev/null; then
    echo "Error: Node.js is required for screenshot verification" >&2
    echo '{"status": "error", "message": "Node.js not found"}'
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temporary Node.js script for Puppeteer
PUPPETEER_SCRIPT=$(mktemp /tmp/atlas-screenshot-XXXXXX.js)
trap "rm -f $PUPPETEER_SCRIPT" EXIT

cat > "$PUPPETEER_SCRIPT" << 'PUPPETEER_EOF'
const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const args = process.argv.slice(2);
const urls = JSON.parse(args[0]);
const outputDir = args[1];
const timeout = parseInt(args[2], 10);
const viewportWidth = parseInt(args[3], 10);
const viewportHeight = parseInt(args[4], 10);

async function captureScreenshots() {
    let browser;
    const results = [];

    try {
        browser = await puppeteer.launch({
            headless: 'new',
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });

        const page = await browser.newPage();
        await page.setViewport({ width: viewportWidth, height: viewportHeight });

        for (const url of urls) {
            const result = { url, status: 'success', screenshot: null, error: null };

            try {
                await page.goto(url, { waitUntil: 'networkidle2', timeout });

                // Generate filename from URL
                const urlObj = new URL(url);
                const filename = `${urlObj.hostname}${urlObj.pathname.replace(/\//g, '_')}.png`;
                const filepath = path.join(outputDir, filename);

                await page.screenshot({ path: filepath, fullPage: false });
                result.screenshot = filepath;
            } catch (err) {
                result.status = 'error';
                result.error = err.message;
            }

            results.push(result);
        }
    } catch (err) {
        console.error(JSON.stringify({ status: 'error', message: err.message }));
        process.exit(1);
    } finally {
        if (browser) await browser.close();
    }

    console.log(JSON.stringify({ status: 'success', screenshots: results }));
}

captureScreenshots();
PUPPETEER_EOF

# Check if Puppeteer is installed
if ! node -e "require('puppeteer')" 2>/dev/null; then
    echo "Puppeteer not installed. Installing locally..."
    npm install puppeteer --no-save 2>/dev/null || {
        echo "Failed to install Puppeteer. Please install it manually:"
        echo "  npm install -g puppeteer"
        echo '{"status": "error", "message": "Puppeteer installation failed"}'
        exit 1
    }
fi

# Convert URLs array to JSON
URLS_JSON=$(printf '%s\n' "${URLS[@]}" | python3 -c 'import sys,json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))')

# Run the Puppeteer script
node "$PUPPETEER_SCRIPT" "$URLS_JSON" "$OUTPUT_DIR" "$TIMEOUT" "$VIEWPORT_WIDTH" "$VIEWPORT_HEIGHT"
