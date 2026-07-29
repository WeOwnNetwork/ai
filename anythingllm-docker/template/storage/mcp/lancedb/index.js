#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

function loadEnvFromPlugin() {
  try {
    const pluginPath = '/app/server/storage/plugins/anythingllm_mcp_servers.json';
    const data = JSON.parse(fs.readFileSync(pluginPath, 'utf8'));
    return (((data || {}).mcpServers || {})['rag-memory'] || {}).env || {};
  } catch (_) {
    return {};
  }
}

const pluginEnv = loadEnvFromPlugin();
const apiKey =
  process.env.OPENROUTER_API_KEY ||
  process.env.EMBED_API_KEY ||
  pluginEnv.OPENROUTER_API_KEY ||
  pluginEnv.EMBED_API_KEY ||
  '';

if (!apiKey) {
  console.error(
    'rag-memory MCP: OPENROUTER_API_KEY is required for lancedb-mcp embeddings'
  );
  process.exit(1);
}

if (String(apiKey).length < 30) {
  console.error(
    'rag-memory MCP: OPENROUTER_API_KEY looks too short (len=' +
      String(apiKey).length +
      '). Use Infisical OPENROUTER_API_KEY or a Secure Handoff into plugin env.'
  );
  process.exit(1);
}

// Pin Python 3.12 + mcp==1.6.0: lancedb-mcp 0.1.3 crashes on mcp>=1.8
// with TypeError: issubclass() arg 1 must be a class during tool registration.
spawnMcp(
  'uvx',
  ['--python', '3.12', '--with', 'mcp==1.6.0', 'lancedb-mcp'],
  {
    EMBED_API_BASE:
      process.env.EMBED_API_BASE ||
      pluginEnv.EMBED_API_BASE ||
      process.env.EMBEDDING_BASE_PATH ||
      'https://openrouter.ai/api/v1',
    EMBED_MODEL:
      process.env.EMBED_MODEL ||
      pluginEnv.EMBED_MODEL ||
      process.env.EMBEDDING_MODEL_PREF ||
      'perplexity/pplx-embed-v1-4b',
    EMBED_API_KEY: apiKey,
    OPENROUTER_API_KEY: apiKey,
    EMBED_DIM: process.env.EMBED_DIM || pluginEnv.EMBED_DIM || '2560',
    KB_STORAGE_PATH:
      process.env.KB_STORAGE_PATH ||
      '/app/server/storage/mcp/lancedb/kb_data',
  }
);
