#!/usr/bin/env node
'use strict';

const path = require('path');
const { spawnMcp } = require(path.join(__dirname, '..', '_lib', 'spawn.js'));

// @modelcontextprotocol/server-puppeteer defaults NPX mode to headless:false
// (needs X/$DISPLAY). DOCKER_CONTAINER=true switches it to headless + --no-sandbox.
const launchOptions = JSON.stringify({
  headless: true,
  executablePath: '/usr/bin/chromium',
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--disable-gpu',
    '--single-process',
    '--no-zygote',
  ],
});

spawnMcp('npx', ['-y', '@modelcontextprotocol/server-puppeteer'], {
  DOCKER_CONTAINER: 'true',
  ALLOW_DANGEROUS: 'true',
  PUPPETEER_EXECUTABLE_PATH: '/usr/bin/chromium',
  PUPPETEER_LAUNCH_OPTIONS: launchOptions,
});
