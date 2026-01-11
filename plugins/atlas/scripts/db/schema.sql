-- Atlas Vector Database Schema
-- Requires PostgreSQL with pgvector extension
--
-- Usage:
--   psql $DATABASE_URL -f scripts/db/schema.sql
--
-- Or run via Atlas:
--   ./scripts/db/migrate.sh

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Embeddings table for storing document chunks
CREATE TABLE IF NOT EXISTS atlas_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Source document information
    source_repo VARCHAR(255) NOT NULL,       -- e.g., "knowledge" or repo name
    source_path VARCHAR(1024) NOT NULL,      -- File path within the repo
    source_hash VARCHAR(64) NOT NULL,        -- SHA256 of source file for change detection

    -- Chunk information
    chunk_index INTEGER NOT NULL,            -- Position within the document
    chunk_type VARCHAR(50) NOT NULL,         -- 'heading', 'paragraph', 'code', etc.
    chunk_text TEXT NOT NULL,                -- The actual text content

    -- Embedding vector (1536 dimensions for OpenAI ada-002)
    embedding vector(1536) NOT NULL,

    -- Metadata
    metadata JSONB DEFAULT '{}',             -- Flexible metadata storage
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Unique constraint to prevent duplicates
    UNIQUE (source_repo, source_path, chunk_index)
);

-- Index for fast vector similarity search
CREATE INDEX IF NOT EXISTS idx_atlas_embeddings_vector
    ON atlas_embeddings
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Index for filtering by source
CREATE INDEX IF NOT EXISTS idx_atlas_embeddings_source
    ON atlas_embeddings (source_repo, source_path);

-- Index for finding stale embeddings
CREATE INDEX IF NOT EXISTS idx_atlas_embeddings_hash
    ON atlas_embeddings (source_hash);

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_atlas_embeddings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
DROP TRIGGER IF EXISTS trigger_atlas_embeddings_updated_at ON atlas_embeddings;
CREATE TRIGGER trigger_atlas_embeddings_updated_at
    BEFORE UPDATE ON atlas_embeddings
    FOR EACH ROW
    EXECUTE FUNCTION update_atlas_embeddings_updated_at();

-- View for quick stats
CREATE OR REPLACE VIEW atlas_embedding_stats AS
SELECT
    source_repo,
    COUNT(DISTINCT source_path) as document_count,
    COUNT(*) as chunk_count,
    MIN(created_at) as oldest_embedding,
    MAX(updated_at) as newest_embedding
FROM atlas_embeddings
GROUP BY source_repo;

-- Comment on table
COMMENT ON TABLE atlas_embeddings IS 'Vector embeddings for Atlas semantic search over company knowledge';
