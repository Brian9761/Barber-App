// The end-to-end tests' server: the real API on PGlite (Postgres in WASM, served
// over the wire protocol by pglite-socket, as in the server's own tests) with the
// migrations and the catalog's barbers, and the built site from ../public, from
// one Node server routed like Vercel: files on disk first, /api to the API, and
// every other path to index.html.
//
//   npm run build && npm run serve:local     (then open http://127.0.0.1:4173)
//
// Playwright starts it by itself (playwright.config.ts). Every start is a new,
// empty database that lives in memory until the server stops. E2E_PORT changes
// the port.
//
// Test plumbing under /__e2e/ (never part of the real server): turn the live
// reviews and no-show protection on and off, and a stand-in for Stripe's card
// page, which sends the browser back to /book/card-return the way the server's
// card return does for the website. There's no Stripe key: nothing leaves this
// machine.

import { existsSync, readFileSync, statSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import type Stripe from 'stripe';
import { createApp } from '../../src/app.js';
import { newManageToken } from '../../src/auth.js';
import { loadCatalog } from '../../src/catalog.js';
import { configFromEnv } from '../../src/config.js';
import { createPool, poolDb } from '../../src/db.js';
import type { Deps, StripeClient } from '../../src/deps.js';
import { migrate, seedBarbers } from '../../src/migrate.js';

const PORT = Number(process.env.E2E_PORT) || 4173;
const ORIGIN = `http://127.0.0.1:${PORT}`;
const PUBLIC_DIR = resolve(fileURLToPath(new URL('../../public/', import.meta.url)));
const FIXTURES = new URL('../../test/fixtures/', import.meta.url);

if (!existsSync(join(PUBLIC_DIR, 'index.html'))) {
  console.error(`No built site in ${PUBLIC_DIR}. Run \`npm run build\` in server/web first.`);
  process.exit(1);
}

// ------------------------------------------------------------------ Database

const db = await PGlite.create({ extensions: { btree_gist } });
const socket = new PGLiteSocketServer({ db, host: '127.0.0.1', port: 0, maxConnections: 4 });
await socket.start();
// PGlite has one session, so the pool has one connection and requests queue for it.
const pool = createPool(`postgres://postgres@${socket.getServerConn()}/postgres`, { max: 1 });
const catalog = loadCatalog();
{
  const client = await pool.connect();
  try {
    await migrate(client);
    await seedBarbers(client, catalog);
  } finally {
    client.release();
  }
}

// -------------------------------------------------------- A stand-in for Stripe

const notHere = async (): Promise<never> => {
  throw new Error('Not used in the end-to-end tests');
};

/** Just the card-saving calls (Customers and Checkout in setup mode), answered like Stripe. */
class StandInStripe implements StripeClient {
  readonly sessions = new Map<string, Stripe.Checkout.Session>();
  private counter = 0;

  readonly terminal = { connectionTokens: { create: notHere } };
  readonly paymentIntents = { create: notHere, retrieve: notHere, list: notHere };

  readonly customers = {
    create: async () => ({ id: `cus_e2e${String(++this.counter).padStart(6, '0')}`, object: 'customer' }) as unknown as Stripe.Customer,
  };

  readonly checkout = {
    sessions: {
      create: async (params: Stripe.Checkout.SessionCreateParams) => {
        const id = `cs_test_e2e${String(++this.counter).padStart(6, '0')}`;
        const session = {
          id,
          object: 'checkout.session',
          mode: params.mode,
          status: 'open',
          url: `${ORIGIN}/__e2e/stripe/${id}`,
          customer: params.customer ?? null,
          metadata: params.metadata ?? {},
          livemode: false,
          setup_intent: null,
        } as unknown as Stripe.Checkout.Session;
        this.sessions.set(id, session);
        return session;
      },
      retrieve: async (id: string) => {
        const session = this.sessions.get(id);
        if (!session) {
          throw Object.assign(new Error(`No such checkout.session: '${id}'`), {
            type: 'StripeInvalidRequestError',
            code: 'resource_missing',
            statusCode: 404,
          });
        }
        return structuredClone(session);
      },
    },
  };

  /** The client typed a card on the page and tapped Save. */
  complete(id: string): boolean {
    const session = this.sessions.get(id);
    if (!session) return false;
    const customer = typeof session.customer === 'string' ? session.customer : null;
    const n = String(++this.counter).padStart(6, '0');
    Object.assign(session, {
      status: 'complete',
      setup_intent: {
        id: `seti_e2e${n}`,
        object: 'setup_intent',
        status: 'succeeded',
        customer,
        payment_method: { id: `pm_e2e${n}`, object: 'payment_method', type: 'card', customer, card: { brand: 'visa', last4: '4242', exp_month: 12, exp_year: 2030 } },
      },
    });
    return true;
  }
}

const stripe = new StandInStripe();

// ------------------------------------------------------------------- The API

/** Google's and Yelp's answers from the server's own test fixtures, without author photos (nothing loads from outside). */
function fixture(path: string): unknown {
  return JSON.parse(readFileSync(new URL(path, FIXTURES), 'utf8'));
}

function withoutPhotos(google: unknown): unknown {
  const place = structuredClone(google) as { reviews?: { authorAttribution?: { photoUri?: unknown } }[] };
  for (const review of place.reviews ?? []) if (review.authorAttribution) delete review.authorAttribution.photoUri;
  return place;
}

const reviewsFetch: typeof fetch = async (input) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  const reply = (body: unknown) => new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' } });
  if (url.host === 'places.googleapis.com') return reply(withoutPhotos(fixture('google/place-details.json')));
  if (url.host === 'api.yelp.com') {
    if (url.pathname.endsWith('/reviews')) {
      const reviews = fixture('yelp/reviews.json') as { reviews?: { user?: { image_url?: unknown } }[] };
      for (const r of reviews.reviews ?? []) if (r.user) r.user.image_url = null;
      return reply(reviews);
    }
    return reply(fixture('yelp/business.json'));
  }
  throw new TypeError(`fetch failed: nothing leaves this machine in the end-to-end tests (${url.host})`);
};

