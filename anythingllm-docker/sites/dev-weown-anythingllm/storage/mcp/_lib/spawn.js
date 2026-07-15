'use strict';

const { spawn } = require('child_process');

function spawnMcp(command, args, envPatch = {}) {
  const child = spawn(command, args, {
    stdio: 'inherit',
    env: { ...process.env, ...envPatch },
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

module.exports = { spawnMcp };
