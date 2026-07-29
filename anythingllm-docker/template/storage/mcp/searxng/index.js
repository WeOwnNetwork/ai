#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

const baseUrl = (
  process.env.SEARXNG_BASE_URL ||
  process.env.SEARXNG_URL ||
  ''
)
  .trim()
  .replace(/\/+$/, '');

if (!baseUrl) {
  console.error(
    'searxng MCP: SEARXNG_BASE_URL (or SEARXNG_URL) is required and must be non-empty'
  );
  process.exit(1);
}

// Pin Python 3.12 + mcp SDK — unpinned uvx pulls a newer mcp that breaks mcp-searxng.
spawnMcp(
  'uvx',
  ['--python', '3.12', '--with', 'mcp==1.9.4', '--from', 'mcp-searxng', 'mcp-searxng'],
  { SEARXNG_URL: baseUrl }
);
