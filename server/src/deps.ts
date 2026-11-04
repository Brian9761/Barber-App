import type Stripe from 'stripe';
import type { Catalog } from './catalog.js';
import type { Config } from './config.js';
import type { Db } from './db.js';

/** Product photo storage (Vercel Blob in production, a fake in tests). */
export interface BlobStore {
  put(pathname: string, body: Uint8Array, options: { contentType: string }): Promise<{ url: string }>;
  del(url: string): Promise<void>;
}

/** The part of stripe-node the server uses, so tests can pass a fake. */
export interface StripeClient {
  terminal: {
    connectionTokens: {
      create(params?: Stripe.Terminal.ConnectionTokenCreateParams): Promise<{ secret: string }>;
    };
  };
  paymentIntents: {
    create(params: Stripe.PaymentIntentCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.PaymentIntent>;
    retrieve(id: string): Promise<Stripe.PaymentIntent>;
    /** One page (the newest first); a no-show fee whose answer was lost is looked up this way. */
    list(params: Stripe.PaymentIntentListParams, options?: Stripe.RequestOptions): Promise<Stripe.ApiList<Stripe.PaymentIntent>>;
  };
  /** No-show protection: a Customer to save the card to, and Checkout in setup mode to collect it. */
  customers: {
    create(params: Stripe.CustomerCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.Customer>;
  };
  checkout: {
    sessions: {
      create(params: Stripe.Checkout.SessionCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.Checkout.Session>;
      retrieve(id: string, params?: Stripe.Checkout.SessionRetrieveParams): Promise<Stripe.Checkout.Session>;
    };
  };
}

export interface Logger {
  error(message: string, details?: Record<string, unknown>): void;
  warn(message: string, details?: Record<string, unknown>): void;
}

/** Everything a request handler needs from the outside world. */
export interface Deps {
  db: Db;
  config: Config;
  catalog: Catalog;
  now(): Date;
  uuid(): string;
  manageToken(): string;
  /** A Stripe client for this secret key. */
  stripe(secretKey: string): StripeClient;
  blob: BlobStore;
  /** Outbound HTTP for Google and Yelp. */
  fetch: typeof fetch;
  clientIp(request: Request): string | undefined;
  log: Logger;
}
