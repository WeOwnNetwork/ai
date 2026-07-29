#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

// Keys come from the container env (Infisical) only — never from the plugins
// JSON on the bind mount (that file is backed up and easy to commit).
const apiKey = process.env.OPENROUTER_API_KEY || process.env.EMBED_API_KEY || '';

if (!apiKey || apiKey.length < 30) {
  console.error(
    'rag-memory MCP: OPENROUTER_API_KEY is missing or too short. ' +
      'Set it via Infisical (process env); do not put keys in plugins JSON.'
  );
  process.exit(1);
}

// Pin Python 3.12 + mcp==1.6.0: lancedb-mcp 0.1.3 crashes on mcp>=1.8
// with TypeError: issubclass() arg 1 must be a class during tool registration.
//
// KB data lives under storage/rag-memory (not storage/mcp/) so the mcp/**
// git allowlist cannot accidentally pick up the LanceDB files.
spawnMcp(
  'uvx',
  ['--python', '3.12', '--with', 'mcp==1.6.0', 'lancedb-mcp'],
  {
    EMBED_API_BASE:
      process.env.EMBED_API_BASE ||
      process.env.EMBEDDING_BASE_PATH ||
      'https://openrouter.ai/api/v1',
    EMBED_MODEL:
      process.env.EMBED_MODEL ||
      process.env.EMBEDDING_MODEL_PREF ||
      'perplexity/pplx-embed-v1-4b',
    EMBED_API_KEY: apiKey,
    OPENROUTER_API_KEY: apiKey,
    EMBED_DIM: process.env.EMBED_DIM || '2560',
    KB_STORAGE_PATH:
      process.env.KB_STORAGE_PATH || '/app/server/storage/rag-memory',
  }
);
