#!/usr/bin/env bash
#
# Atlas Document Chunking Script
#
# Usage:
#   ./scripts/db/chunk.sh <file>
#
# Chunks a markdown document into sections suitable for embedding.
# Output is JSON lines format with chunk metadata.
#
# Chunking Strategy:
#   1. Split by headings (# ## ### etc.)
#   2. Further split paragraphs if > 1000 chars
#   3. Keep code blocks intact
#   4. Preserve context with heading hierarchy

set -euo pipefail

# Colors for output
RED='\033[0;31m'
NC='\033[0m'

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Usage: $0 <file>"
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
    error "File not found: $FILE"
fi

# Python script for chunking (more reliable than pure bash)
python3 - "$FILE" << 'PYTHON_SCRIPT'
import sys
import json
import hashlib
import re
from pathlib import Path

def get_file_hash(filepath):
    """Calculate SHA256 hash of file contents."""
    with open(filepath, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

def chunk_markdown(content):
    """
    Chunk markdown content by sections.

    Strategy:
    - Split on headings (# ## ### etc.)
    - Keep code blocks intact
    - Split long paragraphs (> 1000 chars)
    - Each chunk includes its heading context
    """
    chunks = []
    current_headers = {}  # Track heading hierarchy

    # Pattern to match markdown headings
    heading_pattern = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)

    # Split content into sections by headings
    sections = re.split(r'(?=^#{1,6}\s+)', content, flags=re.MULTILINE)

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
            chunk_type = 'paragraph'

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
    filepath = sys.argv[1]
    path = Path(filepath)

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    file_hash = get_file_hash(filepath)
    chunks = chunk_markdown(content)

    # Output as JSON lines
    for chunk in chunks:
        output = {
            'source_path': str(path),
            'source_hash': file_hash,
            'chunk_index': chunk['index'],
            'chunk_type': chunk['type'],
            'chunk_text': chunk['text'],
            'metadata': {
                'context': chunk['context']
            }
        }
        print(json.dumps(output))

if __name__ == '__main__':
    main()
PYTHON_SCRIPT
