// Test the stripper the way the network actually delivers it: in arbitrary
// pieces, with tags straddling chunk boundaries. Run: node test.js
'use strict';
const assert = require('assert');
const { makeStripper, filterDataLine } = require('./server.js');

const run = (pieces) => {
  const s = makeStripper();
  return pieces.map((p) => s.feed(p)).join('') + s.flush();
};

// 1. whole block in one piece
assert.strictEqual(run(['<think>secret</think>Hello']), 'Hello');

// 2. the boundary case this exists for: tag split across chunks
assert.strictEqual(run(['<thi', 'nk>sec', 'ret</thi', 'nk>', 'Hello']), 'Hello');

// 3. one character at a time — the worst case a stream can produce
assert.strictEqual(run('<think>private reasoning</think>Answer.'.split('')), 'Answer.');

// 4. leading whitespace left by a stripped block is trimmed
assert.strictEqual(run(['<think>x</think>', '\n\n', 'Answer.']), 'Answer.');

// 5. text with no reasoning block is untouched, byte for byte
assert.strictEqual(run(['Plain ', 'answer ', 'text.']), 'Plain answer text.');

// 6. a lone "<" or partial tag that never completes must NOT be eaten
assert.strictEqual(run(['a < b']), 'a < b');
assert.strictEqual(run(['ends with <thi']), 'ends with <thi');

// 7. multiple blocks
assert.strictEqual(run(['<think>a</think>One. <think>b</think>Two.']), 'One. Two.');

// 8. alternate tag names
assert.strictEqual(run(['<reasoning>r</reasoning>Ans']), 'Ans');

// 9. an unterminated block is discarded rather than leaked (fail closed)
assert.strictEqual(run(['<think>never closed']), '');

// 10. SSE line rewriting preserves every other field
{
  const s = makeStripper();
  const out = filterDataLine('data: {"id":"x","type":"textResponseChunk","textResponse":"<think>z</think>Hi","close":false,"error":false}', s);
  const o = JSON.parse(out.slice(5));
  assert.strictEqual(o.textResponse, 'Hi');
  assert.strictEqual(o.id, 'x');
  assert.strictEqual(o.close, false);
  assert.strictEqual(o.error, false);
}

// 11. a non-JSON or non-data line passes through untouched
{
  const s = makeStripper();
  assert.strictEqual(filterDataLine('event: ping', s), 'event: ping');
  assert.strictEqual(filterDataLine('data: not json', s), 'data: not json');
}

console.log('embed-filter: all 11 assertions passed');
