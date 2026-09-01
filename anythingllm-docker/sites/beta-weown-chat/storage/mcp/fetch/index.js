#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

spawnMcp('uvx', ['--python', '3.12', '--with', 'mcp==1.9.4', 'mcp-server-fetch']);
