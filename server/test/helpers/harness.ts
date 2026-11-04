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

/** What the next off-session charge does (`paymentIntents.create` with `confirm` and `off_session`). */
export type ChargeOutcome =
  | 'succeed'
  | 'processing'
  | 'decline'
  | 'insufficient_funds'
  | 'authentication_required'
  | 'requires_action'
  | 'card_removed';

/** A card the client typed on Stripe's page (test card 4242 unless a test says otherwise). */
export interface FakeCard {
  brand: string;
  last4: string;
  exp_month: number;
  exp_year: number;
}

/** A Stripe-like error, as stripe-node throws them. */
export function stripeError(type: string, fields: Record<string, unknown> = {}, message = 'Stripe error'): Error {
  return Object.assign(new Error(message), { type, ...fields });
}

/** What a connected account looks like to the platform, as a test sets it (see `FakeStripe.setAccount`). */
export interface FakeAccountState {
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
  currently_due?: string[];
  disabled_reason?: string | null;
  name?: string | null;
}

/**
 * A fake of the Stripe calls the server makes, with Stripe-shaped objects. Like Stripe, every
 * object lives on the account it was made on (the `stripeAccount` request option, or the key's
 * own account without one) and can only be found there.
 */
export class FakeStripe implements StripeClient {
  readonly intents = new Map<string, Stripe.PaymentIntent>();
  readonly sessions = new Map<string, Stripe.Checkout.Session>();
  readonly customerIds: string[] = [];
  /** Connected accounts of the platform (connect mode), by id. */
  readonly connectedAccounts = new Map<string, Stripe.Account>();
  /** Terminal locations, by id. */
  readonly locations = new Map<string, Stripe.Terminal.Location>();
  /** The connected account each object was made on (null: the key's own account). */
  readonly accountOf = new Map<string, string | null>();
  readonly calls: { method: string; params: unknown; options?: Stripe.RequestOptions }[] = [];
  readonly keys: string[] = [];
  nextError: unknown = null;
  /** The next off-session charge's outcome; then back to 'succeed'. */
  nextCharge: ChargeOutcome = 'succeed';
  /** The next off-session charge goes through at Stripe, but its answer is lost (a connection error). */
  loseNextChargeAnswer = false;
  /** The next connected account is made at Stripe, but its answer is lost (a connection error). */
  loseNextAccountAnswer = false;
  /** accounts.create's idempotency keys, with what Stripe answered. */
  private readonly accountKeys = new Map<string, { params: string; id: string }>();
  /** Idempotency keys Stripe has seen, with what it answered (like Stripe, a repeat gets the same answer). */
  private readonly idempotent = new Map<string, { params: string; intent?: Stripe.PaymentIntent; error?: unknown }>();
  private counter = 0;

  /** Stripe's clock (the test's), for each PaymentIntent's `created`. */
  constructor(private readonly clock: () => Date = () => new Date()) {}

  /**
   * What Stripe does to idempotency keys at least 24 hours old: it may prune them, and a
   * key reused after that is a new request.
   */
  forgetIdempotencyKeys(): void {
    this.idempotent.clear();
  }

  private maybeFail(): void {
    if (this.nextError) {
      const error = this.nextError;
      this.nextError = null;
      throw error;
    }
  }

  /** The account a request is made on: its Stripe-Account header, or null for the key's own account. */
  private on(options?: Stripe.RequestOptions): string | null {
    return options?.stripeAccount ?? null;
  }

  /** Whether an object can be seen from a request on `options`' account (only from the one it was made on). */
  private visible(id: string, options?: Stripe.RequestOptions): boolean {
    return (this.accountOf.get(id) ?? null) === this.on(options);
  }

  private nextId(prefix: string): string {
    this.counter += 1;
    return `${prefix}${String(this.counter).padStart(6, '0')}`;
  }

  // Stripe Connect: the platform's own calls about the shop's account.

