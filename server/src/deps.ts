import type Stripe from 'stripe';
import type { Catalog } from './catalog.js';
import type { Config } from './config.js';
import type { Db } from './db.js';

/** Product photo storage (Vercel Blob in production, a fake in tests). */
export interface BlobStore {
  put(pathname: string, body: Uint8Array, options: { contentType: string }): Promise<{ url: string }>;
  del(url: string): Promise<void>;
}

/**
 * The part of stripe-node the server uses, so tests can pass a fake. Every call
 * made for the shop goes through `shopStripe` (stripeaccount.ts) and passes its
 * `requestOptions`: in connect mode that's the shop's connected account (the
 * Stripe-Account header). Only `accounts` and `accountLinks` are the platform's
 * own calls about that account.
 */
export interface StripeClient {
  /** Stripe Connect (the platform): the shop's own account, made once and read back for its status. */
  accounts: {
    create(params: Stripe.AccountCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.Account>;
    retrieve(id: string, params?: Stripe.AccountRetrieveParams, options?: Stripe.RequestOptions): Promise<Stripe.Account>;
  };
  /** Stripe Connect (the platform): the link to Stripe's own onboarding for that account. */
  accountLinks: {
    create(params: Stripe.AccountLinkCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.AccountLink>;
  };
  terminal: {
    connectionTokens: {
      create(params?: Stripe.Terminal.ConnectionTokenCreateParams, options?: Stripe.RequestOptions): Promise<{ secret: string }>;
    };
    /** Connect mode: the shop's Terminal location, made on its connected account the first time it's needed. */
    locations: {
      create(params: Stripe.Terminal.LocationCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.Terminal.Location>;
    };
  };
  paymentIntents: {
    create(params: Stripe.PaymentIntentCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.PaymentIntent>;
    retrieve(id: string, params?: Stripe.PaymentIntentRetrieveParams, options?: Stripe.RequestOptions): Promise<Stripe.PaymentIntent>;
    /** One page (the newest first); a no-show fee whose answer was lost is looked up this way. */
    list(params: Stripe.PaymentIntentListParams, options?: Stripe.RequestOptions): Promise<Stripe.ApiList<Stripe.PaymentIntent>>;
    /** An email receipt after an in-person payment went through: Stripe sends one when `receipt_email` is set. */
    update(id: string, params: Stripe.PaymentIntentUpdateParams, options?: Stripe.RequestOptions): Promise<Stripe.PaymentIntent>;
  };
  /** No-show protection: a Customer to save the card to, and Checkout in setup mode to collect it. */
  customers: {
    create(params: Stripe.CustomerCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.Customer>;
    /** Deleting a saved card's Customer (retention.ts): Stripe can't charge anything saved under it any more. */
    del(id: string, params?: Stripe.CustomerDeleteParams, options?: Stripe.RequestOptions): Promise<Stripe.DeletedCustomer>;
  };
  /** Deleting a saved card (retention.ts): detached from its Customer, it can never be used again. */
  paymentMethods: {
    detach(id: string, params?: Stripe.PaymentMethodDetachParams, options?: Stripe.RequestOptions): Promise<Stripe.PaymentMethod>;
  };
  checkout: {
    sessions: {
      create(params: Stripe.Checkout.SessionCreateParams, options?: Stripe.RequestOptions): Promise<Stripe.Checkout.Session>;
      retrieve(id: string, params?: Stripe.Checkout.SessionRetrieveParams, options?: Stripe.RequestOptions): Promise<Stripe.Checkout.Session>;
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
  /** 32 random bytes in base64url: a manage token, or a computer's sign-in token. */
  manageToken(): string;
  /** A 6-digit code for signing in on a computer, from crypto random ("004219"). */
  computerCode(): string;
  /** A Stripe client for this secret key. */
  stripe(secretKey: string): StripeClient;
  blob: BlobStore;
  /** Outbound HTTP for Google and Yelp. */
  fetch: typeof fetch;
  clientIp(request: Request): string | undefined;
  log: Logger;
}
