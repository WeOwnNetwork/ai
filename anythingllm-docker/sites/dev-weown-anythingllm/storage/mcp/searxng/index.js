#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

const baseUrl = (
  process.env.SEARXNG_BASE_URL ||
  process.env.SEARXNG_URL ||
  ''
).replace(/\/$/, '');

spawnMcp('uvx', ['mcp-searxng'], { SEARXNG_URL: baseUrl });