  readonly accounts = {
    create: async (params: Stripe.AccountCreateParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'accounts.create', params, options });
      this.maybeFail();
      const key = options?.idempotencyKey;
      const seen = key ? this.accountKeys.get(key) : undefined;
      if (seen) {
        if (seen.params !== JSON.stringify(params)) {
          throw stripeError('StripeIdempotencyError', { code: 'idempotency_error', statusCode: 400 }, 'Keys for idempotent requests can only be used with the same parameters');
        }
        return structuredClone(this.connectedAccounts.get(seen.id)!);
      }
      const id = this.nextId('acct_TestFixture');
      const account = {
        id,
        object: 'account',
        type: 'standard',
        country: params.country ?? 'US',
        email: null,
        charges_enabled: false,
        payouts_enabled: false,
        details_submitted: false,
        business_profile: { name: params.business_profile?.name ?? null, mcc: params.business_profile?.mcc ?? null },
        controller: { type: 'application', is_controller: true, ...params.controller },
        capabilities: { card_payments: 'inactive', transfers: 'inactive' },
        requirements: {
          currently_due: ['business_type', 'external_account', 'tos_acceptance.date'],
          past_due: ['business_type', 'external_account', 'tos_acceptance.date'],
          eventually_due: ['business_type', 'external_account', 'tos_acceptance.date'],
          pending_verification: [],
          disabled_reason: 'requirements.past_due',
          current_deadline: null,
          errors: [],
          alternatives: [],
        },
        settings: { dashboard: { display_name: null, timezone: null } },
        metadata: params.metadata ?? {},
      } as unknown as Stripe.Account;
      this.connectedAccounts.set(id, account);
      if (key) this.accountKeys.set(key, { params: JSON.stringify(params), id });
      if (this.loseNextAccountAnswer) {
        this.loseNextAccountAnswer = false;
        throw stripeError('StripeConnectionError', {}, 'socket hang up');
      }
      return structuredClone(account);
    },
    retrieve: async (id: string, params?: Stripe.AccountRetrieveParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'accounts.retrieve', params: { id, ...params }, options });
      this.maybeFail();
      const account = this.connectedAccounts.get(id);
      if (!account) {
        throw stripeError('StripePermissionError', { statusCode: 403 }, `The provided key does not have access to account '${id}' (or that account does not exist).`);
      }
      return structuredClone(account);
    },
  };

  readonly accountLinks = {
    create: async (params: Stripe.AccountLinkCreateParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'accountLinks.create', params, options });
      this.maybeFail();
      if (!this.connectedAccounts.has(params.account)) {
        throw stripeError('StripeInvalidRequestError', { code: 'resource_missing', param: 'account', statusCode: 400 }, `No such account: '${params.account}'`);
      }
      const created = Math.floor(this.clock().getTime() / 1000);
      const n = this.nextId('');
      return { object: 'account_link', created, expires_at: created + 300, url: `https://connect.stripe.com/setup/s/${params.account}/fixture${n}` } as Stripe.AccountLink;
    },
  };

  /**
   * What happens on Stripe's side of onboarding: the owner submits details, Stripe checks them
   * and enables the account (or not). Undefined fields stay as they are.
   */
  setAccount(id: string, state: FakeAccountState): Stripe.Account {
    const account = this.connectedAccounts.get(id) as unknown as Record<string, any> | undefined;
    if (!account) throw new Error(`unknown ${id}`);
    for (const key of ['charges_enabled', 'payouts_enabled', 'details_submitted'] as const) {
      if (state[key] !== undefined) account[key] = state[key];
    }
    if (state.currently_due !== undefined) {
      account.requirements.currently_due = state.currently_due;
      account.requirements.past_due = state.disabled_reason === 'requirements.past_due' ? state.currently_due : [];
    }
    if (state.disabled_reason !== undefined) account.requirements.disabled_reason = state.disabled_reason;
    if (state.name !== undefined) account.business_profile.name = state.name;
    return account as unknown as Stripe.Account;
  }

  /** The owner finished onboarding and Stripe turned card payments and payouts on. */
  activateAccount(id: string, name = 'Izzy Clipz Barbershop'): Stripe.Account {
    return this.setAccount(id, { details_submitted: true, charges_enabled: true, payouts_enabled: true, currently_due: [], disabled_reason: null, name });
  }

  readonly terminal = {
    connectionTokens: {
      create: async (params?: Stripe.Terminal.ConnectionTokenCreateParams, options?: Stripe.RequestOptions) => {
        this.calls.push({ method: 'terminal.connectionTokens.create', params, options });
        this.maybeFail();
        if (params?.location && this.locations.has(params.location) && !this.visible(params.location, options)) {
          throw stripeError('StripeInvalidRequestError', { code: 'resource_missing', param: 'location', statusCode: 400 }, `No such location: '${params.location}'`);
        }
        return { object: 'terminal.connection_token', secret: 'pst_test_YWNjdF8xRml4dHVyZUNvbm5lY3Rpb25Ub2tlbg' };
      },
    },
    locations: {
      create: async (params: Stripe.Terminal.LocationCreateParams, options?: Stripe.RequestOptions) => {
        this.calls.push({ method: 'terminal.locations.create', params, options });
        this.maybeFail();
        const id = this.nextId('tml_TestFixture');
        const location = { id, object: 'terminal.location', display_name: params.display_name, address: params.address, livemode: false, metadata: {} } as unknown as Stripe.Terminal.Location;
        this.locations.set(id, location);
        this.accountOf.set(id, this.on(options));
        return location;
      },
    },
  };

  readonly paymentIntents = {
    create: async (params: Stripe.PaymentIntentCreateParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'paymentIntents.create', params, options });
      this.maybeFail();
      // Stripe keeps idempotency keys per account.
      const key = options?.idempotencyKey ? `${this.on(options) ?? ''}:${options.idempotencyKey}` : undefined;
      if (key) {
        const seen = this.idempotent.get(key);
        if (seen) {
          if (seen.params !== JSON.stringify(params)) {
            throw stripeError('StripeIdempotencyError', { code: 'idempotency_error', statusCode: 400 }, 'Keys for idempotent requests can only be used with the same parameters');
          }
          if (seen.error) throw seen.error;
          return seen.intent as Stripe.PaymentIntent;
        }
      }
      try {
        const intent = this.makeIntent(params, options);
        if (key) this.idempotent.set(key, { params: JSON.stringify(params), intent });
        if (params.confirm && this.loseNextChargeAnswer) {
          this.loseNextChargeAnswer = false;
          throw stripeError('StripeConnectionError', {}, 'socket hang up');
        }
        return intent;
      } catch (error) {
        const e = error as { type?: string };
        if (key && e.type === 'StripeCardError') this.idempotent.set(key, { params: JSON.stringify(params), error });
        throw error;
      }
    },
    // Like Stripe: newest first, filtered by customer and `created`, `limit` per page, `starting_after` for the next.
    list: async (params: Stripe.PaymentIntentListParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'paymentIntents.list', params: structuredClone(params), options });
      this.maybeFail();
      const created = typeof params.created === 'number' ? { gte: params.created, lte: params.created } : (params.created ?? {});
      let all = [...this.intents.values()]
        .filter((pi) => this.visible(pi.id, options))
        .filter((pi) => params.customer === undefined || pi.customer === params.customer)
        .filter((pi) => (created.gte === undefined || pi.created >= created.gte) && (created.gt === undefined || pi.created > created.gt))
        .filter((pi) => (created.lte === undefined || pi.created <= created.lte) && (created.lt === undefined || pi.created < created.lt))
        .reverse();
      if (params.starting_after) all = all.slice(all.findIndex((pi) => pi.id === params.starting_after) + 1);
      const limit = params.limit ?? 10;
      return { object: 'list', url: '/v1/payment_intents', data: all.slice(0, limit), has_more: all.length > limit } as Stripe.ApiList<Stripe.PaymentIntent>;
    },
    retrieve: async (id: string, _params?: Stripe.PaymentIntentRetrieveParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'paymentIntents.retrieve', params: id, options });
      this.maybeFail();
      const intent = this.intents.get(id);
      if (!intent || !this.visible(id, options)) {
        throw Object.assign(new Error(`No such payment_intent: '${id}'`), {
          type: 'StripeInvalidRequestError',
          code: 'resource_missing',
          statusCode: 404,
        });
      }
      return intent;
    },
  };

  private makeIntent(params: Stripe.PaymentIntentCreateParams, options?: Stripe.RequestOptions): Stripe.PaymentIntent {
    {
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
        created: Math.floor(this.clock().getTime() / 1000),
        customer: params.customer ?? null,
        payment_method: params.payment_method ?? null,
        last_payment_error: null,
      } as unknown as Stripe.PaymentIntent;
      this.intents.set(id, intent);
      this.accountOf.set(id, this.on(options));
      if (!(params.confirm && params.off_session)) return intent;
      // An off-session charge of a saved card: Stripe answers at once.
      const outcome = this.nextCharge;
      this.nextCharge = 'succeed';
      const pm = typeof params.payment_method === 'string' ? params.payment_method : '';
      // The saved card is only there on the account it was saved on.
      const known = [...this.sessions.values()].some((session) => {
        const setup = session.setup_intent as Stripe.SetupIntent | null;
        const method = setup?.payment_method as Stripe.PaymentMethod | null | undefined;
        return method?.id === pm && method.customer === params.customer && this.visible(session.id, options);
      });
      if (outcome === 'card_removed' || !known) {
        throw stripeError(
          'StripeInvalidRequestError',
          { code: 'resource_missing', param: 'payment_method', statusCode: 400 },
          `No such PaymentMethod: '${pm}'`,
        );
      }
      if (outcome === 'succeed') {
        Object.assign(intent, { status: 'succeeded', amount_received: intent.amount });
        return intent;
      }
      if (outcome === 'processing' || outcome === 'requires_action') {
        Object.assign(intent, { status: outcome });
        return intent;
      }
      const declineCode = outcome === 'insufficient_funds' ? 'insufficient_funds' : outcome === 'decline' ? 'generic_decline' : 'authentication_required';
      const code = outcome === 'authentication_required' ? 'authentication_required' : 'card_declined';
      Object.assign(intent, { status: 'requires_payment_method', last_payment_error: { type: 'card_error', code, decline_code: declineCode } });
      throw stripeError(
        'StripeCardError',
        { code, decline_code: declineCode, statusCode: 402, requestId: 'req_fixture_decline', payment_intent: intent },
        'Your card was declined.',
      );
    }
  }

  readonly customers = {
    create: async (params: Stripe.CustomerCreateParams, options?: Stripe.RequestOptions) => {
      this.calls.push({ method: 'customers.create', params, options });
      this.maybeFail();
      this.counter += 1;
      const id = `cus_TestFixture${String(this.counter).padStart(6, '0')}`;
      this.customerIds.push(id);
      this.accountOf.set(id, this.on(options));
      return { id, object: 'customer', description: params.description ?? null, metadata: params.metadata ?? {} } as unknown as Stripe.Customer;
    },
  };

  readonly checkout = {
    sessions: {
      create: async (params: Stripe.Checkout.SessionCreateParams, options?: Stripe.RequestOptions) => {
        this.calls.push({ method: 'checkout.sessions.create', params, options });
        this.maybeFail();
        this.counter += 1;
        const id = `cs_test_Fixture${String(this.counter).padStart(6, '0')}`;
        const session = {
          id,
          object: 'checkout.session',
          mode: params.mode,
          status: 'open',
          url: `https://checkout.stripe.com/c/pay/${id}#fixture`,
          customer: params.customer ?? null,
          metadata: params.metadata ?? {},
          livemode: false,
          setup_intent: null,
          success_url: params.success_url,
          cancel_url: params.cancel_url,
        } as unknown as Stripe.Checkout.Session;
        this.sessions.set(id, session);
        this.accountOf.set(id, this.on(options));
        return session;
      },
      retrieve: async (id: string, params?: Stripe.Checkout.SessionRetrieveParams, options?: Stripe.RequestOptions) => {
        this.calls.push({ method: 'checkout.sessions.retrieve', params: { id, ...params }, options });
        this.maybeFail();
        const session = this.sessions.get(id);
        if (!session || !this.visible(id, options)) {
          throw stripeError('StripeInvalidRequestError', { code: 'resource_missing', param: 'session', statusCode: 404 }, `No such checkout.session: '${id}'`);
        }
        // Expanded like the server asks: setup_intent.payment_method.
        return structuredClone(session);
      },
    },
  };

  /** What happens when the client types a card on Stripe's page and taps Save. */
  completeSession(id: string, card: FakeCard = { brand: 'visa', last4: '4242', exp_month: 12, exp_year: 2030 }): Stripe.Checkout.Session {
    const session = this.sessions.get(id);
    if (!session) throw new Error(`unknown ${id}`);
    this.counter += 1;
    const n = String(this.counter).padStart(6, '0');
    const customer = typeof session.customer === 'string' ? session.customer : null;
    const paymentMethod = { id: `pm_TestFixture${n}`, object: 'payment_method', type: 'card', card, customer };
    const setupIntent = { id: `seti_TestFixture${n}`, object: 'setup_intent', status: 'succeeded', customer, payment_method: paymentMethod };
    Object.assign(session, { status: 'complete', setup_intent: setupIntent });
    return session;
  }

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

