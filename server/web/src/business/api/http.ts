// The owner API over the network: same-origin requests to /api/owner/…, with this
// computer's session token (Authorization: Bearer), JSON bodies sent as
// application/json, and every failure turned into an ApiError with a plain
// sentence. A 401 means the server no longer knows this computer's session
// (signed out from the iPhone, or 30 days old): the session ends here too, and
// Izzy Clipz Business shows sign-in with a friendly line (session.ts).

import { ApiError, errorFromResponse, OFFLINE } from '../../api/errors';
import { session } from '../session';
import type {
  Analytics,
  AnalyticsQuery,
  ComputerSession,
  NewSale,
  NoShowSettings,
  OwnerAppointment,
  Product,
  ProductInput,
  Sale,
  SalesDay,
  SignedIn,
  StripeConnection,
  StripeConnectLink,
  TimeOff,
  VoidedSale,
} from '../types';

/** What Izzy Clipz Business says when the shop's server can't be reached. */
export const OWNER_OFFLINE_MESSAGE = "We couldn't reach Izzy Clipz Business. Check your internet connection and try again.";

/** Not a code the server sends: there's no session on this computer (signed out in another tab, say). */
export const SIGNED_OUT = 'signed_out';

type Auth = { kind: 'session' } | { kind: 'key'; key: string } | { kind: 'none' };

interface OwnerRequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: unknown;
  /** A file to send as it is (a product photo), with its type. */
  file?: { data: Blob; type: string };
  headers?: Record<string, string>;
  signal?: AbortSignal;
  auth?: Auth;
}

