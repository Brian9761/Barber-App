// The demo version's end-to-end server: dist-demo/ as a static site, hosted the
// way its own vercel.json tells Vercel to (files first, then its rewrites: each
// legal page's plain HTML, Business's page, and the site's page for every other
// path but /api/ and /assets/, with the headers it sets), and nothing else.
// There's no API: the demo answers in the browser.
//
//   npm run build:demo && npm run serve:demo     (then open http://127.0.0.1:4174)
//
// Playwright starts it by itself (playwright.demo.config.ts). E2E_DEMO_PORT
// changes the port.
//
// Test plumbing under /__e2e/ (never part of the real site): the requests that
// reached /api (the demo must never make one), a new version of the service
// worker, for the "A new version is ready" bar, and the demo retired: the retired
// site (`npm run build:retired`, in dist-retired/) deployed at its address instead.

import { existsSync, readFileSync, statSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rewriteFor, rewritesOf, sourcePattern } from '../tools/hosting.js';

const PORT = Number(process.env.E2E_DEMO_PORT) || 4174;
const ORIGIN = `http://127.0.0.1:${PORT}`;
const DEMO_ROOT = resolve(fileURLToPath(new URL('../dist-demo/', import.meta.url)));
const RETIRED_ROOT = resolve(fileURLToPath(new URL('../dist-retired/', import.meta.url)));

if (!existsSync(join(DEMO_ROOT, 'index.html')) || !existsSync(join(DEMO_ROOT, 'vercel.json'))) {
  console.error(`No demo build in ${DEMO_ROOT}. Run \`npm run build:demo\` in server/web first.`);
  process.exit(1);
}

interface HostingSettings {
  headers?: { source: string; headers: { key: string; value: string }[] }[];
}

interface Site {
  root: string;
  rewrites: { pattern: RegExp; destination: string }[];
  headerRules: { pattern: RegExp; headers: { key: string; value: string }[] }[];
}

/** A folder deployed as its vercel.json says (its sources read as Vercel reads them: tools/hosting.ts). */
function site(root: string): Site {
  const text = readFileSync(join(root, 'vercel.json'), 'utf8');
  const hosting = JSON.parse(text) as HostingSettings;
  return {
    root,
    rewrites: rewritesOf(text),
    headerRules: (hosting.headers ?? []).map((rule) => ({ pattern: sourcePattern(rule.source), headers: rule.headers })),
  };
}

const demo = site(DEMO_ROOT);
/** What's deployed now: the demo, or (with /__e2e/retire) the retired site in its place. */
let current = demo;

const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
};

/** The headers vercel.json sets for this path: every rule that matches, in order. */
function headersFor(pathname: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const rule of current.headerRules) {
    if (!rule.pattern.test(pathname)) continue;
    for (const { key, value } of rule.headers) out[key.toLowerCase()] = value;
  }
  return out;
}

/** A file of the build, or null (never outside it, and never the hosting settings). */
function siteFile(pathname: string): string | null {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  const root = current.root;
  const file = normalize(join(root, decoded));
  if (file !== root && !file.startsWith(root + sep)) return null;
  if (file === join(root, 'vercel.json')) return null;
  return existsSync(file) && statSync(file).isFile() ? file : null;
}

// ------------------------------------------------------------ Test plumbing

/** Every request that reached /api: the demo must never make one. */
const apiRequests: string[] = [];
/** Above 0, /sw.js is a new version (a line added at its end), so the browser finds an update. */
let workerVersion = 0;

async function readBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const text = Buffer.concat(chunks).toString('utf8');
  return text ? (JSON.parse(text) as Record<string, unknown>) : {};
}

function send(res: ServerResponse, status: number, body: string | Buffer, headers: Record<string, string>): void {
  res.writeHead(status, headers);
  res.end(body);
}

async function plumbing(req: IncomingMessage, res: ServerResponse, pathname: string): Promise<void> {
  const json = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
  if (pathname === '/__e2e/api-requests' && req.method === 'GET') return send(res, 200, JSON.stringify({ requests: apiRequests }), json);
  if (pathname === '/__e2e/new-version' && req.method === 'POST') {
    const { reset } = await readBody(req);
    workerVersion = reset ? 0 : workerVersion + 1;
    return send(res, 200, JSON.stringify({ version: workerVersion }), json);
  }
  if (pathname === '/__e2e/retire' && req.method === 'POST') {
    const { on } = await readBody(req);
    if (on && !existsSync(join(RETIRED_ROOT, 'vercel.json'))) {
      return send(res, 409, JSON.stringify({ error: 'No retired site: run `DEMO_MOVED_TO=https://izzy-clipz.example npm run build:retired` first' }), json);
    }
    current = on ? site(RETIRED_ROOT) : demo;
    return send(res, 200, JSON.stringify({ retired: Boolean(on) }), json);
  }
  send(res, 404, JSON.stringify({ error: 'No such end-to-end control' }), json);
}

// ------------------------------------------------------------------- Routing

const server = createServer(async (req, res) => {
  try {
    const { pathname } = new URL(req.url ?? '/', ORIGIN);
    if (pathname.startsWith('/__e2e/')) return await plumbing(req, res, pathname);
    if (pathname === '/api' || pathname.startsWith('/api/')) apiRequests.push(`${req.method} ${pathname}`);

    // Files first, then the rewrites (each legal page's plain HTML, Business's page, and the site's
    // page for every other path but /api/ and /assets/), like Vercel.
    let file = siteFile(pathname);
    if (!file) {
      const destination = rewriteFor(current.rewrites, pathname);
      if (destination) file = siteFile(destination);
    }
    const headers = { 'content-type': file ? (TYPES[extname(file)] ?? 'application/octet-stream') : 'text/plain; charset=utf-8', ...headersFor(pathname) };
    if (!file) return send(res, 404, 'Not found', headers);
    let body = readFileSync(file);
    if (pathname === '/sw.js' && workerVersion > 0 && current === demo) {
      body = Buffer.concat([body, Buffer.from(`\n// New version ${workerVersion}, for the end-to-end tests.\n`)]);
    }
    send(res, 200, body, headers);
  } catch (error) {
    console.error(error);
    if (!res.headersSent) send(res, 500, 'The demo server failed.', { 'content-type': 'text/plain; charset=utf-8' });
  }
});

server.listen(PORT, '127.0.0.1', () => console.log(`Izzy Clipz demo on ${ORIGIN}`));

function stop(): void {
  server.close();
  process.exit(0);
}

process.on('SIGINT', stop);
process.on('SIGTERM', stop);
