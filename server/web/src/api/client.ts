// The site's API client: same-origin requests to /api, JSON bodies sent as
// application/json (the server requires it), and every failure turned into an
// ApiError with a plain sentence that says what to do (the Kit's APIError).

import type {
  Appointment,
  Availability,
  BookingConfirmation,
  BookingTarget,
  CardCheckout,
  Catalog,
  NewAppointment,
  NoShowPolicy,
  Reviews,
  SavedCard,
} from './types';

/** Not a code the server sends: the request never got an answer. */
export const OFFLINE = 'offline';

export const OFFLINE_MESSAGE = "We couldn't reach the shop. Check your internet connection and try again.";

/** The API's error codes the site handles by name. */
export const ErrorCode = {
  invalidRequest: 'invalid_request',
  unauthorized: 'unauthorized',
  notFound: 'not_found',
  slotTaken: 'slot_taken',
  notCancellable: 'not_cancellable',
  outsideHours: 'outside_hours',
  tooSoon: 'too_soon',
  tooFar: 'too_far',
  rateLimited: 'rate_limited',
  cardRequired: 'card_required',
  policyChanged: 'policy_changed',
  lateCancelFee: 'late_cancel_fee',
  stripeNotConfigured: 'stripe_not_configured',
  serverError: 'server_error',
} as const;

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
  }

  /** The request never got an answer: the booking may still have gone through. */
  get isOffline(): boolean {
    return this.code === OFFLINE;
  }
}

/** A friendly sentence for a code when the server didn't send one (the Kit's `userMessage`). */
export function defaultMessage(code: string, status: number): string {
  switch (code) {
    case OFFLINE:
      return OFFLINE_MESSAGE;
    case ErrorCode.invalidRequest:
      return "Something in that request wasn't right. Check the details and try again.";
    case ErrorCode.notFound:
      return "We couldn't find that. It may have been removed.";
    case ErrorCode.slotTaken:
      return 'Someone just booked that time. Pick another one.';
    case ErrorCode.notCancellable:
      return "This appointment can't be cancelled anymore. Call the shop if you need to change it.";
    case ErrorCode.rateLimited:
      return "That's a lot of tries in a short time. Wait a little and try again, or call the shop.";
    case ErrorCode.outsideHours:
      return "That time is outside the shop's hours. Pick another time.";
    case ErrorCode.tooSoon:
      return 'That time is too soon to book. Pick a later time.';
    case ErrorCode.tooFar:
      return 'That day is too far ahead to book. Pick an earlier day.';
    case ErrorCode.cardRequired:
      return "Add a card to book this time. You won't be charged now.";
    case ErrorCode.policyChanged:
      return 'The no-show policy for this booking just changed. Check it and book again.';
    default:
      return status >= 500 || status === 0
        ? 'Something went wrong on our side. Try again in a moment, or call the shop.'
        : "Something in that request wasn't right. Check the details and try again.";
  }
}

/** What a response that isn't 2xx becomes: the contract's error envelope when there is one. */
export async function errorFromResponse(response: Response): Promise<ApiError> {
  let code: string | null = null;
  let message = '';
  try {
    const body: unknown = await response.json();
    const error = (body as { error?: { code?: unknown; message?: unknown } } | null)?.error;
    if (typeof error?.code === 'string') code = error.code;
    if (typeof error?.message === 'string') message = error.message.trim().slice(0, 300);
  } catch {
    // Not JSON (a proxy's error page): guessed from the status below.
  }
  if (!code) {
    const status = response.status;
    code =
      status === 404 ? ErrorCode.notFound : status === 401 ? ErrorCode.unauthorized : status === 429 ? ErrorCode.rateLimited : status >= 500 ? ErrorCode.serverError : ErrorCode.invalidRequest;
  }
  return new ApiError(code, message || defaultMessage(code, response.status), response.status);
}

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}

/** The sentence to show for any error. */
export function errorMessage(error: unknown): string {
  return isApiError(error) ? error.message : defaultMessage(ErrorCode.serverError, 500);
}