export async function ownerRequest<T>(path: string, options: OwnerRequestOptions = {}): Promise<T> {
  const auth = options.auth ?? { kind: 'session' };
  const headers: Record<string, string> = { Accept: 'application/json', ...options.headers };
  let token: string | null = null;
  if (auth.kind === 'session') {
    token = session.token();
    if (!token) throw new ApiError(SIGNED_OUT, 'Sign in to Izzy Clipz Business first.', 401);
    headers.Authorization = `Bearer ${token}`;
  } else if (auth.kind === 'key') {
    headers.Authorization = `Bearer ${auth.key}`;
  }
  let body: BodyInit | undefined;
  if (options.file) {
    headers['Content-Type'] = options.file.type;
    body = options.file.data;
  } else if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(options.body);
  }
  let response: Response;
  try {
    response = await fetch(path, {
      method: options.method ?? 'GET',
      headers,
      body,
      signal: options.signal,
      credentials: 'same-origin',
      // Nothing of the shop's own area is ever kept by the browser.
      cache: 'no-store',
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    throw new ApiError(OFFLINE, OWNER_OFFLINE_MESSAGE, 0);
  }
  if (!response.ok) {
    const error = await errorFromResponse(response);
    if (error.status === 401 && token) session.expire(token);
    throw error;
  }
  if (response.status === 204) return undefined as T;
  try {
    return (await response.json()) as T;
  } catch {
    throw new ApiError('server_error', "Something went wrong reading the server's reply. Try again in a moment.", response.status);
  }
}

const enc = encodeURIComponent;

export const httpOwnerApi = {
  /** POST /api/computer-sessions: the 6-digit code from the app buys this computer a session. */
  signIn: (code: string, name: string) => ownerRequest<SignedIn>('/api/computer-sessions', { method: 'POST', body: { code, name }, auth: { kind: 'none' } }),

  /**
   * "Use the owner key instead": the key makes a code (POST /api/owner/computer-codes, which only
   * the owner key can), and the code a session, so the key itself is never kept on this computer
   * and the computer shows in the app's list like any other.
   */
  async signInWithKey(key: string, name: string): Promise<SignedIn> {
    const { code } = await ownerRequest<{ code: string }>('/api/owner/computer-codes', { method: 'POST', auth: { kind: 'key', key } });
    return httpOwnerApi.signIn(code, name);
  },

  /** "Sign out": DELETE /api/owner/computer-sessions/current. */
  signOut: () => ownerRequest<void>('/api/owner/computer-sessions/current', { method: 'DELETE' }),

  appointments: (date: string, signal?: AbortSignal) =>
    ownerRequest<{ appointments: OwnerAppointment[] }>(`/api/owner/appointments?date=${enc(date)}`, { signal }).then((r) => r.appointments),

  timeOff: (date: string, signal?: AbortSignal) =>
    ownerRequest<{ timeOff: TimeOff[] }>(`/api/owner/time-off?date=${enc(date)}`, { signal }).then((r) => r.timeOff),

  setStatus: (id: string, status: 'booked' | 'completed' | 'noShow' | 'cancelled') =>
    ownerRequest<{ appointment: OwnerAppointment }>(`/api/owner/appointments/${enc(id)}`, { method: 'PATCH', body: { status } }).then((r) => r.appointment),

  /** Charges the fee agreed at booking (a no-show or a late cancellation) to the card on file. */
  chargeFee: (id: string) =>
    ownerRequest<{ appointment: OwnerAppointment }>(`/api/owner/appointments/${enc(id)}/no-show-fee`, { method: 'POST', body: {} }).then((r) => r.appointment),

  sales: (date: string, signal?: AbortSignal) => ownerRequest<SalesDay>(`/api/owner/sales?date=${enc(date)}`, { signal }),

  /** A cash or other sale, with the ticket's Idempotency-Key: sending it again can't record it twice. */
  createSale: (sale: NewSale, idempotencyKey: string) =>
    ownerRequest<{ sale: Sale }>('/api/owner/sales', { method: 'POST', body: sale, headers: { 'Idempotency-Key': idempotencyKey } }).then((r) => r.sale),

  voidSale: (id: string, reason: string | null) =>
    ownerRequest<VoidedSale>(`/api/owner/sales/${enc(id)}/void`, { method: 'POST', body: reason ? { reason } : {} }),

  analytics: (query: AnalyticsQuery, signal?: AbortSignal) => {
    const params = new URLSearchParams({ from: query.from, to: query.to });
    if (query.barberId) params.set('barberId', query.barberId);
    return ownerRequest<Analytics>(`/api/owner/analytics?${params.toString()}`, { signal });
  },

  products: (signal?: AbortSignal) => ownerRequest<{ products: Product[] }>('/api/owner/products', { signal }).then((r) => r.products),

  createProduct: (input: ProductInput) => ownerRequest<{ product: Product }>('/api/owner/products', { method: 'POST', body: input }).then((r) => r.product),

  updateProduct: (id: string, input: Partial<ProductInput>) =>
    ownerRequest<{ product: Product }>(`/api/owner/products/${enc(id)}`, { method: 'PATCH', body: input }).then((r) => r.product),

  deleteProduct: (id: string) => ownerRequest<void>(`/api/owner/products/${enc(id)}`, { method: 'DELETE' }),

  /** The photo as a JPEG (the server takes JPEGs up to 4 MB). */
  uploadProductPhoto: (id: string, jpeg: Blob) =>
    ownerRequest<{ product: Product }>(`/api/owner/products/${enc(id)}/photo`, { method: 'POST', file: { data: jpeg, type: 'image/jpeg' } }).then(
      (r) => r.product,
    ),

  stripe: (signal?: AbortSignal) => ownerRequest<StripeConnection>('/api/owner/stripe', { signal }),

  /** Stripe's page to connect (or finish setting up) the shop's account, coming back to Settings here. */
  connectStripe: () => ownerRequest<StripeConnectLink>('/api/owner/stripe/connect', { method: 'POST', body: { returnTo: 'web' } }),

  noShowSettings: (signal?: AbortSignal) =>
    ownerRequest<{ noShowSettings: NoShowSettings }>('/api/owner/no-show-settings', { signal }).then((r) => r.noShowSettings),

  updateNoShowSettings: (patch: Partial<NoShowSettings>) =>
    ownerRequest<{ noShowSettings: NoShowSettings }>('/api/owner/no-show-settings', { method: 'PATCH', body: patch }).then((r) => r.noShowSettings),

  computerSessions: (signal?: AbortSignal) => ownerRequest<{ sessions: ComputerSession[] }>('/api/owner/computer-sessions', { signal }).then((r) => r.sessions),

  signOutComputer: (id: string) => ownerRequest<void>(`/api/owner/computer-sessions/${enc(id)}`, { method: 'DELETE' }),

  signOutAllComputers: () => ownerRequest<void>('/api/owner/computer-sessions', { method: 'DELETE' }),

  /** The demo's own sample data back as it started ("Reset the demo"). Nothing to reset on the shop's server. */
  resetDemo: async (): Promise<void> => undefined,
};

/** What the Business pages call: the shop's server (this file), or the demo's stand-in, which answers the same way. */
export type OwnerApi = typeof httpOwnerApi;
