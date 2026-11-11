// The demo version's shop, in the browser: the same interface as the API client
// (src/api/http.ts), answering like the shop's server, and never touching the
// network. Modeled on the apps' FakeShopAPI (IzzyClipz/Services/FakeShopAPI.swift):
//
// - The catalog is the server's own data/catalog.json, built into the demo: the
//   shop's real services, prices, barbers and hours.
// - Open times come from the shop's hours, slot interval, lead time and booking
//   window, on the shop's clock (its time zone, with the real time), so daylight
//   saving changes are handled like on the server.
// - Every barber already has two or three sample bookings each open day, the same
//   every time that day is shown, so some times are taken like on a real day.
// - Bookings and cancellations are kept in this browser's localStorage, so they're
//   still there after a reload, with the server's rules: a retry with the same
//   manage token gets the same appointment back, a number can hold 3 upcoming
//   appointments, cancelling works until the start, and inside the late-cancellation
//   window of a booking with a card on file the client is asked first.
// - What's kept is the appointment (service, barber, time, status) and its manage
//   token, never the client's name, number, email or note: a computer can be shared.
//   Only a scrambled code of the number is kept, for the 3-per-number rule. "Forget
//   me" on My appointments clears it all (forgetHere).
// - No-show protection is off, as on the shop's server until the owner turns it
//   on: no card is needed, and Stripe is never involved.
// - Reviews are samples, and say so.

import catalogData from '../../../data/catalog.json';
import { ApiError, ErrorCode } from '../api/errors';
import type { Api } from '../api/http';
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
  Offering,
  Reviews,
  SavedCard,
} from '../api/types';
import { cancelledLate, lateCancelWarning } from '../lib/lateCancel';
import { charLength, emailProblem, parseUSPhone, toE164 } from '../lib/phone';
import { addDays, clockMinutes, daysBetween, localDate, parseDate, weekdayOf, zonedInstant } from '../lib/shopTime';
import { DEMO_STORE_KEY, readJSON, removeKey, writeJSON } from '../lib/storage';
import { isToken } from '../lib/tokens';
import { sampleReviews } from './samples';

/** The shop's real catalog: the server's data/catalog.json, as GET /api/catalog answers it. */
export const DEMO_CATALOG = catalogData as unknown as Catalog;

/** Where the demo keeps the bookings made in it (this browser only). */
export { DEMO_STORE_KEY };
/** The store's layout: 2 keeps no name, number, email or note. */
const STORE_VERSION = 2;

/** The server's limits (server/src/appointments.ts and booking.ts). */
export const MAX_UPCOMING_PER_PHONE = 3;
export const MAX_AVAILABILITY_DAYS = 31;
/** A booking that ended this long ago is forgotten, so the demo's storage doesn't grow for ever. */
const KEEP_DAYS = 60;
/** How long each sample booking is. */
const SAMPLE_MINUTES = 60;

/** An appointment as the demo keeps it: without the client's name, number, email and note. */
export type KeptAppointment = Omit<Appointment, 'customer' | 'note'>;

/** A booking made in the demo, as the server would keep it, less the client's own details. */
export interface DemoBooking {
  appointment: KeptAppointment;
  /** The manage token it was booked with: looking it up and cancelling it need it. */
  manageToken: string;
  /** Booked for "Any barber", so the demo picked the barber. */
  anyBarber: boolean;
  /** A scrambled code of the client's number (never the number), for the 3-per-number rule and retries. */
  phoneCode: string;
}

/** The client's details in a later answer: the demo doesn't keep them, and the site never shows them back. */
const NOT_KEPT = { name: '', phone: '', email: null };

function asAnswered(appointment: KeptAppointment): Appointment {
  return { ...appointment, customer: { ...NOT_KEPT }, note: null };
}

/** The appointment without the client's own details, whatever was handed in. */
function kept(appointment: KeptAppointment | Appointment): KeptAppointment {
  const { customer: _customer, note: _note, ...rest } = appointment as Partial<Appointment> & KeptAppointment;
  return rest;
}

/**
 * A scrambled code of a number (cyrb53, 53 bits), so the demo can count a number's bookings
 * without keeping the number itself.
 */
export function phoneCode(e164: string): string {
  const text = `izzy-demo|${e164}`;
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16).padStart(14, '0');
}

