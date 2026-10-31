import { afterAll, beforeAll, beforeEach } from 'vitest';
import type Stripe from 'stripe';
import { createApp, type App } from '../../src/app.js';
import { loadCatalog, type Catalog } from '../../src/catalog.js';
import { configFromEnv, type Config } from '../../src/config.js';
import { poolDb } from '../../src/db.js';
import type { BlobStore, Deps, StripeClient } from '../../src/deps.js';
import { startTestDatabase, type TestDatabase } from './db.js';

/** What `fetch`/`Request` accept as a body. */
export type RequestBody = NonNullable<RequestInit['body']>;

export const OWNER_KEY = 'test-owner-key-0123456789abcdefghijklmnop';
export const CRON_SECRET = 'test-cron-secret-0123456789';

/** A fake of the Stripe calls the server makes, with Stripe-shaped objects. */
export class FakeStripe implements StripeClient {
  readonly intents = new Map<string, Stripe.PaymentIntent>();
  readonly calls: { method: string; params: unknown; options?: unknown }[] = [];
  readonly keys: string[] = [];
  nextError: unknown = null;
  private counter = 0;

  private maybeFail(): void {
    if (this.nextError) {
      const error = this.nextError;
      this.nextError = null;
      throw error;
    }
  }

  readonly terminal = {
    connectionTokens: {
      create: async (params?: Stripe.Terminal.ConnectionTokenCreateParams) => {
        this.calls.push({ method: 'terminal.connectionTokens.create', params });
        this.maybeFail();
        return { object: 'terminal.connection_token', secret: 'pst_test_YWNjdF8xRml4dHVyZUNvbm5lY3Rpb25Ub2tlbg' };
      },
    },
  };

  readonly paymentIntents = {
    create: async (params: Stripe.PaymentIntentCreateParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'paymentIntents.create', params, options });
      this.maybeFail();
      this.counter += 1;
      const id = `pi_3TestFixture${String(this.counter).padStart(6, '0')}`;
      const intent = {
        id,
        object: 'payment_intent',
        amount: params.amount,
        amount_received: 0,
        currency: params.currency,
        capture_method: params.capture_method ?? 'automatic_async',
        allowed_payment_method_types: params.allowed_payment_method_types ?? null,
        client_secret: `${id}_secret_FixtureClientSecret`,
        description: params.description ?? null,
        receipt_email: params.receipt_email ?? null,
        metadata: params.metadata ?? {},
        status: 'requires_payment_method',
        livemode: false,
      } as unknown as Stripe.PaymentIntent;
      this.intents.set(id, intent);
      return intent;
    },
    retrieve: async (id: string) => {
      this.calls.push({ method: 'paymentIntents.retrieve', params: id });
      this.maybeFail();
      const intent = this.intents.get(id);
      if (!intent) {
        throw Object.assign(new Error(`No such payment_intent: '${id}'`), {
          type: 'StripeInvalidRequestError',
          code: 'resource_missing',
          statusCode: 404,
        });
      }
      return intent;
    },
  };

  /** What happens when the card is tapped and approved. */
  succeed(id: string): Stripe.PaymentIntent {
    const intent = this.intents.get(id);
    if (!intent) throw new Error(`unknown ${id}`);
    Object.assign(intent, { status: 'succeeded', amount_received: intent.amount });
    return intent;
  }

  setStatus(id: string, status: Stripe.PaymentIntent.Status): void {
    const intent = this.intents.get(id);
    if (!intent) throw new Error(`unknown ${id}`);
    Object.assign(intent, { status });
  }
}

export class FakeBlob implements BlobStore {
  readonly puts: { pathname: string; bytes: number; contentType: string; url: string }[] = [];
  readonly deleted: string[] = [];
  failPut = false;
  failDel = false;

  async put(pathname: string, body: Uint8Array, options: { contentType: string }): Promise<{ url: string }> {
    if (this.failPut) throw new Error('Blob store unavailable');
    const n = this.puts.length + 1;
    const url = `https://fixture.public.blob.vercel-storage.com/${pathname.replace(/\.jpg$/, '')}-r${n}.jpg`;
    this.puts.push({ pathname, bytes: body.byteLength, contentType: options.contentType, url });
    return { url };
  }

  async del(url: string): Promise<void> {
    if (this.failDel) throw new Error('Blob delete failed');
    this.deleted.push(url);
  }
}

export type FetchHandler = (url: URL, init: RequestInit | undefined) => Response | Promise<Response>;

export class FakeFetch {
  readonly calls: { url: string; headers: Record<string, string> }[] = [];
  private readonly routes: { host: string; pathPrefix: string; handler: FetchHandler }[] = [];

