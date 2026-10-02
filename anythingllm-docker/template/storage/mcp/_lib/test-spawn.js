// node test-spawn.js — weown-fleet#97: an MCP child gets an env ALLOWLIST plus
// its own patch, never the whole secret-bearing AnythingLLM container env.
// Runs spawnMcp for real (as the wrappers do) on a child that reports its env.
'use strict';
const assert = require('assert');
const path = require('path');
const { spawnSync } = require('child_process');

const parent = {
  PATH: process.env.PATH, HOME: '/app', LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8', TZ: 'UTC',
  UV_CACHE_DIR: '/app/.uv', npm_config_cache: '/app/.npm', HTTPS_PROXY: 'http://proxy:3128',
  NODE_EXTRA_CA_CERTS: '/etc/ca.pem',
  // container secrets an MCP child must never see
  OPENROUTER_API_KEY: 'sk-or-test', JWT_SECRET: 'jwt-test', SIG_KEY: 'k', SIG_SALT: 's',
  INFISICAL_TOKEN: 't', BAO_TOKEN: 't', ADMIN_EMAIL: 'a@example.test', DATABASE_CONNECTION_STRING: 'x',
  // registry credentials that live under the uv/npm prefixes
  UV_PUBLISH_TOKEN: 'pypi-x', UV_INDEX_PRIVATE_PASSWORD: 'p', UV_INDEX_URL: 'https://u:p@pypi.example.test/simple',
  NPM_CONFIG__AUTH: 'x', 'npm_config_//registry.npmjs.org/:_authToken': 'npm_x', UV_TOOL_DIR: '/app/.uv-tools',
};
const childEnvOf = (patch) => {
  const wrapper = `require(${JSON.stringify(path.join(__dirname, 'spawn.js'))}).spawnMcp(process.execPath,
    ['-e', 'process.stdout.write(JSON.stringify(process.env))'], ${JSON.stringify(patch)});`;
  const r = spawnSync(process.execPath, ['-e', wrapper], { env: parent, encoding: 'utf8' });
  assert.strictEqual(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
};

const env = childEnvOf({ SEARXNG_URL: 'http://searxng:8080' });
for (const k of ['PATH', 'HOME', 'LANG', 'LC_ALL', 'TZ', 'UV_CACHE_DIR', 'UV_TOOL_DIR', 'npm_config_cache', 'HTTPS_PROXY', 'NODE_EXTRA_CA_CERTS'])
  assert.strictEqual(env[k], parent[k], `${k} should pass through`);
assert.strictEqual(env.SEARXNG_URL, 'http://searxng:8080', 'the explicit patch is applied');
const leaked = ['OPENROUTER_API_KEY', 'JWT_SECRET', 'SIG_KEY', 'SIG_SALT', 'INFISICAL_TOKEN', 'BAO_TOKEN',
  'ADMIN_EMAIL', 'DATABASE_CONNECTION_STRING', 'UV_PUBLISH_TOKEN', 'UV_INDEX_PRIVATE_PASSWORD', 'UV_INDEX_URL',
  'NPM_CONFIG__AUTH', 'npm_config_//registry.npmjs.org/:_authToken'].filter((k) => k in env);
assert.deepStrictEqual(leaked, [], `container secrets reached the MCP child: ${leaked.join(', ')}`);

// a server that needs a key (lancedb) gets it only by naming it in its patch
assert.strictEqual(childEnvOf({ EMBED_API_KEY: 'sk-or-test' }).EMBED_API_KEY, 'sk-or-test');
console.log('test-spawn: ok');