interface RequestOptions {
  method?: 'GET' | 'POST';
  body?: unknown;
  headers?: Record<string, string>;
  signal?: AbortSignal;
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json', ...options.headers };
  let body: string | undefined;
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(options.body);
  }
  let response: Response;
  try {
    response = await fetch(path, { method: options.method ?? 'GET', headers, body, signal: options.signal, credentials: 'same-origin' });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    throw new ApiError(OFFLINE, OFFLINE_MESSAGE, 0);
  }
  if (!response.ok) throw await errorFromResponse(response);
  try {
    return (await response.json()) as T;
  } catch {
    throw new ApiError(ErrorCode.serverError, "Something went wrong reading the shop's reply. Try again in a moment.", response.status);
  }
}

function targetQuery(target: BookingTarget): string {
  const params = new URLSearchParams('offeringId' in target ? { offeringId: target.offeringId } : { serviceId: target.serviceId, barberId: 'any' });
  return params.toString();
}

function targetBody(target: BookingTarget): Record<string, string> {
  return 'offeringId' in target ? { offeringId: target.offeringId } : { serviceId: target.serviceId, barberId: 'any' };
}

export const api = {
  catalog: (signal?: AbortSignal) => request<Catalog>('/api/catalog', { signal }),

  reviews: (signal?: AbortSignal) => request<Reviews>('/api/reviews', { signal }),

  availability: (target: BookingTarget, from: string, days: number, signal?: AbortSignal) =>
    request<Availability>(`/api/availability?${targetQuery(target)}&from=${from}&days=${days}`, { signal }),

  noShowPolicy: (target: BookingTarget, signal?: AbortSignal) =>
    request<NoShowPolicy>(`/api/no-show-policy?${targetQuery(target)}`, { signal }),

  /** Stripe's card page for this booking, coming back to the website (`returnTo: "web"`). */
  startCardCheckout: (target: BookingTarget, cardToken: string) =>
    request<CardCheckout>('/api/cards/checkout', {
      method: 'POST',
      body: { ...targetBody(target), returnTo: 'web' },
      headers: { 'X-Card-Token': cardToken },
    }),

  /** Saves the card Stripe's page collected; again with the same token and session, the same card. */
  saveCard: (sessionId: string, cardToken: string) =>
    request<{ card: SavedCard }>('/api/cards', { method: 'POST', body: { sessionId }, headers: { 'X-Card-Token': cardToken } }).then(
      (r) => r.card,
    ),

  /**
   * Books it with the manage token made for this booking (and the card, when one is required).
   * A network failure is tried once more with the same token: if the first try went through and
   * only its answer was lost, the server answers with that same appointment instead of booking twice.
   */
  async book(appointment: NewAppointment, manageToken: string, cardToken?: string): Promise<BookingConfirmation> {
    const send = () =>
      request<BookingConfirmation>('/api/appointments', {
        method: 'POST',
        body: {
          ...targetBody(appointment.target),
          start: appointment.start,
          customer: appointment.customer,
          ...(appointment.note ? { note: appointment.note } : {}),
          ...(appointment.noShowPolicy !== undefined ? { noShowPolicy: appointment.noShowPolicy } : {}),
        },
        headers: { 'X-Manage-Token': manageToken, ...(cardToken ? { 'X-Card-Token': cardToken } : {}) },
      });
    try {
      return await send();
    } catch (error) {
      if (isApiError(error) && error.isOffline) return send();
      throw error;
    }
  },

  appointment: (id: string, manageToken: string, signal?: AbortSignal) =>
    request<{ appointment: Appointment }>(`/api/appointments/${encodeURIComponent(id)}`, {
      headers: { 'X-Manage-Token': manageToken },
      signal,
    }).then((r) => r.appointment),

  /**
   * Cancels it. Inside the agreed late-cancellation window the server first answers 409
   * `late_cancel_fee` with the warning; the client then cancels with `acceptLateCancelFee`.
   */
  cancel: (id: string, manageToken: string, acceptLateCancelFee = false) =>
    request<{ appointment: Appointment }>(`/api/appointments/${encodeURIComponent(id)}/cancel`, {
      method: 'POST',
      headers: { 'X-Manage-Token': manageToken },
      ...(acceptLateCancelFee ? { body: { acceptLateCancelFee: true } } : {}),
    }).then((r) => r.appointment),
};

export type Api = typeof api;