const config = configFromEnv({});

const deps: Deps = {
  db: poolDb(pool),
  config,
  catalog,
  now: () => new Date(),
  uuid: randomUUID,
  manageToken: newManageToken,
  stripe: () => stripe,
  blob: { put: notHere, del: notHere },
  fetch: reviewsFetch,
  // Each test passes its own address, so the booking limits (5 an hour per network) are per test.
  clientIp: (request) => request.headers.get('x-real-ip') ?? undefined,
  log: {
    error: (message, details) => console.error(JSON.stringify({ level: 'error', message, ...details })),
    warn: (message, details) => console.warn(JSON.stringify({ level: 'warn', message, ...details })),
  },
};

const app = createApp(deps);

// ------------------------------------------------------------ Test plumbing

async function readBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const text = Buffer.concat(chunks).toString('utf8');
  if (!text) return {};
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return Object.fromEntries(new URLSearchParams(text));
  }
}

function send(res: ServerResponse, status: number, body: string, type = 'application/json; charset=utf-8', headers: Record<string, string> = {}) {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store', ...headers });
  res.end(body);
}

const escapeHtml = (text: string) => text.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] ?? c);

/** A plain page standing in for Stripe's card page: Save card, or Back. */
function stripePage(id: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Test card page</title>
<style>body{font:17px/1.5 system-ui,sans-serif;max-width:480px;margin:48px auto;padding:0 16px}button{font:inherit;min-height:44px;padding:0 20px;border-radius:22px;border:1px solid #1f4fd8;margin-right:12px}button.save{background:#1f4fd8;color:#fff}</style></head>
<body><main><h1>Test card page</h1><p>Stands in for Stripe's card page in the end-to-end tests. Saving uses a test Visa ending in 4242.</p>
<form method="post" action="/__e2e/stripe/${escapeHtml(id)}/save"><button class="save" type="submit">Save card</button></form>
<form method="post" action="/__e2e/stripe/${escapeHtml(id)}/back" style="margin-top:12px"><button type="submit">Back</button></form></main></body></html>`;
}

async function plumbing(req: IncomingMessage, res: ServerResponse, url: URL): Promise<void> {
  const parts = url.pathname.split('/').filter(Boolean); // ['__e2e', …]
  if (parts[1] === 'reviews' && req.method === 'POST') {
    const { live } = await readBody(req);
    config.googlePlacesApiKey = live ? 'e2e-google-key' : undefined;
    config.yelpApiKey = live ? 'e2e-yelp-key' : undefined;
    return send(res, 200, JSON.stringify({ live: Boolean(live) }));
  }
  if (parts[1] === 'protection' && req.method === 'POST') {
    const { on } = await readBody(req);
    config.stripeSecretKey = on ? 'sk_test_e2e' : undefined;
    await pool.query(
      `INSERT INTO settings (key, value, updated_at) VALUES ('no_show', $1::jsonb, now())
       ON CONFLICT (key) DO UPDATE SET value = settings.value || EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
      [JSON.stringify({ enabled: Boolean(on) })],
    );
    return send(res, 200, JSON.stringify({ on: Boolean(on) }));
  }
  if (parts[1] === 'stripe' && parts[2]) {
    const id = parts[2];
    if (req.method === 'GET' && parts.length === 3) {
      return stripe.sessions.has(id) ? send(res, 200, stripePage(id), 'text/html; charset=utf-8') : send(res, 404, 'No such session', 'text/plain');
    }
    if (req.method === 'POST' && parts[3] === 'save') {
      stripe.complete(id);
      // What the server's card return does for the website (returnTo "web").
      return send(res, 302, '', 'text/plain', { location: `/book/card-return?status=saved&session_id=${encodeURIComponent(id)}` });
    }
    if (req.method === 'POST' && parts[3] === 'back') {
      return send(res, 302, '', 'text/plain', { location: '/book/card-return?status=cancelled' });
    }
  }
  send(res, 404, JSON.stringify({ error: 'No such end-to-end control' }));
}