export interface DemoOptions {
  /** The real clock, unless a test sets its own. */
  now?: () => Date;
  /** How long each answer takes, so loading states show for a moment like on a real network. */
  latencyMs?: number;
  catalog?: Catalog;
}

/** Busy time for a barber: a sample booking or one made in the demo. Milliseconds. */
interface Busy {
  barberId: string;
  start: number;
  end: number;
}

// --------------------------------------------------------------------- Errors

const fail = (code: string, message: string, status: number) => new ApiError(code, message, status);
const invalid = (message: string) => fail(ErrorCode.invalidRequest, message, 400);
const notFound = () => fail(ErrorCode.notFound, "We couldn't find that appointment.", 404);
const slotTaken = () => fail(ErrorCode.slotTaken, 'Someone just booked that time. Pick another.', 409);
const notOnMenu = () => invalid("That service isn't on the menu any more. Pick another.");

// The server's input rules (server/src/validation.ts).
const CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;
const CONTROL_CHARS_EXCEPT_NEWLINES = /[\u0000-\u0009\u000b\u000c\u000e-\u001f\u007f-\u009f\u2028\u2029]/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// ---------------------------------------------------------------------- Time

/** "2026-11-02T18:00:00Z": the contract's format. */
function iso(instant: Date | number): string {
  return new Date(instant).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function isDate(text: string): boolean {
  if (!DATE_RE.test(text)) return false;
  const { year, month, day } = parseDate(text);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/**
 * The start times on `date` for an appointment of `durationMinutes`, before any bookings: every
 * slot interval from opening, ending by closing, at least the lead time from now, and only
 * today through the end of the booking window. The server's `gridStarts`.
 */
export function gridStarts(catalog: Catalog, date: string, durationMinutes: number, now: Date): Date[] {
  const zone = catalog.timeZone;
  const today = localDate(now, zone);
  if (date < today || date > addDays(today, catalog.windowDays)) return [];
  const hours = catalog.hours[String(weekdayOf(date))];
  if (!hours) return [];
  const opens = clockMinutes(hours.opens);
  const closes = clockMinutes(hours.closes);
  const closesAt = zonedInstant(date, closes, zone);
  if (!closesAt) return [];
  const earliest = now.getTime() + catalog.leadTimeMinutes * 60_000;
  const starts: Date[] = [];
  for (let minutes = opens; minutes < closes; minutes += catalog.slotIntervalMinutes) {
    const start = zonedInstant(date, minutes, zone);
    if (!start) continue;
    if (start.getTime() + durationMinutes * 60_000 > closesAt.getTime()) break;
    if (start.getTime() >= earliest) starts.push(start);
  }
  return starts;
}

// ------------------------------------------------------------ Sample bookings

/** A small random number generator that gives the same numbers for the same text. */
function seededRandom(text: string): () => number {
  let hash = 2166136261;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  let state = hash >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
}

/**
 * The sample bookings on a shop day: two or three an hour long for each barber, on the half
 * hour inside opening hours, never overlapping. The same every time that day is shown.
 */
export function sampleBookings(catalog: Catalog, date: string): Busy[] {
  const hours = catalog.hours[String(weekdayOf(date))];
  if (!hours) return [];
  const opens = clockMinutes(hours.opens);
  const lastStart = clockMinutes(hours.closes) - SAMPLE_MINUTES;
  const starts: number[] = [];
  for (let minutes = opens; minutes <= lastStart; minutes += 30) starts.push(minutes);
  if (starts.length === 0) return [];
  return catalog.barbers.flatMap((barber) => {
    const random = seededRandom(`${date}|${barber.id}`);
    const count = 2 + Math.floor(random() * 2);
    const picked: number[] = [];
    for (let tries = 0; picked.length < count && tries < 40; tries += 1) {
      const minutes = starts[Math.floor(random() * starts.length)]!;
      if (picked.every((other) => Math.abs(other - minutes) >= SAMPLE_MINUTES)) picked.push(minutes);
    }
    return picked.flatMap((minutes) => {
      const start = zonedInstant(date, minutes, catalog.timeZone);
      return start ? [{ barberId: barber.id, start: start.getTime(), end: start.getTime() + SAMPLE_MINUTES * 60_000 }] : [];
    });
  });
}

// ---------------------------------------------------------------- The store

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isDemoBooking(value: unknown): value is DemoBooking {
  if (!isObject(value) || typeof value.manageToken !== 'string' || typeof value.anyBarber !== 'boolean' || typeof value.phoneCode !== 'string') {
    return false;
  }
  const a = value.appointment;
  return (
    isObject(a) &&
    typeof a.id === 'string' &&
    typeof a.start === 'string' &&
    typeof a.end === 'string' &&
    typeof a.status === 'string' &&
    typeof a.barberId === 'string'
  );
}

/**
 * The bookings made in the demo, kept in localStorage. Where this browser keeps no site data
 * (some private windows), they're kept in memory instead, until the page closes.
 */
class DemoStore {
  private memory: DemoBooking[] = [];
  private inMemory = false;

  load(now: Date): DemoBooking[] {
    let list = this.memory;
    if (!this.inMemory) {
      const stored = readJSON('local', DEMO_STORE_KEY);
      list = isObject(stored) && stored.version === STORE_VERSION && Array.isArray(stored.bookings) ? stored.bookings.filter(isDemoBooking) : [];
    }
    const cutoff = now.getTime() - KEEP_DAYS * 86_400_000;
    return list
      .filter((booking) => new Date(booking.appointment.end).getTime() >= cutoff)
      .map((booking) => ({ ...booking, appointment: kept(booking.appointment) }));
  }

  save(list: DemoBooking[]): void {
    const clean = list.map((booking) => ({ ...booking, appointment: kept(booking.appointment) }));
    this.memory = clean;
    if (!this.inMemory && !writeJSON('local', DEMO_STORE_KEY, { version: STORE_VERSION, bookings: clean })) this.inMemory = true;
  }

  /** "Forget me": every booking made here, gone from this browser. */
  clear(): void {
    this.memory = [];
    removeKey('local', DEMO_STORE_KEY);
  }
}

// --------------------------------------------------------------------- Rules

interface Resolved {
  offerings: Offering[];
  anyBarber: boolean;
}

/** One barber's menu item, or the service with whichever barber is free first. The server's `resolveTarget`. */
function resolveTarget(catalog: Catalog, target: BookingTarget): Resolved {
  if ('offeringId' in target) {
    const offering = catalog.offerings.find((o) => o.id === target.offeringId);
    if (!offering) throw notOnMenu();
    return { offerings: [offering], anyBarber: false };
  }
  if (!catalog.services.some((s) => s.id === target.serviceId)) throw notOnMenu();
  const entry = catalog.firstAvailable.find((f) => f.serviceId === target.serviceId);
  if (!entry) throw invalid('This service needs a specific barber. Pick one to see their times.');
  const offerings = entry.offeringIds.flatMap((id) => catalog.offerings.filter((o) => o.id === id));
  return { offerings, anyBarber: true };
}

function busyFrom(bookings: DemoBooking[]): Busy[] {
  return bookings
    .filter((b) => b.appointment.status === 'booked' || b.appointment.status === 'completed')
    .map((b) => ({ barberId: b.appointment.barberId, start: Date.parse(b.appointment.start), end: Date.parse(b.appointment.end) }));
}

function isFree(busy: Busy[], barberId: string, start: number, end: number): boolean {
  return !busy.some((b) => b.barberId === barberId && b.start < end && b.end > start);
}

/** Why a customer can't book `start` for `offering`, ignoring other bookings. The server's `checkStart`. */
function startProblem(catalog: Catalog, offering: Offering, start: Date, now: Date): ApiError | null {
  const zone = catalog.timeZone;
  const day = localDate(start, zone);
  const lastDay = addDays(localDate(now, zone), catalog.windowDays);
  if (start.getTime() < now.getTime()) return fail(ErrorCode.tooSoon, 'That time has already passed. Pick another.', 422);
  if (start.getTime() < now.getTime() + catalog.leadTimeMinutes * 60_000) {
    return fail(ErrorCode.tooSoon, `That's too soon. Pick a time at least ${catalog.leadTimeMinutes} minutes from now.`, 422);
  }
  if (day > lastDay) return fail(ErrorCode.tooFar, `We take bookings up to ${catalog.windowDays} days ahead. Pick an earlier day.`, 422);
  if (!catalog.hours[String(weekdayOf(day))]) return fail(ErrorCode.outsideHours, "We're closed that day. Pick another day.", 422);
  const onGrid = gridStarts(catalog, day, offering.durationMinutes, now).some((s) => s.getTime() === start.getTime());
  if (!onGrid) return fail(ErrorCode.outsideHours, "That isn't one of our booking times. Pick a time from the list.", 422);
  return null;
}

/** The server's rule for a retry: the same target asked for the same way, the same start and the same number. */
function sameBooking(booking: DemoBooking, target: BookingTarget, start: Date, phone: string): boolean {
  const a = booking.appointment;
  if (Date.parse(a.start) !== start.getTime() || booking.phoneCode !== phoneCode(phone)) return false;
  return 'offeringId' in target ? !booking.anyBarber && a.offeringId === target.offeringId : booking.anyBarber && a.serviceId === target.serviceId;
}

interface CleanBooking {
  start: Date;
  name: string;
  phone: string;
  email: string | null;
  note: string | null;
}

/** The booking's fields as the server takes them, or a 400 that says what's wrong. */
function cleanBooking(appointment: NewAppointment): CleanBooking {
  const start = new Date(appointment.start);
  if (Number.isNaN(start.getTime())) throw invalid('Times must be ISO 8601, like 2026-11-02T18:00:00Z.');
  const name = appointment.customer.name.trim();
  if (name === '') throw invalid('Enter your name.');
  if (charLength(name) > 60) throw invalid('Keep the name to 60 characters or fewer.');
  if (CONTROL_CHARS.test(name)) throw invalid('The name has characters we can’t use.');
  const digits = parseUSPhone(appointment.customer.phone);
  if (!digits) throw invalid('Enter a US mobile number, like (442) 341-3053.');
  const email = appointment.customer.email?.trim() || null;
  if (email !== null && emailProblem(email)) throw invalid('Enter a valid email address.');
  const note = appointment.note?.trim() || null;
  if (note !== null && charLength(note) > 300) throw invalid('Keep the note to 300 characters or fewer.');
  if (note !== null && CONTROL_CHARS_EXCEPT_NEWLINES.test(note)) throw invalid('The note has characters we can’t use.');
  return { start, name, phone: toE164(digits), email, note };
}

function newId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** No card needed: no-show protection is off in the demo, as on the server until the owner turns it on. */
export const NOT_REQUIRED: NoShowPolicy = {
  required: false,
  minFeeCents: null,
  maxFeeCents: null,
  policyText: null,
  lateCancelWindowMinutes: null,
  warning: null,
};

/** Waits like a request on the network would, and stops when the page no longer wants the answer. */
function pause(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const aborted = () => new DOMException('The request was cancelled.', 'AbortError');
    if (signal?.aborted) {
      reject(aborted());
      return;
    }
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        reject(aborted());
      },
      { once: true },
    );
  });
}

