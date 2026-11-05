// The site's API over the network: same-origin requests to /api, JSON bodies sent
// as application/json (the server requires it), and every failure turned into an
// ApiError with a plain sentence that says what to do (the Kit's APIError).

import type {
  Appointment,
  Availability,
  BookingConfirmation,
  BookingTarget,
  CardCheckout,
  CardDeletion,
  Catalog,
  NewAppointment,
  NoShowPolicy,
  Reviews,
  SavedCard,
} from './types';
import { ApiError, ErrorCode, errorFromResponse, isApiError, OFFLINE, OFFLINE_MESSAGE } from './errors';

interface RequestOptions {
  method?: 'GET' | 'POST' | 'DELETE';
  body?: unknown;
  headers?: Record<string, string>;
  signal?: AbortSignal;
  /** Sent even if the page goes away meanwhile (a request made as the client leaves). */
  keepalive?: boolean;
}

/** The server's words for each answer to DELETE /api/cards (server/src/cards.ts), should an answer come without them. */
export const CARD_DELETED_MESSAGE = "Your saved card is deleted. It can't be charged any more.";
export const CARD_SCHEDULED_MESSAGE = 'Your card will be deleted as soon as your appointments no longer need it.';

/** DELETE /api/cards's answer as the site reads it: a status it doesn't know reads as scheduled, never as deleted (like the Kit). */
export function cardDeletionOf(answer: { cardDeletion?: { status?: unknown; message?: unknown } } | null | undefined): CardDeletion {
  const status = answer?.cardDeletion?.status === 'deleted' ? 'deleted' : 'scheduled';
  const message = answer?.cardDeletion?.message;
  const fallback = status === 'deleted' ? CARD_DELETED_MESSAGE : CARD_SCHEDULED_MESSAGE;
  return { status, message: typeof message === 'string' && message.trim() !== '' ? message.trim() : fallback };
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
    response = await fetch(path, {
      method: options.method ?? 'GET',
      headers,
      body,
      signal: options.signal,
      credentials: 'same-origin',
      ...(options.keepalive ? { keepalive: true } : {}),
    });
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

export const httpApi = {
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
   * Asks the shop to delete the card saved under this token ("Forget me", "Not you?", and right
   * after a booking made without "Remember me"): deleted at Stripe now, or as soon as no booking
   * needs it. A token with no card is a 404. `keepalive` sends it even as the page moves on.
   */
  deleteCard: (cardToken: string, options: { keepalive?: boolean } = {}) =>
    request<{ cardDeletion?: { status?: unknown; message?: unknown } }>('/api/cards', {
      method: 'DELETE',
      headers: { 'X-Card-Token': cardToken },
      keepalive: options.keepalive,
    }).then(cardDeletionOf),

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

  /**
   * "Forget me on this computer": what the backend itself keeps in this browser. The shop's
   * server keeps nothing here (the demo's stand-in keeps its bookings, and forgets them).
   */
  forgetHere: (): void => undefined,
};

/** What the pages call: the shop's server (this file), or the demo's stand-in, which answers the same way. */
export type Api = typeof httpApi;