// -------------------------------------------------------- The site and routing

const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json',
};

/** A file of the built site, or null (never outside it). */
function siteFile(pathname: string): string | null {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  const file = normalize(join(PUBLIC_DIR, decoded));
  if (file !== PUBLIC_DIR && !file.startsWith(PUBLIC_DIR + sep)) return null;
  return existsSync(file) && statSync(file).isFile() ? file : null;
}

function serveFile(res: ServerResponse, file: string, status = 200): void {
  const immutable = file.includes(`${sep}assets${sep}`);
  res.writeHead(status, {
    'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
    'cache-control': immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=0, must-revalidate',
    'x-content-type-options': 'nosniff',
  });
  res.end(readFileSync(file));
}

async function api(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    if (Array.isArray(value)) value.forEach((v) => headers.append(name, v));
    else if (value !== undefined) headers.set(name, value);
  }
  if (!headers.has('x-real-ip')) headers.set('x-real-ip', req.socket.remoteAddress ?? '127.0.0.1');
  const hasBody = req.method !== 'GET' && req.method !== 'HEAD';
  const request = new Request(`${ORIGIN}${req.url ?? '/'}`, {
    method: req.method ?? 'GET',
    headers,
    body: hasBody ? (Readable.toWeb(req) as ReadableStream) : null,
    ...(hasBody ? { duplex: 'half' } : {}),
  } as RequestInit);
  const response = await app.fetch(request);
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? '/', ORIGIN);
    if (url.pathname.startsWith('/__e2e/')) return await plumbing(req, res, url);
    if (url.pathname === '/api' || url.pathname.startsWith('/api/')) return await api(req, res);
    const file = siteFile(url.pathname);
    if (file) return serveFile(res, file);
    // A hashed file that isn't there is a real 404, not the page.
    if (url.pathname.startsWith('/assets/')) return send(res, 404, 'Not found', 'text/plain');
    return serveFile(res, join(PUBLIC_DIR, 'index.html'));
  } catch (error) {
    console.error(error);
    if (!res.headersSent) send(res, 500, JSON.stringify({ error: { code: 'server_error', message: 'The end-to-end server failed.' } }));
  }
});

server.listen(PORT, '127.0.0.1', () => console.log(`Izzy Clipz end-to-end server on ${ORIGIN}`));

async function stop(): Promise<void> {
  server.close();
  await pool.end().catch(() => undefined);
  await socket.stop().catch(() => undefined);
  await db.close().catch(() => undefined);
  process.exit(0);
}

process.on('SIGINT', () => void stop());
process.on('SIGTERM', () => void stop());