// ----------------------------------------------------------------- The API

/** The demo's stand-in for the shop's server, with the API client's own interface. */
export function createDemoApi(options: DemoOptions = {}): Api {
  const catalog = options.catalog ?? DEMO_CATALOG;
  const clock = options.now ?? (() => new Date());
  const latency = options.latencyMs ?? 150;
  const zone = catalog.timeZone;
  const store = new DemoStore();
  const teamRank = (id: string) => catalog.barbers.findIndex((b) => b.id === id);

  /** Bookings for each barber on the shop day of `start`, sample ones included (for "Any barber"). */
  function bookingsThatDay(bookings: DemoBooking[], barberId: string, start: Date): number {
    const day = localDate(start, zone);
    const samples = sampleBookings(catalog, day).filter((b) => b.barberId === barberId).length;
    const booked = busyFrom(bookings).filter((b) => b.barberId === barberId && localDate(new Date(b.start), zone) === day).length;
    return samples + booked;
  }

  function makeAppointment(offering: Offering, booking: CleanBooking, now: Date): Appointment {
    const service = catalog.services.find((s) => s.id === offering.serviceId);
    const barber = catalog.barbers.find((b) => b.id === offering.barberId);
    return {
      id: newId(),
      offeringId: offering.id,
      serviceId: offering.serviceId,
      serviceName: service?.name ?? 'Appointment',
      barberId: offering.barberId,
      barberName: barber?.name ?? 'Your barber',
      start: iso(booking.start),
      end: iso(booking.start.getTime() + offering.durationMinutes * 60_000),
      durationMinutes: offering.durationMinutes,
      priceLabel: offering.priceLabel,
      status: 'booked',
      cancelledBy: null,
      payment: { status: 'unpaid', amountCents: null, paidAt: null },
      customer: { name: booking.name, phone: booking.phone, email: booking.email },
      note: booking.note,
      createdAt: iso(now),
      card: null,
      noShowFee: null,
    };
  }

  const api: Api = {
    async catalog(signal?: AbortSignal): Promise<Catalog> {
      await pause(latency, signal);
      return structuredClone(catalog);
    },

    async reviews(signal?: AbortSignal): Promise<Reviews> {
      await pause(latency, signal);
      return sampleReviews(catalog.shop, clock());
    },

    async availability(target: BookingTarget, from: string, days: number, signal?: AbortSignal): Promise<Availability> {
      await pause(latency, signal);
      if (!Number.isInteger(days) || days < 1 || days > MAX_AVAILABILITY_DAYS) {
        throw invalid(`days must be a whole number from 1 to ${MAX_AVAILABILITY_DAYS}.`);
      }
      if (!isDate(from)) throw invalid('Dates must look like 2026-11-02.');
      const now = clock();
      if (Math.abs(daysBetween(localDate(now, zone), from)) > 366) throw invalid('from must be within a year of today.');
      const { offerings } = resolveTarget(catalog, target);
      const booked = busyFrom(store.load(now));
      return {
        timeZone: zone,
        days: Array.from({ length: days }, (_, i) => {
          const date = addDays(from, i);
          const busy = [...sampleBookings(catalog, date), ...booked];
          const free = new Map<number, Set<string>>();
          for (const offering of offerings) {
            for (const start of gridStarts(catalog, date, offering.durationMinutes, now)) {
              const begins = start.getTime();
              if (!isFree(busy, offering.barberId, begins, begins + offering.durationMinutes * 60_000)) continue;
              const barbers = free.get(begins) ?? new Set<string>();
              barbers.add(offering.barberId);
              free.set(begins, barbers);
            }
          }
          const slots = [...free.entries()]
            .sort(([a], [b]) => a - b)
            .map(([begins, barbers]) => ({ start: iso(begins), barberIds: [...barbers].sort((a, b) => teamRank(a) - teamRank(b)) }));
          return { date, slots };
        }),
      };
    },

    async noShowPolicy(target: BookingTarget, signal?: AbortSignal): Promise<NoShowPolicy> {
      await pause(latency, signal);
      resolveTarget(catalog, target);
      return { ...NOT_REQUIRED };
    },

    async startCardCheckout(target: BookingTarget, _cardToken: string): Promise<CardCheckout> {
      await pause(latency);
      resolveTarget(catalog, target);
      throw invalid("This booking doesn't need a card. Go ahead and book.");
    },

    async saveCard(_sessionId: string, _cardToken: string): Promise<SavedCard> {
      await pause(latency);
      // No card page was ever opened, so there's no card to save.
      throw fail(ErrorCode.notFound, "We couldn't find that card. Add it again.", 404);
    },

    /**
     * DELETE /api/cards, answered as the server would, with no request: the demo never saves a card
     * (no-show protection is off), so whatever key this browser holds has no card behind it.
     */
    async deleteCard(cardToken: string): Promise<CardDeletion> {
      await pause(latency);
      if (!isToken(cardToken)) throw invalid('Send the card token as X-Card-Token.');
      throw fail(ErrorCode.notFound, "We couldn't find that card.", 404);
    },

    async book(appointment: NewAppointment, manageToken: string, _cardToken?: string): Promise<BookingConfirmation> {
      await pause(latency);
      if (!isToken(manageToken)) throw invalid('X-Manage-Token must be 32 random bytes in base64url (43 characters).');
      const booking = cleanBooking(appointment);
      const now = clock();
      const bookings = store.load(now);

      // A retry of a booking that went through: the same appointment, as it is now, before any time rules.
      const earlier = bookings.find((b) => b.manageToken === manageToken);
      if (earlier) {
        if (!sameBooking(earlier, appointment.target, booking.start, booking.phone)) throw invalid('That booking token was already used.');
        return { appointment: asAnswered(earlier.appointment), manageToken };
      }

      const { offerings, anyBarber } = resolveTarget(catalog, appointment.target);
      const problems = offerings.map((o) => startProblem(catalog, o, booking.start, now));
      const candidates = offerings.filter((_, i) => problems[i] === null);
      if (candidates.length === 0) throw problems[0] ?? slotTaken();

      const code = phoneCode(booking.phone);
      const upcoming = bookings.filter(
        (b) => b.phoneCode === code && b.appointment.status === 'booked' && Date.parse(b.appointment.start) > now.getTime(),
      );
      if (upcoming.length >= MAX_UPCOMING_PER_PHONE) {
        throw fail(
          ErrorCode.rateLimited,
          `This number already has ${MAX_UPCOMING_PER_PHONE} upcoming appointments. Cancel one, or call the shop to book more.`,
          429,
        );
      }

      // Free barbers only; for "Any barber", the one with the fewest bookings that day, then team order.
      const busy = [...sampleBookings(catalog, localDate(booking.start, zone)), ...busyFrom(bookings)];
      const begins = booking.start.getTime();
      const free = candidates
        .filter((o) => isFree(busy, o.barberId, begins, begins + o.durationMinutes * 60_000))
        .sort(
          (a, b) =>
            bookingsThatDay(bookings, a.barberId, booking.start) - bookingsThatDay(bookings, b.barberId, booking.start) ||
            teamRank(a.barberId) - teamRank(b.barberId),
        );
      const offering = free[0];
      if (!offering) throw slotTaken();

      // The answer has the client's details, as the shop's would; what's kept doesn't.
      const created = makeAppointment(offering, booking, now);
      store.save([...bookings, { appointment: kept(created), manageToken, anyBarber, phoneCode: code }]);
      return { appointment: created, manageToken };
    },

    async appointment(id: string, manageToken: string, signal?: AbortSignal): Promise<Appointment> {
      await pause(latency, signal);
      if (!manageToken) throw fail(ErrorCode.unauthorized, 'This appointment needs its manage token.', 401);
      const found = store.load(clock()).find((b) => b.appointment.id === id && b.manageToken === manageToken);
      // Same answer for "no such appointment" and "wrong token", like the server.
      if (!found) throw notFound();
      return asAnswered(found.appointment);
    },

    async cancel(id: string, manageToken: string, acceptLateCancelFee = false): Promise<Appointment> {
      await pause(latency);
      if (!manageToken) throw fail(ErrorCode.unauthorized, 'This appointment needs its manage token.', 401);
      const now = clock();
      const bookings = store.load(now);
      const index = bookings.findIndex((b) => b.appointment.id === id && b.manageToken === manageToken);
      const entry = bookings[index];
      if (!entry) throw notFound();
      const current = entry.appointment;
      const started = Date.parse(current.start) <= now.getTime();

      if (!started && current.status === 'booked') {
        // Inside the agreed late-cancellation window the client is told first, and nothing changes.
        const warning = lateCancelWarning(current, now);
        if (warning && !acceptLateCancelFee) throw fail(ErrorCode.lateCancelFee, warning, 409);
        const fee = current.noShowFee;
        const firstAsked = fee?.customerCancelledAt ?? iso(now);
        const cancelled: KeptAppointment = {
          ...current,
          status: 'cancelled',
          cancelledBy: 'customer',
          noShowFee: fee
            ? {
                ...fee,
                customerCancelledAt: firstAsked,
                reason: cancelledLate(new Date(current.start), new Date(firstAsked), fee.lateCancelWindowMinutes, new Date(current.createdAt))
                  ? 'lateCancel'
                  : null,
              }
            : null,
        };
        store.save(bookings.map((b, i) => (i === index ? { ...b, appointment: cancelled } : b)));
        return asAnswered(cancelled);
      }

      // Asked in time, but it isn't booked any more: like the server, the request still counts.
      if (!started && current.noShowFee && current.noShowFee.customerCancelledAt === null) {
        const asked = { ...current, noShowFee: { ...current.noShowFee, customerCancelledAt: iso(now) } };
        store.save(bookings.map((b, i) => (i === index ? { ...b, appointment: asked } : b)));
      }
      if (current.status === 'cancelled') throw fail(ErrorCode.notCancellable, 'This appointment is already cancelled.', 409);
      if (current.status !== 'booked') throw fail(ErrorCode.notCancellable, "This appointment can't be cancelled any more.", 409);
      throw fail(ErrorCode.notCancellable, 'This appointment has already started. Call the shop if you need help.', 409);
    },

    /** "Forget me on this computer": the bookings made in the demo go too, from this browser. */
    forgetHere(): void {
      store.clear();
    },
  };
  return api;
}

/** The demo build's API: the real clock, and answers that take a moment like the network's. */
export const demoApi: Api = createDemoApi();
