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
import { isDemo } from '../demo/mode';
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
/**
 * The demo's own list: should the real site later open at the demo's address, it never shows
 * (or tries to check with the shop) a booking made in the demo.
 */
export const DEMO_APPOINTMENTS_KEY = 'izzy.demo.appointments.v1';
/** Where the demo keeps the bookings made in it, as the shop's server would (src/demo/api.ts). */
export const DEMO_STORE_KEY = 'izzy.demo.v1';
/** How long a finished appointment stays listed, like the app. */
export const KEEP_DAYS = 30;

function appointmentsKey(): string {
  return isDemo() ? DEMO_APPOINTMENTS_KEY : APPOINTMENTS_KEY;
}

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
  const stored = readJSON('local', appointmentsKey());
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
    appointmentsKey(),
    list.map((s) => ({ ...s, appointment: listedAppointment(s.appointment) })),
  );
}

/** Keeps a booking with its manage token. False when this browser couldn't keep it. */
export function saveAppointment(appointment: ListedAppointment, manageToken: string, now: Date = new Date()): boolean {
  const list = loadAppointments(now).filter((s) => s.id !== appointment.id);
  list.push({ id: appointment.id, manageToken, appointment, checkedAt: now.toISOString() });
  carryAppointment(appointment.id, manageToken, appointment.end, now);
  return storeAppointments(list);
}

export function updateAppointment(id: string, change: (saved: SavedAppointment) => SavedAppointment, now: Date = new Date()): void {
  storeAppointments(loadAppointments(now).map((s) => (s.id === id ? change(s) : s)));
}

export function removeAppointment(id: string, now: Date = new Date()): void {
  storeAppointments(loadAppointments(now).filter((s) => s.id !== id));
  dropCarried(id, now);
}

/** "Forget me on this computer": the list goes. The appointments stay booked with the shop. */
export function forgetAppointments(): void {
  removeKey('local', appointmentsKey());
  forgetCarried();
}

/**
 * The real site, opened where the demo was (the same address), forgets what the demo kept:
 * its bookings were never the shop's.
 */
export function forgetDemoLeftovers(): void {
  removeKey('local', DEMO_STORE_KEY);
  removeKey('local', DEMO_APPOINTMENTS_KEY);
}

// ------------------------------------------- Carried into the app on the Home Screen
//
// Added to an iPhone's or iPad's Home Screen (iOS 17.2 and later), or to the Dock from Safari on
// a Mac, the app gets website data of its own: only the cookies are copied into it, not
// localStorage. So each appointment booked here is also kept, as its id and manage token only,
// in a cookie, and My appointments in the app brings in the ones it doesn't have yet. The server
// never reads it. The demo keeps none: its bookings only exist in the browser they were made in.

export const CARRY_COOKIE = 'izzy_appointments';
/** At most this many, the latest first: a cookie stays small (the shop allows 3 upcoming per number). */
const CARRY_MAX = 10;
const CARRY_MAX_AGE_DAYS = 60;
const ID_RE = /^[A-Za-z0-9-]{1,64}$/;

export interface CarriedAppointment {
  id: string;
  manageToken: string;
  /** Carried until this time (ms): 30 days after the appointment ends, like the list. */
  until: number;
}

function cookieDocument(): Document | null {
  try {
    return typeof document === 'undefined' ? null : document;
  } catch {
    return null;
  }
}

/** Every appointment carried in the cookie that hasn't run out, latest first. */
export function carriedAppointments(now: Date = new Date()): CarriedAppointment[] {
  if (isDemo()) return [];
  let cookies = '';
  try {
    cookies = cookieDocument()?.cookie ?? '';
  } catch {
    return [];
  }
  const value = cookies
    .split(/;\s*/)
    .find((pair) => pair.startsWith(`${CARRY_COOKIE}=`))
    ?.slice(CARRY_COOKIE.length + 1);
  if (!value) return [];
  return value
    .split('~')
    .map((entry) => {
      const [id = '', manageToken = '', until = ''] = entry.split('.');
      return { id, manageToken, until: Number.parseInt(until, 36) * 1000 };
    })
    .filter((c) => ID_RE.test(c.id) && MANAGE_TOKEN_RE.test(c.manageToken) && Number.isFinite(c.until) && c.until > now.getTime());
}

function writeCarried(list: CarriedAppointment[], now: Date): void {
  const doc = cookieDocument();
  if (!doc || isDemo()) return;
  const kept = list
    .filter((c) => c.until > now.getTime())
    .sort((a, b) => b.until - a.until)
    .slice(0, CARRY_MAX);
  const secure = doc.location?.protocol === 'https:' ? '; Secure' : '';
  const value = kept.map((c) => `${c.id}.${c.manageToken}.${Math.ceil(c.until / 1000).toString(36)}`).join('~');
  try {
    doc.cookie =
      kept.length > 0
        ? `${CARRY_COOKIE}=${value}; Path=/; Max-Age=${CARRY_MAX_AGE_DAYS * 86_400}; SameSite=Strict${secure}`
        : `${CARRY_COOKIE}=; Path=/; Max-Age=0; SameSite=Strict${secure}`;
  } catch {
    // Cookies are off: the app on the Home Screen starts with its own list instead.
  }
}

/** Carries a booking into an app added to the Home Screen later. */
export function carryAppointment(id: string, manageToken: string, end: string, now: Date = new Date()): void {
  if (isDemo() || !ID_RE.test(id) || !MANAGE_TOKEN_RE.test(manageToken)) return;
  const until = new Date(end).getTime() + KEEP_DAYS * 86_400_000;
  if (!Number.isFinite(until)) return;
  writeCarried([...carriedAppointments(now).filter((c) => c.id !== id), { id, manageToken, until }], now);
}

/**
 * Carries every appointment listed here, with those already carried: when the site opens, so the
 * cookie is fresh whenever someone adds the site to the Home Screen (Safari lets a cookie that
 * the page wrote last a week at most), and appointments booked before there was a cookie go too.
 */
export function carryAppointments(list: SavedAppointment[], now: Date = new Date()): void {
  if (isDemo()) return;
  const carried = carriedAppointments(now);
  if (list.length === 0 && carried.length === 0) return;
  const listed = list
    .filter((s) => ID_RE.test(s.id) && MANAGE_TOKEN_RE.test(s.manageToken))
    .map((s) => ({ id: s.id, manageToken: s.manageToken, until: new Date(s.appointment.end).getTime() + KEEP_DAYS * 86_400_000 }))
    .filter((c) => Number.isFinite(c.until));
  const ids = new Set(listed.map((c) => c.id));
  writeCarried([...listed, ...carried.filter((c) => !ids.has(c.id))], now);
}

/** No longer carried: removed from the list here, or unknown to the shop. */
export function dropCarried(id: string, now: Date = new Date()): void {
  const list = carriedAppointments(now);
  if (list.some((c) => c.id === id)) writeCarried(list.filter((c) => c.id !== id), now);
}

export function forgetCarried(): void {
  writeCarried([], new Date());
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