  on(urlPrefix: string, handler: FetchHandler): void {
    const u = new URL(urlPrefix);
    this.routes.unshift({ host: u.host, pathPrefix: u.pathname, handler });
  }

  clear(): void {
    this.routes.length = 0;
    this.calls.length = 0;
  }

  readonly fetch: typeof fetch = async (input, init) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    const headers: Record<string, string> = {};
    new Headers(init?.headers).forEach((v, k) => (headers[k] = v));
    this.calls.push({ url: url.toString(), headers });
    const route = this.routes.find((r) => r.host === url.host && url.pathname.startsWith(r.pathPrefix));
    if (!route) throw new TypeError(`fetch failed: no fake for ${url}`);
    return route.handler(url, init);
  };
}

export interface CallOptions {
  body?: unknown;
  rawBody?: RequestBody;
  headers?: Record<string, string>;
  owner?: boolean;
  ip?: string;
}

export interface CallResult<T = any> {
  status: number;
  headers: Headers;
  body: T;
  text: string;
}

export interface Harness {
  database: TestDatabase;
  app: App;
  deps: Deps;
  catalog: Catalog;
  config: Config;
  now: Date;
  stripe: FakeStripe;
  blob: FakeBlob;
  fetch: FakeFetch;
  logs: { level: string; message: string; details?: Record<string, unknown> }[];
  setNow(iso: string): void;
  advance(minutes: number): void;
  call<T = any>(method: string, path: string, options?: CallOptions): Promise<CallResult<T>>;
}

export interface HarnessOptions {
  now?: string;
  config?: Partial<Config>;
}

/** Deterministic UUIDs: 00000000-0000-4000-8000-000000000001, …002, … */
export function fixtureUuid(n: number): string {
  return `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
}

/** Sets up a database for the file and a fresh app, fakes and clock for each test. */
export function useHarness(options: HarnessOptions = {}): Harness {
  const h = {} as Harness;
  let uuidCounter = 0;
  let tokenCounter = 0;

  beforeAll(async () => {
    h.database = await startTestDatabase();
  }, 60_000);

  afterAll(async () => {
    await h.database?.close();
  });

  beforeEach(async () => {
    await h.database.reset();
    uuidCounter = 0;
    tokenCounter = 0;
    h.catalog = loadCatalog();
    h.config = {
      ...configFromEnv({}),
      ownerKey: OWNER_KEY,
      cronSecret: CRON_SECRET,
      ...options.config,
    };
    h.now = new Date(options.now ?? '2026-11-02T17:00:00Z');
    h.stripe = new FakeStripe();
    h.blob = new FakeBlob();
    h.fetch = new FakeFetch();
    h.logs = [];
    const stripe = h.stripe;
    h.deps = {
      db: poolDb(h.database.pool),
      get config() {
        return h.config;
      },
      catalog: h.catalog,
      now: () => new Date(h.now.getTime()),
      uuid: () => fixtureUuid(++uuidCounter),
      manageToken: () => `fixture-manage-token-${String(++tokenCounter).padStart(4, '0')}`.padEnd(43, 'x').slice(0, 43),
      stripe: (key: string) => {
        stripe.keys.push(key);
        return stripe;
      },
      blob: h.blob,
      fetch: h.fetch.fetch,
      clientIp: (request) => request.headers.get('x-real-ip') ?? undefined,
      log: {
        error: (message, details) => h.logs.push({ level: 'error', message, ...(details ? { details } : {}) }),
        warn: (message, details) => h.logs.push({ level: 'warn', message, ...(details ? { details } : {}) }),
      },
    };
    h.app = createApp(h.deps);
  });

  h.setNow = (iso: string) => {
    h.now = new Date(iso);
  };
  h.advance = (minutes: number) => {
    h.now = new Date(h.now.getTime() + minutes * 60_000);
  };
  h.call = async (method, path, opts = {}) => {
    const headers = new Headers(opts.headers);
    if (opts.owner) headers.set('authorization', `Bearer ${OWNER_KEY}`);
    headers.set('x-real-ip', opts.ip ?? '203.0.113.7');
    let body: RequestBody | undefined = opts.rawBody;
    if (opts.body !== undefined) {
      body = JSON.stringify(opts.body);
      if (!headers.has('content-type')) headers.set('content-type', 'application/json');
    }
    const response = await h.app.fetch(new Request(`https://izzy-clipz-api.test${path}`, { method, headers, body: body ?? null }));
    const text = await response.text();
    let parsed: unknown = undefined;
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = undefined;
      }
    }
    return { status: response.status, headers: response.headers, body: parsed as any, text };
  };
  return h;
}
