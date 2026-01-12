#!/usr/bin/env bash
#
# Atlas Document Chunking Script
#
# Usage:
#   ./scripts/db/chunk.sh <file>
#
# Chunks a document into sections suitable for embedding.
# Output is JSON lines format with chunk metadata.
#
# Supported file types:
#   - .md, .txt - Markdown/text files (native support)
#   - .pdf - PDF files (requires pdftotext from poppler)
#
# Chunking Strategy:
#   1. Split by headings (# ## ### etc.)
#   2. Further split paragraphs if > 1000 chars
#   3. Keep code blocks intact
#   4. Preserve context with heading hierarchy

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Usage: $0 <file>"
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
    error "File not found: $FILE"
fi

# Get file extension
FILE_EXT="${FILE##*.}"
FILE_EXT="${FILE_EXT,,}"  # lowercase

# Handle PDF files
if [[ "$FILE_EXT" == "pdf" ]]; then
    if ! command -v pdftotext &>/dev/null; then
        error "pdftotext is required for PDF files.

Install with:
  macOS:  brew install poppler
  Ubuntu: apt install poppler-utils

Or extract PDF content manually to .md format."
    fi

    # Create temp file for extracted text
    TEMP_FILE=$(mktemp --suffix=.txt)
    trap "rm -f '$TEMP_FILE'" EXIT

    # Extract text from PDF (with layout preservation)
    if ! pdftotext -layout "$FILE" "$TEMP_FILE" 2>/dev/null; then
        error "Failed to extract text from PDF: $FILE"
    fi

    # Check if extraction produced content
    if [[ ! -s "$TEMP_FILE" ]]; then
        warn "PDF appears to be empty or image-only: $FILE"
        exit 0
    fi

    # Use extracted text file for processing
    PROCESS_FILE="$TEMP_FILE"
    ORIGINAL_FILE="$FILE"
else
    PROCESS_FILE="$FILE"
    ORIGINAL_FILE="$FILE"
fi

# Python script for chunking (more reliable than pure bash)
python3 - "$PROCESS_FILE" "$ORIGINAL_FILE" "$FILE_EXT" << 'PYTHON_SCRIPT'
import sys
import json
import hashlib
import re
from pathlib import Path

def get_file_hash(filepath):
    """Calculate SHA256 hash of file contents."""
    with open(filepath, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

def chunk_text(content, is_pdf=False):
    """
    Chunk text content by sections.

    Strategy:
    - Split on headings (# ## ### etc.) for markdown
    - Split by double newlines for plain text/PDF
    - Split long paragraphs (> 1000 chars)
    - Each chunk includes its heading context
    """
    chunks = []
    current_headers = {}  # Track heading hierarchy

    # Pattern to match markdown headings
    heading_pattern = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)

    # For PDFs, also detect common heading patterns (ALL CAPS, numbered sections)
    if is_pdf:
        # Add PDF-specific heading detection
        pdf_heading_pattern = re.compile(r'^([A-Z][A-Z\s]{2,50})$|^(\d+\.[\d.]*\s+.+)$', re.MULTILINE)

    # Split content into sections by headings
    sections = re.split(r'(?=^#{1,6}\s+)', content, flags=re.MULTILINE)

    # If no markdown headings found (common in PDFs), split by paragraphs
    if len(sections) <= 1:
        sections = re.split(r'\n\s*\n', content)

    chunk_index = 0

    for section in sections:
        if not section.strip():
            continue

        # Check if section starts with a heading
        heading_match = heading_pattern.match(section)

        if heading_match:
            level = len(heading_match.group(1))
            heading_text = heading_match.group(2).strip()

            # Update heading hierarchy
            current_headers[level] = heading_text
            # Clear lower-level headings
            for l in list(current_headers.keys()):
                if l > level:
                    del current_headers[l]

            # Get content after heading
            content_after_heading = section[heading_match.end():].strip()
            chunk_type = 'heading'
        else:
            content_after_heading = section.strip()
            chunk_type = 'paragraph' if not is_pdf else 'pdf_section'

        # Build context from heading hierarchy
        context = ' > '.join([current_headers[l] for l in sorted(current_headers.keys())])

        # Split long content into smaller chunks
        if len(content_after_heading) > 1500:
            # Split by paragraphs
            paragraphs = re.split(r'\n\s*\n', content_after_heading)
            for para in paragraphs:
                if para.strip():
                    # Further split if still too long
                    if len(para) > 1500:
                        # Split by sentences
                        sentences = re.split(r'(?<=[.!?])\s+', para)
                        current_chunk = ""
                        for sent in sentences:
                            if len(current_chunk) + len(sent) < 1200:
                                current_chunk += sent + " "
                            else:
                                if current_chunk.strip():
                                    chunks.append({
                                        'index': chunk_index,
                                        'type': chunk_type,
                                        'context': context,
                                        'text': current_chunk.strip()
                                    })
                                    chunk_index += 1
                                current_chunk = sent + " "
                        if current_chunk.strip():
                            chunks.append({
                                'index': chunk_index,
                                'type': chunk_type,
                                'context': context,
                                'text': current_chunk.strip()
                            })
                            chunk_index += 1
                    else:
                        chunks.append({
                            'index': chunk_index,
                            'type': chunk_type,
                            'context': context,
                            'text': para.strip()
                        })
                        chunk_index += 1
        elif content_after_heading:
            chunks.append({
                'index': chunk_index,
                'type': chunk_type,
                'context': context,
                'text': content_after_heading
            })
            chunk_index += 1

    return chunks

def main():
    process_filepath = sys.argv[1]  # File to read (may be temp file for PDFs)
    original_filepath = sys.argv[2]  # Original file path (for metadata)
    file_ext = sys.argv[3]  # File extension

    path = Path(original_filepath)
    is_pdf = file_ext == 'pdf'

    with open(process_filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    # Use original file for hash (not temp extracted text)
    file_hash = get_file_hash(original_filepath)
    chunks = chunk_text(content, is_pdf=is_pdf)

    # Output as JSON lines
    for chunk in chunks:
        output = {
            'source_path': str(path),
            'source_hash': file_hash,
            'chunk_index': chunk['index'],
            'chunk_type': chunk['type'],
            'chunk_text': chunk['text'],
            'metadata': {
                'context': chunk['context'],
                'file_type': file_ext
            }
        }
        print(json.dumps(output))

if __name__ == '__main__':
    main()
PYTHON_SCRIPT
