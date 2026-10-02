#!/usr/bin/env node
'use strict';

const { spawn } = require('child_process');

// weown-fleet#97: an MCP child is third-party code fetched at runtime, so it
// gets only what a process needs to run (paths, locale, CA and proxy, the
// uv/npm caches) plus the variables its wrapper names in envPatch. Never the
// whole AnythingLLM env, which holds the tenant's LLM key, JWT secret and
// store credentials. A server that needs a key must pass it explicitly.
const ENV_KEYS = new Set([
  'PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'TERM', 'LANG', 'LANGUAGE', 'TZ',
  'TMPDIR', 'TMP', 'TEMP', 'NODE_ENV', 'NODE_EXTRA_CA_CERTS',
  'SSL_CERT_FILE', 'SSL_CERT_DIR', 'REQUESTS_CA_BUNDLE',
  'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy',
]);
const ENV_PREFIXES = ['LC_', 'XDG_', 'UV_', 'NPM_CONFIG_', 'npm_config_'];

function childEnv(envPatch = {}, parent = process.env) {
  const env = {};
  for (const [k, v] of Object.entries(parent)) {
    if (ENV_KEYS.has(k) || ENV_PREFIXES.some((p) => k.startsWith(p))) env[k] = v;
  }
  return { ...env, ...envPatch };
}

function spawnMcp(command, args, envPatch = {}) {
  const child = spawn(command, args, {
    stdio: 'inherit',
    env: childEnv(envPatch),
  });

  child.on('error', (err) => {
    console.error(`Failed to start MCP backend (${command}):`, err.message);
    process.exit(1);
  });

  child.on('exit', (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    else process.exit(code ?? 1);
  });
}

module.exports = { spawnMcp, childEnv };
