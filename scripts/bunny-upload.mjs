#!/usr/bin/env node
// Uploads the wire files of the rendered tree (config.json, c/**, p/**) to Bunny storage zone
// sh-ocx-index-edge, which serves index.ocx.sh; every other path there redirects to ocx.sh/catalog/.
// Files whose SHA-256 already matches are skipped. Order keeps the wire consistent for a client
// reading mid-deploy: CAS objects first, then package roots, then c/index.json and config.json.
//
// Every mutable file this run uploaded is then purged from the pull zone and read back: the edge
// keeps serving its cached copy of an overwritten root until told otherwise, and a purge that
// missed a cache variant looks exactly like one that worked.
//
// Usage: BUNNY_EDGE_STORAGE_KEY=... BUNNY_API_KEY=... node scripts/bunny-upload.mjs [dist]
// ponytail: no prune. Wire files are append-mostly (CAS is immutable, roots are overwritten); a removed
// package's files stay until deleted by hand.
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

const ZONE = 'sh-ocx-index-edge';
const EDGE = 'https://index.ocx.sh';
const HOST = process.env.BUNNY_STORAGE_HOST || 'storage.bunnycdn.com';
const KEY = process.env.BUNNY_EDGE_STORAGE_KEY;
const API_KEY = process.env.BUNNY_API_KEY;
const DIST = process.argv[2] || 'dist';
const PARALLEL = 16;
// Bunny's exact-URL purge bucket holds 120 tokens and refills 5/s; past this, one prefix purge.
const PURGE_MAX = 100;

if (!KEY) throw new Error('BUNNY_EDGE_STORAGE_KEY is empty');
if (!API_KEY) throw new Error('BUNNY_API_KEY is empty');
const api = (path) => `https://${HOST}/${ZONE}/${path}`;
const sha256 = (body) => createHash('sha256').update(body).digest('hex').toUpperCase();

async function request(method, url, key, body) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, {
      method,
      headers: { AccessKey: key, ...(body && { 'Content-Type': 'application/octet-stream' }) },
      body,
      signal: AbortSignal.timeout(30_000),
    }).catch((e) => ({ ok: false, status: 0, text: async () => String(e) }));
    if (res.ok || res.status === 404 || attempt === 3) return res;
    await sleep(1000 * attempt);
  }
}

async function purge(url) {
  const res = await request('POST', `https://api.bunny.net/purge?async=false&url=${encodeURIComponent(url)}`, API_KEY);
  if (!res.ok) throw new Error(`purge ${url}: HTTP ${res.status} ${await res.text()}`);
}

/** Fails unless the edge serves `sum` for `p` to a client that sends no Accept-Encoding, as ocx does. */
async function assertFresh(p, sum) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`${EDGE}/${p}`, {
      headers: { 'Accept-Encoding': 'identity' },
      signal: AbortSignal.timeout(30_000),
    }).catch(() => null);
    if (res?.ok && sha256(Buffer.from(await res.arrayBuffer())) === sum) return;
    if (attempt === 5) throw new Error(`${EDGE}/${p} still serves stale bytes after the purge`);
    await sleep(2000);
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
    const res = await request('GET', api(dir), KEY);
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
const mutable = new Map(); // path -> SHA-256 of every uploaded file a URL can outlive: all but CAS objects
for (const n of [0, 1, 2]) {
  const group = files.filter((p) => phase(p) === n);
  await pool(group, async (p) => {
    const body = await readFile(join(DIST, p));
    const sum = sha256(body);
    if (remote.get(p) === sum) return;
    const res = await request('PUT', api(p), KEY, body);
    if (!res.ok) throw new Error(`PUT /${p}: HTTP ${res.status} ${await res.text()}`);
    uploaded++;
    if (!p.includes('/o/sha256/')) mutable.set(p, sum);
  });
}
console.log(`${ZONE}: ${files.length} files, ${uploaded} uploaded, ${files.length - uploaded} unchanged`);

const stale = [...mutable.keys()];
if (stale.length > PURGE_MAX) await purge(`${EDGE}/*`);
else await pool(stale, (p) => purge(`${EDGE}/${p}`));
// ponytail: a prefix purge reads back only the first PURGE_MAX paths, enough to tell it took.
await pool(stale.slice(0, PURGE_MAX), (p) => assertFresh(p, mutable.get(p)));
console.log(`${EDGE}: ${stale.length} purged, ${Math.min(stale.length, PURGE_MAX)} read back`);
