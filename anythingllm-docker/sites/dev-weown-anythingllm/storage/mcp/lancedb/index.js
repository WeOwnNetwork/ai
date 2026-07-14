#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

const apiKey = process.env.OPENROUTER_API_KEY || process.env.EMBED_API_KEY || '';
if (!apiKey) {
  console.error(
    'rag-memory MCP: OPENROUTER_API_KEY is required for lancedb-mcp embeddings'
  );
  process.exit(1);
}

spawnMcp('uvx', ['lancedb-mcp'], {
  EMBED_API_BASE:
    process.env.EMBED_API_BASE ||
    process.env.EMBEDDING_BASE_PATH ||
    'https://openrouter.ai/api/v1',
  EMBED_MODEL:
    process.env.EMBED_MODEL ||
    process.env.EMBEDDING_MODEL_PREF ||
    'perplexity/pplx-embed-v1-4b',
  EMBED_API_KEY: apiKey,
  EMBED_DIM: process.env.EMBED_DIM || '2560',
  KB_STORAGE_PATH:
    process.env.KB_STORAGE_PATH ||
    '/app/server/storage/mcp/lancedb/kb_data',
});
