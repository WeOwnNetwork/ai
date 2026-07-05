#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

spawnMcp('npx', ['-y', '@modelcontextprotocol/server-puppeteer']);
