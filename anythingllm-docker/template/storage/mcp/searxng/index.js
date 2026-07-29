#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

const baseUrl = (
  process.env.SEARXNG_BASE_URL ||
  process.env.SEARXNG_URL ||
  ''
).replace(/\/$/, '');

// Pin Python 3.12 + mcp SDK — unpinned uvx pulls a newer mcp that breaks mcp-searxng.
spawnMcp(
  'uvx',
  ['--python', '3.12', '--with', 'mcp==1.9.4', '--from', 'mcp-searxng', 'mcp-searxng'],
  { SEARXNG_URL: baseUrl }
);
