#!/usr/bin/env node
'use strict';

/**
 * Document Summarizer MCP for AnythingLLM.
 *
 * Lists and returns workspace document text from STORAGE_DIR/documents so the
 * agent (or optional OpenRouter call) can summarize. Replaces the prior stub
 * that spawned @modelcontextprotocol/server-memory (knowledge-graph tools),
 * which made "document-summarizer" unusable for document Q&A.
 *
 * No secrets are logged. OPENROUTER_API_KEY is optional: when set,
 * summarize_document may call OpenRouter; otherwise it returns document text
 * for the parent agent LLM to summarize.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const readline = require('readline');

const STORAGE_DIR = process.env.STORAGE_DIR || '/app/server/storage';
const DOCUMENTS_DIR =
  process.env.DOCUMENTS_DIR || path.join(STORAGE_DIR, 'documents');
const TIMEOUT_MS = Number(
  process.env.OPENROUTER_TIMEOUT_MS ||
    process.env.LLM_STREAM_TIMEOUT ||
    30000
);
const MODEL =
  process.env.OPENROUTER_MODEL_PREF ||
  process.env.SUMMARIZER_MODEL ||
  'deepseek/deepseek-v4-flash';
const MAX_LIST = Number(process.env.SUMMARIZER_MAX_LIST || 100);
const DEFAULT_VIEW_CHARS = Number(process.env.SUMMARIZER_MAX_CHARS || 24000);

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function textResult(text, isError = false) {
  return { content: [{ type: 'text', text }], isError };
}

function walkJsonFiles(dir, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) walkJsonFiles(full, acc);
    else if (ent.isFile() && ent.name.endsWith('.json')) acc.push(full);
  }
  return acc;
}

function loadDoc(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const data = JSON.parse(raw);
  const rel = path.relative(DOCUMENTS_DIR, filePath).replace(/\\/g, '/');
  return {
    path: rel,
    id: data.id || '',
    title: data.title || data.docSource || path.basename(filePath),
    description: data.description || '',
    docSource: data.docSource || '',
    wordCount: data.wordCount || 0,
    pageContent: String(data.pageContent || data.content || data.text || ''),
  };
}

function findDocs(query) {
  const files = walkJsonFiles(DOCUMENTS_DIR);
  const docs = [];
  for (const f of files) {
    try {
      docs.push(loadDoc(f));
    } catch {
      // skip unreadable / non-AnythingLLM JSON
    }
  }
  if (!query) return docs;
  const q = String(query).toLowerCase();
  return docs.filter(
    (d) =>
      d.title.toLowerCase().includes(q) ||
      d.path.toLowerCase().includes(q) ||
      d.docSource.toLowerCase().includes(q) ||
      d.description.toLowerCase().includes(q)
  );
}

function resolveDoc(pathOrTitle) {
  const needle = String(pathOrTitle || '').trim();
  if (!needle) return null;
  const docs = findDocs('');
  const exactPath = docs.find((d) => d.path === needle);
  if (exactPath) return exactPath;
  const byTitle = docs.find((d) => d.title === needle);
  if (byTitle) return byTitle;
  const lower = needle.toLowerCase();
  return (
    docs.find((d) => d.path.toLowerCase().includes(lower)) ||
    docs.find((d) => d.title.toLowerCase().includes(lower)) ||
    null
  );
}

function openRouterChat(system, user) {
  const apiKey = process.env.OPENROUTER_API_KEY || '';
  if (!apiKey) {
    return Promise.reject(new Error('OPENROUTER_API_KEY unset'));
  }
  const body = JSON.stringify({
    model: MODEL,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user },
    ],
  });
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'openrouter.ai',
        path: '/api/v1/chat/completions',
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
        timeout: TIMEOUT_MS,
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          if (res.statusCode < 200 || res.statusCode >= 300) {
            reject(
              new Error(
                `OpenRouter HTTP ${res.statusCode}: ${data.slice(0, 200)}`
              )
            );
            return;
          }
          try {
            const parsed = JSON.parse(data);
            const text =
              parsed.choices?.[0]?.message?.content ||
              JSON.stringify(parsed).slice(0, 500);
            resolve(text);
          } catch (err) {
            reject(err);
          }
        });
      }
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error(`OpenRouter timeout after ${TIMEOUT_MS}ms`));
    });
    req.write(body);
    req.end();
  });
}

const TOOLS = [
  {
    name: 'list_documents',
    description:
      'List workspace documents currently stored/embedded under AnythingLLM storage/documents. Use before summarizing so you know exact titles/paths.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Optional filter matched against title/path/source',
        },
        limit: {
          type: 'number',
          description: `Max results (default 20, max ${MAX_LIST})`,
        },
      },
    },
  },
  {
    name: 'view_document',
    description:
      'Return the text content of a workspace document by path or title so it can be read or summarized.',
    inputSchema: {
      type: 'object',
      properties: {
        path_or_title: {
          type: 'string',
          description: 'Document relative path or title from list_documents',
        },
        max_chars: {
          type: 'number',
          description: `Truncate page content to this many characters (default ${DEFAULT_VIEW_CHARS})`,
        },
      },
      required: ['path_or_title'],
    },
  },
  {
    name: 'summarize_document',
    description:
      'Summarize a workspace document. Prefer this when the user asks to summarize or overview a file. Returns a summary when OPENROUTER_API_KEY is available; otherwise returns document text for you to summarize in your reply.',
    inputSchema: {
      type: 'object',
      properties: {
        path_or_title: {
          type: 'string',
          description: 'Document relative path or title from list_documents',
        },
        focus: {
          type: 'string',
          description: 'Optional focus area for the summary',
        },
        max_chars: {
          type: 'number',
          description: 'Max characters of source text to use',
        },
      },
      required: ['path_or_title'],
    },
  },
];

async function callTool(name, args = {}) {
  if (name === 'list_documents') {
    const limit = Math.min(
      Math.max(Number(args.limit) || 20, 1),
      MAX_LIST
    );
    const docs = findDocs(args.query).slice(0, limit);
    if (!docs.length) {
      return textResult(
        `No documents found under ${DOCUMENTS_DIR}` +
          (args.query ? ` matching "${args.query}"` : '')
      );
    }
    const lines = docs.map(
      (d, i) =>
        `${i + 1}. title=${d.title} | path=${d.path} | words=${d.wordCount}`
    );
    return textResult(
      `Found ${docs.length} document(s):\n` + lines.join('\n')
    );
  }

  if (name === 'view_document' || name === 'summarize_document') {
    const doc = resolveDoc(args.path_or_title);
    if (!doc) {
      return textResult(
        `Document not found: ${args.path_or_title}. Call list_documents first.`,
        true
      );
    }
    const maxChars = Number(args.max_chars) || DEFAULT_VIEW_CHARS;
    const content = doc.pageContent.slice(0, maxChars);
    const truncated = doc.pageContent.length > content.length;

    if (name === 'view_document') {
      return textResult(
        [
          `Title: ${doc.title}`,
          `Path: ${doc.path}`,
          `Words: ${doc.wordCount}`,
          truncated
            ? `Content (truncated to ${maxChars} chars):`
            : 'Content:',
          content || '(empty)',
        ].join('\n')
      );
    }

    if (process.env.OPENROUTER_API_KEY) {
      try {
        const focus = args.focus ? ` Focus on: ${args.focus}.` : '';
        const summary = await openRouterChat(
          'You summarize workplace documents clearly and concisely. Use short sections and bullet points when helpful. Do not invent facts.',
          `Summarize this document titled "${doc.title}".${focus}\n\n${content}`
        );
        return textResult(
          `Summary of "${doc.title}" (${doc.path}):\n\n${summary}`
        );
      } catch (err) {
        return textResult(
          [
            `OpenRouter summarization failed (${err.message}).`,
            `Document text for you to summarize follows.`,
            `Title: ${doc.title}`,
            `Path: ${doc.path}`,
            truncated
              ? `Content (truncated to ${maxChars} chars):`
              : 'Content:',
            content || '(empty)',
          ].join('\n')
        );
      }
    }

    return textResult(
      [
        `OPENROUTER_API_KEY not available to MCP; returning document text for you (the agent) to summarize.`,
        `Title: ${doc.title}`,
        `Path: ${doc.path}`,
        `Words: ${doc.wordCount}`,
        args.focus ? `Requested focus: ${args.focus}` : null,
        truncated ? `Content (truncated to ${maxChars} chars):` : 'Content:',
        content || '(empty)',
      ]
        .filter(Boolean)
        .join('\n')
    );
  }

  return textResult(`Unknown tool: ${name}`, true);
}

async function handle(msg) {
  if (!msg || typeof msg !== 'object') return;
  const { id, method, params } = msg;

  if (method === 'initialize') {
    send({
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: params?.protocolVersion || '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: {
          name: 'document-summarizer',
          version: '1.0.0',
        },
      },
    });
    return;
  }

  if (method === 'notifications/initialized' || method === 'initialized') {
    return;
  }

  if (method === 'tools/list') {
    send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    return;
  }

  if (method === 'tools/call') {
    try {
      const result = await callTool(params?.name, params?.arguments || {});
      send({ jsonrpc: '2.0', id, result });
    } catch (err) {
      send({
        jsonrpc: '2.0',
        id,
        result: textResult(String(err.message || err), true),
      });
    }
    return;
  }

  if (method === 'ping') {
    send({ jsonrpc: '2.0', id, result: {} });
    return;
  }

  if (id !== undefined && id !== null) {
    send({
      jsonrpc: '2.0',
      id,
      error: { code: -32601, message: `Method not found: ${method}` },
    });
  }
}

const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let msg;
  try {
    msg = JSON.parse(trimmed);
  } catch (err) {
    console.error('document-summarizer: invalid JSON on stdin:', err.message);
    return;
  }
  Promise.resolve(handle(msg)).catch((err) => {
    console.error('document-summarizer:', err.message);
  });
});

process.stdin.on('end', () => process.exit(0));
