// What this browser keeps: the booking in progress (this tab only), the
// appointments booked here with their manage tokens (without the client's name,
// number, email or note), and the client's details and card token when they
// asked to be remembered. Storage can be off or full (private windows, blocked
// site data), so every read and write is guarded and the site still works
// without it.
//
// A computer can be shared, so a saved card is kept with the number of the
// client who added it, and it's only ever offered to that number.

import type { Appointment, SavedCard } from '../api/types';
import { isToken } from './tokens';

type Area = 'local' | 'session';

function storage(area: Area): Storage | null {
  try {
    return area === 'local' ? window.localStorage : window.sessionStorage;
  } catch {
    return null;
  }
}

export function readJSON(area: Area, key: string): unknown {
  try {
    const text = storage(area)?.getItem(key);
    return text ? (JSON.parse(text) as unknown) : null;
  } catch {
    return null;
  }
}

export function writeJSON(area: Area, key: string, value: unknown): boolean {
  try {
    const store = storage(area);
    if (!store) return false;
    store.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

export function removeKey(area: Area, key: string): void {
  try {
    storage(area)?.removeItem(key);
  } catch {
    // Nothing to do: it isn't stored.
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// ---------------------------------------------------------------- Appointments

export const APPOINTMENTS_KEY = 'izzy.appointments.v1';
/** How long a finished appointment stays listed, like the app. */
export const KEEP_DAYS = 30;

/**
 * An appointment as My appointments shows it: everything but the client's name,
 * number, email and note, which this computer doesn't need to keep.
 */
export type ListedAppointment = Omit<Appointment, 'customer' | 'note'>;

/** The appointment without the client's own details. */
export function listedAppointment(appointment: ListedAppointment): ListedAppointment {
  const { customer: _customer, note: _note, ...listed } = appointment as Partial<Appointment> & ListedAppointment;
  return listed;
}

export interface SavedAppointment {
  id: string;
  manageToken: string;
  /** As the server last described it. */
  appointment: ListedAppointment;
  checkedAt: string;
  /** The server doesn't know it (or its token) any more. */
  notFound?: boolean;
}

/** A manage token as the server hands them out: 43 base64url characters. */
const MANAGE_TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

function isSavedAppointment(value: unknown): value is SavedAppointment {
  return (
    isObject(value) &&
    typeof value.id === 'string' &&
    typeof value.manageToken === 'string' &&
    MANAGE_TOKEN_RE.test(value.manageToken) &&
    isObject(value.appointment) &&
    typeof value.appointment.start === 'string' &&
    typeof value.appointment.end === 'string'
  );
}

/** The appointments booked from this browser, soonest first, without those that ended over 30 days ago. */
export function loadAppointments(now: Date = new Date()): SavedAppointment[] {
  const stored = readJSON('local', APPOINTMENTS_KEY);
  const all = Array.isArray(stored) ? stored.filter(isSavedAppointment) : [];
  const cutoff = now.getTime() - KEEP_DAYS * 86_400_000;
  return all
    .filter((s) => new Date(s.appointment.end).getTime() >= cutoff)
    .map((s) => ({ ...s, appointment: listedAppointment(s.appointment) }))
    .sort((a, b) => a.appointment.start.localeCompare(b.appointment.start) || a.id.localeCompare(b.id));
}

function storeAppointments(list: SavedAppointment[]): boolean {
  return writeJSON(
    'local',
    APPOINTMENTS_KEY,
    list.map((s) => ({ ...s, appointment: listedAppointment(s.appointment) })),
  );
}

/** Keeps a booking with its manage token. False when this browser couldn't keep it. */
export function saveAppointment(appointment: ListedAppointment, manageToken: string, now: Date = new Date()): boolean {
  const list = loadAppointments(now).filter((s) => s.id !== appointment.id);
  list.push({ id: appointment.id, manageToken, appointment, checkedAt: now.toISOString() });
  return storeAppointments(list);
}

export function updateAppointment(id: string, change: (saved: SavedAppointment) => SavedAppointment, now: Date = new Date()): void {
  storeAppointments(loadAppointments(now).map((s) => (s.id === id ? change(s) : s)));
}

export function removeAppointment(id: string, now: Date = new Date()): void {
  storeAppointments(loadAppointments(now).filter((s) => s.id !== id));
}

/** "Forget me on this computer": the list goes. The appointments stay booked with the shop. */
export function forgetAppointments(): void {
  removeKey('local', APPOINTMENTS_KEY);
}

// ------------------------------------------------------------------- The card

export const CARD_KEY = 'izzy.card.v1';
/** The card token waiting for Stripe's page to send the client back (this tab only). */
export const CARD_CHECKOUT_KEY = 'izzy.cardCheckout.v1';

export interface StoredCard {
  token: string;
  card: SavedCard;
  /** The number (E.164) of the client who added it: the card is only offered to that number. */
  phone: string;
}

const E164_RE = /^\+1\d{10}$/;

function isStoredCard(value: unknown): value is StoredCard {
  return (
    isObject(value) &&
    isToken(value.token) &&
    typeof value.phone === 'string' &&
    E164_RE.test(value.phone) &&
    isObject(value.card) &&
    typeof value.card.brand === 'string' &&
    typeof value.card.last4 === 'string' &&
    typeof value.card.expMonth === 'number' &&
    typeof value.card.expYear === 'number'
  );
}

/** The saved card, whoever added it: remembered on this computer, or kept for this visit only. */
export function loadCard(): StoredCard | null {
  for (const area of ['session', 'local'] as const) {
    const stored = readJSON(area, CARD_KEY);
    if (isStoredCard(stored)) return stored;
  }
  return null;
}

/** The saved card of the client with this number (E.164), or null: nobody else gets it. */
export function loadCardFor(phone: string): StoredCard | null {
  const stored = loadCard();
  return stored !== null && stored.phone === phone ? stored : null;
}

/** "Remember me" keeps the card token on this computer; otherwise only until the tab closes. */
export function storeCard(stored: StoredCard, remember: boolean): void {
  removeKey(remember ? 'session' : 'local', CARD_KEY);
  writeJSON(remember ? 'local' : 'session', CARD_KEY, stored);
}

/** Forgets the saved card; given a token, only that card (one added since stays). */
export function forgetCard(token?: string): void {
  for (const area of ['local', 'session'] as const) {
    if (token === undefined) {
      removeKey(area, CARD_KEY);
      continue;
    }
    const stored = readJSON(area, CARD_KEY);
    if (isObject(stored) && stored.token === token) removeKey(area, CARD_KEY);
  }
}

/**
 * The client with this number chose "Remember me" (or not) for this booking: their card
 * is kept on this computer, or only until this tab closes. A card someone else added
 * isn't theirs to use, so it's forgotten.
 */
export function keepCardFor(phone: string, remember: boolean): void {
  const stored = loadCard();
  if (stored === null) return;
  if (stored.phone !== phone) forgetCard();
  else storeCard(stored, remember);
}

/** Good through the last day of its expiry month, like the server: it must last until the appointment's month. */
export function cardValidOn(card: SavedCard, date: string): boolean {
  const [year, month] = date.split('-').map(Number) as [number, number];
  return card.expYear > year || (card.expYear === year && card.expMonth >= month);
}

export interface PendingCardCheckout {
  token: string;
  remember: boolean;
  /** The Checkout Session this tab started: the one the card is saved from. */
  sessionId: string;
  /** The number (E.164) of the client adding it. */
  phone: string;
}

export function savePendingCheckout(pending: PendingCardCheckout): boolean {
  return writeJSON('session', CARD_CHECKOUT_KEY, pending);
}

export function loadPendingCheckout(): PendingCardCheckout | null {
  const stored = readJSON('session', CARD_CHECKOUT_KEY);
  if (
    !isObject(stored) ||
    !isToken(stored.token) ||
    typeof stored.sessionId !== 'string' ||
    typeof stored.phone !== 'string' ||
    !E164_RE.test(stored.phone)
  ) {
    return null;
  }
  return { token: stored.token, remember: stored.remember === true, sessionId: stored.sessionId, phone: stored.phone };
}

export function clearPendingCheckout(): void {
  removeKey('session', CARD_CHECKOUT_KEY);
}

// ---------------------------------------------------------------- Your details

export const DETAILS_KEY = 'izzy.details.v1';

export interface RememberedDetails {
  name: string;
  phone: string;
  email: string;
}

export function loadRememberedDetails(): RememberedDetails | null {
  const stored = readJSON('local', DETAILS_KEY);
  if (!isObject(stored) || typeof stored.name !== 'string' || typeof stored.phone !== 'string') return null;
  return { name: stored.name, phone: stored.phone, email: typeof stored.email === 'string' ? stored.email : '' };
}

export function rememberDetails(details: RememberedDetails): void {
  writeJSON('local', DETAILS_KEY, details);
}

export function forgetDetails(): void {
  removeKey('local', DETAILS_KEY);
}

/** "Not you? Forget me on this computer": the remembered name, number and email, and the card. */
export function forgetClient(): void {
  forgetDetails();
  forgetCard();
  clearPendingCheckout();
}