/**
 * Stripe set up with `key` and no-show protection turned on by the owner, as it must be
 * before online bookings need a card (it's off until then).
 */
export async function protectionOn(h: Harness, key = 'sk_test_fixture'): Promise<void> {
  h.config.stripeSecretKey = key;
  const res = await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { enabled: true } });
  if (res.status !== 200) throw new Error(`Couldn't turn no-show protection on: ${res.text}`);
}

/** The app developer's Connect platform key in tests (STRIPE_CONNECT=on). */
export const PLATFORM_KEY = 'sk_test_platform';
export const PUBLIC_BASE_URL = 'https://izzy-clipz-api.test';

/** Connect mode (the platform's key, STRIPE_CONNECT=on, PUBLIC_BASE_URL) with no account connected yet. */
export function connectMode(h: Harness): void {
  h.config.stripeSecretKey = PLATFORM_KEY;
  h.config.stripeConnect = true;
  h.config.publicBaseUrl = PUBLIC_BASE_URL;
}

/**
 * Connect mode with the shop's own Stripe account connected and taking card payments, as after
 * the owner finished Stripe's onboarding. Returns the account's id.
 */
export async function connectedShop(h: Harness): Promise<string> {
  connectMode(h);
  const link = await h.call('POST', '/api/owner/stripe/connect', { owner: true, body: { returnTo: 'app' } });
  if (link.status !== 201) throw new Error(`Couldn't start connecting Stripe: ${link.text}`);
  const params = h.stripe.calls.filter((c) => c.method === 'accountLinks.create').at(-1)?.params as { account: string };
  h.stripe.activateAccount(params.account);
  const status = await h.call('GET', '/api/owner/stripe', { owner: true });
  if (status.body.status !== 'active') throw new Error(`Stripe isn't active: ${status.text}`);
  return params.account;
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
  let codeCounter = 0;

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
    codeCounter = 0;
    h.catalog = loadCatalog();
    h.config = {
      ...configFromEnv({}),
      ownerKey: OWNER_KEY,
      cronSecret: CRON_SECRET,
      ...options.config,
    };
    h.now = new Date(options.now ?? '2026-11-02T17:00:00Z');
    h.stripe = new FakeStripe(() => h.now);
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
      // 483920 first, then a fixed sequence of other 6-digit codes.
      computerCode: () => String((483920 + codeCounter++ * 271_829) % 1_000_000).padStart(6, '0'),
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
