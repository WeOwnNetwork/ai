#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

// No dedicated document-summarizer MCP package exists; use the knowledge-graph
// memory server so the stdio transport stays alive for Agent Skills boot.
spawnMcp('npx', ['-y', '@modelcontextprotocol/server-memory']);
