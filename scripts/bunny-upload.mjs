#!/usr/bin/env node
// Uploads the wire files of the rendered tree (config.json, c/**, p/**) to Bunny storage zone
// sh-ocx-index-edge, which serves index.ocx.sh; every other path there redirects to ocx.sh/catalog/.
// Files whose SHA-256 already matches are skipped. Order keeps the wire consistent for a client
// reading mid-deploy: CAS objects first, then package roots, then c/index.json and config.json.
//
// Usage: BUNNY_EDGE_STORAGE_KEY=... node scripts/bunny-upload.mjs [dist]
// ponytail: no prune. Wire files are append-mostly (CAS is immutable, roots are overwritten); a removed
// package's files stay until deleted by hand.
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';

const ZONE = 'sh-ocx-index-edge';
const HOST = process.env.BUNNY_STORAGE_HOST || 'storage.bunnycdn.com';
const KEY = process.env.BUNNY_EDGE_STORAGE_KEY;
const DIST = process.argv[2] || 'dist';
const PARALLEL = 16;

if (!KEY) throw new Error('BUNNY_EDGE_STORAGE_KEY is empty');
const api = (path) => `https://${HOST}/${ZONE}/${path}`;

async function request(method, path, body) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(api(path), {
      method,
      headers: { AccessKey: KEY, ...(body && { 'Content-Type': 'application/octet-stream' }) },
      body,
      signal: AbortSignal.timeout(30_000),
    }).catch((e) => ({ ok: false, status: 0, text: async () => String(e) }));
    if (res.ok || res.status === 404 || attempt === 3) return res;
    await new Promise((r) => setTimeout(r, 1000 * attempt));
  }
}

async function pool(items, fn) {
  let i = 0;
  await Promise.all(Array.from({ length: PARALLEL }, async () => { while (i < items.length) await fn(items[i++]); }));
}

async function walk(dir) {
  const out = [];
  for (const e of await readdir(dir, { withFileTypes: true, recursive: true }))
    if (e.isFile()) out.push(relative(DIST, join(e.parentPath, e.name)).split('\\').join('/'));
  return out;
}

/** Remote SHA-256 (upper-case hex) per path, for every directory the local tree has. */
async function remoteChecksums(paths) {
  const dirs = [...new Set(paths.map((p) => p.slice(0, p.lastIndexOf('/') + 1)))];
  const sums = new Map();
  await pool(dirs, async (dir) => {
    const res = await request('GET', dir);
    if (res.status === 404) return;
    if (!res.ok) throw new Error(`list /${dir}: HTTP ${res.status} ${await res.text()}`);
    for (const e of await res.json()) if (!e.IsDirectory) sums.set(dir + e.ObjectName, e.Checksum);
  });
  return sums;
}

const isWire = (p) => p === 'config.json' || p.startsWith('c/') || p.startsWith('p/');

function phase(p) {
  if (p === 'config.json' || p === 'c/index.json') return 2;
  return /^p\/[^/]+\/[^/]+\.json$/.test(p) ? 1 : 0;
}

const files = (await walk(DIST)).filter(isWire);
if (!files.includes('config.json')) throw new Error(`${DIST}/config.json missing: run task render:build first`);

const remote = await remoteChecksums(files);
let uploaded = 0;
for (const n of [0, 1, 2]) {
  const group = files.filter((p) => phase(p) === n);
  await pool(group, async (p) => {
    const body = await readFile(join(DIST, p));
    const sum = createHash('sha256').update(body).digest('hex').toUpperCase();
    if (remote.get(p) === sum) return;
    const res = await request('PUT', p, body);
    if (!res.ok) throw new Error(`PUT /${p}: HTTP ${res.status} ${await res.text()}`);
    uploaded++;
  });
}
console.log(`${ZONE}: ${files.length} files, ${uploaded} uploaded, ${files.length - uploaded} unchanged`);
