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
