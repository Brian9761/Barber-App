// The Business demo's shop, in the browser: the same interface as the owner API client
// (src/business/api/http.ts), answering like the shop's server, and never touching the
// network. Modeled on the owner app's fakes (IzzyClipzBusiness/Fakes/FakeServer.swift):
//
// - Sign in is one button: the demo needs no code from the app.
// - The schedule and sales are the sample shop (./samples.ts): today's and the coming
//   days' bookings for the five barbers, and 8 weeks of history, so analytics has
//   something to show. The shop's real catalog (the server's data/catalog.json) gives the
//   services, prices, barbers and hours; the products are samples.
// - Checking out, voiding, marking and fees follow the server's rules (server/src/sales.ts,
//   appointments.ts, noshowfee.ts): a checked-out appointment can't be reopened, cancelled
//   or marked a no-show until its sale is voided; a no-show with a card on file is marked
//   only once it has started; an Idempotency-Key sent again gets the same sale back.
// - Analytics are worked out from the demo's own data with the server's own definitions
//   (./facts.ts, ./analytics.ts).
// - "Connect Stripe" connects after a short pretend step; the no-show settings save.
// - Everything stays in this browser (localStorage `izzy.demo.business.v1`), and "Reset the
//   demo" brings the sample shop back as it was.
//
// A day the owner changes something on is kept whole in the store from then on, as it is
// at that moment; the other days are worked out from the samples each time.

import catalogData from '../../../../data/catalog.json';
import { ApiError } from '../../api/errors';
import type { Catalog } from '../../api/types';
import type { OwnerApi } from '../../business/api/http';
import { ruleFeeCase, type FeeReason } from '../../business/lib/fees';
import { session } from '../../business/session';
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
  SaleItem,
  SalesDay,
  SignedIn,
  StripeConnection,
  StripeConnectLink,
  TimeOff,
  VoidedSale,
} from '../../business/types';
import { money, windowLabel } from '../../lib/format';
import { addDays, daysBetween, localDate, zonedInstant } from '../../lib/shopTime';
import { DEMO_BUSINESS_KEY, readJSON, removeKey, writeJSON } from '../../lib/storage';
import { newToken } from '../../lib/tokens';
import { demoAnalytics } from './facts';
import { dayId, dayOfId, SAMPLE_PRODUCTS, sampleDay, sampleDays, type DayData, type DemoAppointment } from './samples';

/** Where the Business demo keeps what's changed in it (this browser only). */
export { DEMO_BUSINESS_KEY };
const STORE_VERSION = 1;
/** How long a computer stays signed in, like the server. */
const SESSION_DAYS = 30;
/** The pretend step of connecting Stripe. */
const CONNECT_STEP_MS = 1200;

export const DEMO_CATALOG = catalogData as unknown as Catalog;

const DEFAULT_NO_SHOW: NoShowSettings = {
  enabled: false,
  feeMode: 'percent',
  percent: 100,
  flatCents: 2000,
  lateCancelEnabled: true,
  lateCancelWindowMinutes: 60,
};

interface DemoSession extends ComputerSession {
  /** The token this computer signs in with (this browser's own; nothing leaves it). */
  token: string | null;
}

interface Store {
  version: number;
  /** When the demo was opened first (or reset): appointments that ended before it, or before today, have their outcome. */
  startedAt: string;
  /** Days the owner changed something on, kept whole from then on. */
  days: Record<string, DayData>;
  /** Idempotency-Key → the sale it recorded. */
  keys: Record<string, string>;
  /** The products once changed; null for the samples. */
  products: Product[] | null;
  noShowSettings: NoShowSettings;
  stripe: { connectedAt: string | null };
  /** Computers signed in. */
  sessions: DemoSession[];
}

// --------------------------------------------------------------------- Errors

const fail = (code: string, message: string, status: number) => new ApiError(code, message, status);
const invalid = (message: string) => fail('invalid_request', message, 400);
const appointmentNotFound = () => fail('not_found', "We couldn't find that appointment.", 404);
const productNotFound = () => fail('not_found', "We couldn't find that product. It may have been deleted.", 404);

const CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_SALE_CENTS = 1_000_000;

const VOIDED_MESSAGE = 'The sale was voided, so it no longer counts in your sales.';
const VOIDED_CARD_MESSAGE = `${VOIDED_MESSAGE} Voiding doesn't refund the card: refunds are made in the Stripe Dashboard.`;

function iso(ms: number | Date): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function charLength(text: string): number {
  return [...text].length;
}

function isDate(text: string): boolean {
  if (!DATE_RE.test(text)) return false;
  const [y, m, d] = text.split('-').map(Number) as [number, number, number];
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
}

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

/** An appointment as the API answers it: without what only the demo keeps, and with its fee's reason now. */
function answered(appointment: DemoAppointment): OwnerAppointment {
  const { priceCents: _price, cardPayment: _card, ...rest } = appointment;
  const fee = rest.noShowFee;
  if (!fee) return structuredClone(rest);
  let reason: FeeReason | null = fee.status !== 'none' && fee.reason ? fee.reason : null;
  if (reason === null) {
    const found = ruleFeeCase(
      rest.status,
      rest.cancelledBy,
      new Date(rest.start),
      fee.customerCancelledAt ? new Date(fee.customerCancelledAt) : null,
      fee.lateCancelWindowMinutes,
    );
    reason = found.kind === 'chargeable' ? found.reason : null;
  }
  return structuredClone({ ...rest, noShowFee: { ...fee, reason } });
}

function isStore(value: unknown): value is Store {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Partial<Store>;
  return (
    v.version === STORE_VERSION &&
    typeof v.startedAt === 'string' &&
    typeof v.days === 'object' &&
    v.days !== null &&
    typeof v.keys === 'object' &&
    v.keys !== null &&
    Array.isArray(v.sessions) &&
    typeof v.noShowSettings === 'object' &&
    v.noShowSettings !== null &&
    typeof v.stripe === 'object' &&
    v.stripe !== null
  );
}

export interface DemoOwnerOptions {
  /** The real clock, unless a test sets its own. */
  now?: () => Date;
  /** How long each answer takes, so loading states show for a moment like on a real network. */
  latencyMs?: number;
  catalog?: Catalog;
  /** How long "Connect Stripe" pretends to take. */
  connectStepMs?: number;
}

/** The Business demo's stand-in for the shop's server, with the owner API client's own interface. */
export function createDemoOwnerApi(options: DemoOwnerOptions = {}): OwnerApi {
  const catalog = options.catalog ?? DEMO_CATALOG;
  const clock = options.now ?? (() => new Date());
  const latency = options.latencyMs ?? 120;
  const connectStep = options.connectStepMs ?? CONNECT_STEP_MS;
  const zone = catalog.timeZone;

  let memory: Store | null = null;
  let inMemoryOnly = false;

  function fresh(now: Date, sessions: DemoSession[] = []): Store {
    return {
      version: STORE_VERSION,
      startedAt: iso(now),
      days: {},
      keys: {},
      products: null,
      noShowSettings: { ...DEFAULT_NO_SHOW },
      stripe: { connectedAt: null },
      sessions,
    };
  }

  function load(): Store {
    if (inMemoryOnly && memory) return memory;
    const stored = readJSON('local', DEMO_BUSINESS_KEY);
    if (isStore(stored)) {
      memory = stored;
      return stored;
    }
    if (memory) return memory;
    const created = fresh(clock());
    save(created);
    return created;
  }

  function save(store: Store): void {
    memory = store;
    if (!inMemoryOnly && !writeJSON('local', DEMO_BUSINESS_KEY, store)) inMemoryOnly = true;
  }

  /** Writes a store that must be kept (a photo, say): fails loudly when this browser's storage is full. */
  function saveOrFail(store: Store): void {
    memory = store;
    if (inMemoryOnly) return;
    if (!writeJSON('local', DEMO_BUSINESS_KEY, store)) {
      throw invalid("The demo couldn't keep that: this browser's storage is full. Try a smaller photo, or reset the demo in Settings.");
    }
  }

  function today(): string {
    return localDate(clock(), zone);
  }

  /** Appointments that ended before this have their outcome: before the demo was opened, or before today began. */
  function historyBefore(store: Store): number {
    const startOfToday = zonedInstant(today(), 0, zone)?.getTime() ?? 0;
    return Math.max(Date.parse(store.startedAt), startOfToday);
  }

  function day(store: Store, date: string): DayData {
    return store.days[date] ?? sampleDay({ catalog, today: today(), historyBefore: historyBefore(store) }, date);
  }

  /** The day kept whole in the store, to change it. */
  function keep(store: Store, date: string): DayData {
    const existing = store.days[date];
    if (existing) return existing;
    const kept = structuredClone(day(store, date));
    store.days[date] = kept;
    return kept;
  }

  function products(store: Store): Product[] {
    return store.products ?? SAMPLE_PRODUCTS.map((p) => ({ ...p }));
  }

  /** The session asking: the computer signed in here. Anyone else gets the server's 401. */
  function signedIn(store: Store): DemoSession {
    const token = session.token();
    const found = token ? store.sessions.find((s) => s.token === token && Date.parse(s.expiresAt) > clock().getTime()) : undefined;
    if (!found) {
      if (token) session.expire(token);
      throw fail('unauthorized', "That owner key isn't right. Check it and sign in again.", 401);
    }
    return found;
  }

  /** An appointment by id, wherever it is: the day is in its id. */
  function findAppointment(store: Store, id: string): { date: string; appointment: DemoAppointment } | null {
    const date = dayOfId(id);
    const dates = date ? [date] : Object.keys(store.days);
    for (const d of dates) {
      const appointment = day(store, d).appointments.find((a) => a.id === id);
      if (appointment) return { date: d, appointment };
    }
    return null;
  }

  function findSale(store: Store, id: string): { date: string; sale: Sale } | null {
    const date = dayOfId(id);
    const dates = date ? [date, ...Object.keys(store.days).filter((d) => d !== date)] : Object.keys(store.days);
    for (const d of dates) {
      const sale = day(store, d).sales.find((s) => s.id === id);
      if (sale) return { date: d, sale };
    }
    return null;
  }

  function sessionJSON(s: DemoSession, current: DemoSession | null): ComputerSession {
    return { id: s.id, name: s.name, createdAt: s.createdAt, lastUsedAt: s.lastUsedAt, expiresAt: s.expiresAt, current: s.id === current?.id };
  }

  function stripeJSON(store: Store): StripeConnection {
    const connected = store.stripe.connectedAt !== null;
    return connected
      ? {
          mode: 'connect',
          status: 'active',
          accountId: 'acct_demo',
          businessName: 'Izzy Clipz Barbershop',
          livemode: true,
          chargesEnabled: true,
          payoutsEnabled: true,
          detailsSubmitted: true,
          requirementsDue: 0,
          message: 'Connected. Card payments are on. Payouts to your bank are on.',
          dashboardUrl: 'https://dashboard.stripe.com/',
          checkedAt: store.stripe.connectedAt,
        }
      : {
          mode: 'connect',
          status: 'notConnected',
          accountId: null,
          businessName: null,
          livemode: null,
          chargesEnabled: false,
          payoutsEnabled: false,
          detailsSubmitted: false,
          requirementsDue: 0,
          message: 'Connect your Stripe account to take card payments in the app.',
          dashboardUrl: 'https://dashboard.stripe.com/',
          checkedAt: null,
        };
  }

  // ------------------------------------------------------------- Sales rules

  /** The server's `sameSale`: the same method, appointment, barber, client and items. */
  function sameSale(sale: Sale, body: NewSale): boolean {
    if (sale.method !== body.method || sale.appointmentId !== (body.appointmentId ?? null)) return false;
    if (body.barberId && body.barberId !== sale.barberId) return false;
    if (body.customerName && body.customerName !== sale.customerName) return false;
    if (sale.items.length !== body.items.length) return false;
    return body.items.every((item, i) => {
      const stored = sale.items[i];
      if (!stored || stored.kind !== item.kind || stored.quantity !== (item.quantity ?? 1)) return false;
      if (item.unitCents !== undefined && item.unitCents !== stored.unitCents) return false;
      if (item.kind === 'service') return stored.serviceId === item.serviceId;
      if (item.kind === 'product') return stored.productId === null || stored.productId === item.productId;
      return stored.name === item.name;
    });
  }

  function checkPrice(cents: unknown, message = 'Prices must be whole cents, from $0 to $10,000.'): number {
    if (typeof cents !== 'number' || !Number.isInteger(cents) || cents < 0 || cents > MAX_SALE_CENTS) throw invalid(message);
    return cents;
  }

  function checkQuantity(quantity: unknown): number {
    const q = quantity ?? 1;
    if (typeof q !== 'number' || !Number.isInteger(q) || q < 1 || q > 99) throw invalid('The quantity must be a whole number from 1 to 99.');
    return q;
  }

  /** The barber's one price for a service on the menu, or a 400 asking for the price. */
  function menuPrice(barberId: string, barberName: string, serviceId: string, serviceName: string): number {
    const prices = [...new Set(catalog.offerings.filter((o) => o.barberId === barberId && o.serviceId === serviceId).map((o) => o.priceCents))];
    if (prices.length === 1) return prices[0]!;
    if (prices.length === 0) throw invalid(`${barberName} doesn't offer ${serviceName}. Enter the price.`);
    throw invalid(`${barberName} has more than one price for ${serviceName}. Enter the price.`);
  }

  // --------------------------------------------------------------- The API

  const api: OwnerApi = {
    async signIn(_code: string, name: string): Promise<SignedIn> {
      await pause(latency);
      const now = clock();
      const store = load();
      const created: DemoSession = {
        id: dayId(`session|${now.getTime()}|${Math.random()}`, today()),
        name: name.trim().slice(0, 80) || 'Computer',
        createdAt: iso(now),
        lastUsedAt: iso(now),
        expiresAt: iso(now.getTime() + SESSION_DAYS * 86_400_000),
        current: true,
        token: newToken(),
      };
      // A sample of another computer signed in, so the list in Settings shows how it looks.
      const others =
        store.sessions.length === 0
          ? [
              {
                id: dayId('session|sample-ipad', addDays(today(), -3)),
                name: 'Safari on iPad (sample)',
                createdAt: iso(now.getTime() - 3 * 86_400_000),
                lastUsedAt: iso(now.getTime() - 26 * 3_600_000),
                expiresAt: iso(now.getTime() + 27 * 86_400_000),
                current: false,
                token: null,
              },
            ]
          : [];
      store.sessions = [...store.sessions.filter((s) => Date.parse(s.expiresAt) > now.getTime()), ...others, created];
      save(store);
      return { token: created.token!, session: sessionJSON(created, created) };
    },

    async signInWithKey(_key: string, name: string): Promise<SignedIn> {
      return api.signIn('', name);
    },

    async signOut(): Promise<void> {
      await pause(latency);
      const store = load();
      const current = signedIn(store);
      store.sessions = store.sessions.filter((s) => s.id !== current.id);
      save(store);
    },

    async appointments(date: string, signal?: AbortSignal): Promise<OwnerAppointment[]> {
      await pause(latency, signal);
      if (!isDate(date)) throw invalid('Dates must look like 2026-11-02.');
      const store = load();
      signedIn(store);
      return day(store, date).appointments.map(answered);
    },

    async timeOff(date: string, signal?: AbortSignal): Promise<TimeOff[]> {
      await pause(latency, signal);
      if (!isDate(date)) throw invalid('Dates must look like 2026-11-02.');
      signedIn(load());
      return [];
    },

    async setStatus(id: string, status: 'booked' | 'completed' | 'noShow' | 'cancelled'): Promise<OwnerAppointment> {
      await pause(latency);
      const store = load();
      signedIn(store);
      const found = findAppointment(store, id);
      if (!found) throw appointmentNotFound();
      const now = clock();
      const current = found.appointment;
      if (current.sale !== null && status !== 'completed') {
        throw fail('already_checked_out', 'This appointment was checked out. Void its sale first, then change it.', 409);
      }
      if (status === 'noShow' && current.card && Date.parse(current.start) > now.getTime()) {
        throw fail('not_started', 'You can mark a no-show once the appointment has started.', 409);
      }
      const kept = keep(store, found.date);
      const appointment = kept.appointments.find((a) => a.id === id)!;
      if (status === 'booked' || status === 'completed') {
        // Back on the schedule: only if no other booking of this barber took the time meanwhile.
        const start = Date.parse(appointment.start);
        const end = Date.parse(appointment.end);
        const taken = kept.appointments.some(
          (other) =>
            other.id !== id &&
            other.barberId === appointment.barberId &&
            (other.status === 'booked' || other.status === 'completed') &&
            Date.parse(other.start) < end &&
            Date.parse(other.end) > start,
        );
        if (taken && appointment.status !== 'booked' && appointment.status !== 'completed') {
          throw fail('slot_taken', 'Another appointment is booked at that time now, so this one can’t be restored.', 409);
        }
      }
      appointment.status = status;
      appointment.cancelledBy = status === 'cancelled' ? (appointment.cancelledBy ?? 'shop') : null;
      save(store);
      return answered(appointment);
    },

    async chargeFee(id: string): Promise<OwnerAppointment> {
      await pause(latency * 3);
      const store = load();
      signedIn(store);
      const found = findAppointment(store, id);
      if (!found) throw appointmentNotFound();
      const fee = found.appointment.noShowFee;
      if (fee?.status === 'charged') return answered(found.appointment);
      if (store.stripe.connectedAt === null) throw fail('stripe_not_configured', 'Connect Stripe in Settings to take card payments.', 503);
      if (!found.appointment.card || !fee) throw fail('not_chargeable', "This booking has no card on file, so there's no fee to charge.", 409);
      const now = clock();
      const appointmentNow = answered(found.appointment);
      const rule = ruleFeeCase(
        appointmentNow.status,
        appointmentNow.cancelledBy,
        new Date(appointmentNow.start),
        fee.customerCancelledAt ? new Date(fee.customerCancelledAt) : null,
        fee.lateCancelWindowMinutes,
      );
      if (rule.kind === 'refused') throw fail('not_chargeable', rule.message, 409);
      if (rule.reason === 'noShow' && Date.parse(appointmentNow.start) > now.getTime()) {
        throw fail('not_chargeable', "The appointment hasn't started yet, so it can't be a no-show.", 409);
      }
      const kept = keep(store, found.date);
      const appointment = kept.appointments.find((a) => a.id === id)!;
      // The demo's declined card: like Stripe's test card that ends in 0002.
      appointment.noShowFee =
        appointment.card?.last4 === '0002'
          ? { ...fee, status: 'declined', chargedAt: null, message: 'The card was declined. Ask the client to pay at the shop.', reason: rule.reason }
          : { ...fee, status: 'charged', chargedAt: iso(now), message: null, reason: rule.reason };
      save(store);
      return answered(appointment);
    },

    async sales(date: string, signal?: AbortSignal): Promise<SalesDay> {
      await pause(latency, signal);
      if (!isDate(date)) throw invalid('Dates must look like 2026-11-02.');
      const store = load();
      signedIn(store);
      const sales = [...day(store, date).sales].sort((a, b) => b.soldAt.localeCompare(a.soldAt) || b.id.localeCompare(a.id));
      const live = sales.filter((s) => s.voidedAt === null);
      return { date, sales: structuredClone(sales), totals: { totalCents: live.reduce((sum, s) => sum + s.totalCents, 0), count: live.length } };
    },

    async createSale(body: NewSale, idempotencyKey: string): Promise<Sale> {
      await pause(latency * 2);
      const store = load();
      signedIn(store);
      // A retry is answered first: its appointment is already checked out, by this very sale.
      const earlierId = store.keys[idempotencyKey];
      if (earlierId) {
        const earlier = findSale(store, earlierId);
        if (earlier) {
          if (!sameSale(earlier.sale, body)) throw invalid('That sale key was already used for another sale.');
          return structuredClone(earlier.sale);
        }
      }
      if ((body.method as string) === 'card') {
        throw invalid('Take card payments with Tap to Pay in the app. The sale is saved when the payment goes through.');
      }
      if (body.method !== 'cash' && body.method !== 'other') throw invalid('method must be cash or other.');
      if (!Array.isArray(body.items) || body.items.length === 0) throw invalid('Add at least one item.');
      if (body.items.length > 20) throw invalid('A sale can have at most 20 items.');

      let appointment: DemoAppointment | null = null;
      let appointmentDate: string | null = null;
      if (body.appointmentId) {
        const found = findAppointment(store, body.appointmentId);
        if (!found) throw appointmentNotFound();
        if (found.appointment.status === 'cancelled') {
          throw fail(
            'not_checkoutable',
            "This appointment was cancelled, so it can't be checked out. Reopen it first, or check out without the appointment.",
            409,
          );
        }
        if (found.appointment.status === 'noShow') {
          throw fail(
            'not_checkoutable',
            "This appointment was marked a no-show, so it can't be checked out. Reopen it first, or check out without the appointment.",
            409,
          );
        }
        if (found.appointment.sale !== null) throw fail('already_checked_out', 'This appointment was already checked out.', 409);
        appointment = found.appointment;
        appointmentDate = found.date;
      }

      const barberId = body.barberId || appointment?.barberId;
      if (!barberId) throw invalid('Pick the barber who gets credit for this sale.');
      const barber = catalog.barbers.find((b) => b.id === barberId);
      if (!barber) throw invalid("That barber isn't on the team. Pick who did the service.");

      const shelf = products(store);
      const items: SaleItem[] = body.items.map((input) => {
        const quantity = checkQuantity(input.quantity);
        const line = (fields: Omit<SaleItem, 'quantity' | 'totalCents'>): SaleItem => ({ ...fields, quantity, totalCents: fields.unitCents * quantity });
        if (input.kind === 'service') {
          const own = appointment !== null && input.serviceId === appointment.serviceId;
          const name = catalog.services.find((s) => s.id === input.serviceId)?.name ?? (own ? appointment?.serviceName : undefined);
          if (!name) throw invalid("That service isn't on the menu. Pick another, or add it as a custom item.");
          const price =
            input.unitCents !== undefined
              ? checkPrice(input.unitCents)
              : own && appointment
                ? appointment.priceCents
                : menuPrice(barber.id, barber.name, input.serviceId, name);
          return line({ kind: 'service', serviceId: input.serviceId, productId: null, name, unitCents: price });
        }
        if (input.kind === 'product') {
          const product = shelf.find((p) => p.id === input.productId);
          if (!product) throw productNotFound();
          const price = input.unitCents !== undefined ? checkPrice(input.unitCents) : product.priceCents;
          if (price === null) throw invalid(`${product.name} has no price. Enter the price.`);
          return line({ kind: 'product', serviceId: null, productId: product.id, name: product.name, unitCents: price });
        }
        const name = typeof input.name === 'string' ? input.name.trim() : '';
        if (name === '') throw invalid('Give the item a name, like Gift card.');
        if (charLength(name) > 80) throw invalid('Keep the item name to 80 characters or fewer.');
        if (CONTROL_CHARS.test(name)) throw invalid('The item name has characters we can’t use.');
        return line({ kind: 'custom', serviceId: null, productId: null, name, unitCents: checkPrice(input.unitCents, 'Enter the price of each custom item.') });
      });
      const total = items.reduce((sum, i) => sum + i.totalCents, 0);
      if (total > MAX_SALE_CENTS) throw invalid('A sale can be at most $10,000. Split it into two sales.');
      const typedName = typeof body.customerName === 'string' ? body.customerName.trim() : '';
      if (charLength(typedName) > 60) throw invalid('Keep the name to 60 characters or fewer.');
      if (CONTROL_CHARS.test(typedName)) throw invalid('The name has characters we can’t use.');

      const now = clock();
      const soldOn = today();
      const sale: Sale = {
        id: dayId(`sale|${now.getTime()}|${Math.random()}`, soldOn),
        barberId: barber.id,
        barberName: barber.name,
        appointmentId: appointment?.id ?? null,
        customerName: typedName || appointment?.customer.name || null,
        method: body.method,
        paymentIntentId: null,
        totalCents: total,
        items,
        soldAt: iso(now),
        voidedAt: null,
        voidReason: null,
      };
      keep(store, soldOn).sales.unshift(sale);
      if (appointment && appointmentDate) {
        const kept = keep(store, appointmentDate).appointments.find((a) => a.id === appointment!.id)!;
        kept.status = 'completed';
        kept.cancelledBy = null;
        kept.sale = { id: sale.id, totalCents: total, method: sale.method };
        // Paid with the sale's total, unless a card payment paid it already (then the card's numbers stay).
        if (!kept.cardPayment) kept.payment = { status: 'paid', amountCents: total, paidAt: sale.soldAt };
      }
      store.keys[idempotencyKey] = sale.id;
      save(store);
      return structuredClone(sale);
    },

    async voidSale(id: string, reason: string | null): Promise<VoidedSale> {
      await pause(latency);
      const store = load();
      signedIn(store);
      const found = findSale(store, id);
      if (!found) throw fail('not_found', "We couldn't find that sale.", 404);
      const why = reason?.trim() || null;
      if (why !== null && charLength(why) > 200) throw invalid('Keep the reason to 200 characters or fewer.');
      const kept = keep(store, found.date);
      const sale = kept.sales.find((s) => s.id === id)!;
      if (sale.voidedAt === null) {
        sale.voidedAt = iso(clock());
        sale.voidReason = why;
        if (sale.appointmentId) {
          const where = findAppointment(store, sale.appointmentId);
          if (where) {
            const appointment = keep(store, where.date).appointments.find((a) => a.id === sale.appointmentId)!;
            if (appointment.sale?.id === sale.id) {
              appointment.sale = null;
              // Unpaid again, unless a card payment paid it (voiding never refunds a card).
              appointment.payment = appointment.cardPayment
                ? { status: 'paid', amountCents: appointment.cardPayment.amountCents, paidAt: appointment.cardPayment.paidAt }
                : { status: 'unpaid', amountCents: null, paidAt: null };
            }
          }
        }
        save(store);
      }
      return { sale: structuredClone(sale), message: sale.method === 'card' ? VOIDED_CARD_MESSAGE : VOIDED_MESSAGE };
    },

    async analytics(query: AnalyticsQuery, signal?: AbortSignal): Promise<Analytics> {
      await pause(latency, signal);
      if (!isDate(query.from) || !isDate(query.to)) throw invalid('Dates must look like 2026-11-02.');
      const now = clock();
      const shopToday = localDate(now, zone);
      if (Math.abs(daysBetween(shopToday, query.from)) > 3660 || Math.abs(daysBetween(shopToday, query.to)) > 3660) {
        throw invalid('Pick dates within 10 years of today.');
      }
      const span = daysBetween(query.from, query.to);
      if (span < 0) throw invalid('to must be on or after from.');
      if (span >= 366) throw invalid('Ask for at most 366 days at a time.');
      if (query.barberId !== null && !catalog.barbers.some((b) => b.id === query.barberId)) throw invalid("That barber isn't on the team.");
      const store = load();
      signedIn(store);
      return demoAnalytics(
        {
          catalog,
          day: (date) => day(store, date),
          // A fee charged now may be for any visit the demo holds: the sample days and the days kept.
          days: [...sampleDays(shopToday), ...Object.keys(store.days)],
          products: products(store),
          now,
        },
        query,
      );
    },

    async products(signal?: AbortSignal): Promise<Product[]> {
      await pause(latency, signal);
      const store = load();
      signedIn(store);
      return products(store);
    },

    async createProduct(input: ProductInput): Promise<Product> {
      await pause(latency);
      const store = load();
      signedIn(store);
      const clean = checkProduct(input);
      const product: Product = {
        id: dayId(`product|${clock().getTime()}|${Math.random()}`, today()),
        name: clean.name!,
        description: clean.description ?? null,
        priceCents: clean.priceCents ?? null,
        imageUrl: null,
        visible: clean.visible ?? true,
      };
      store.products = [...products(store), product];
      save(store);
      return { ...product };
    },

    async updateProduct(id: string, input: Partial<ProductInput>): Promise<Product> {
      await pause(latency);
      const store = load();
      signedIn(store);
      const list = products(store);
      const index = list.findIndex((p) => p.id === id);
      if (index === -1) throw productNotFound();
      const clean = checkProduct(input, true);
      const updated = { ...list[index]!, ...clean };
      list[index] = updated;
      store.products = list;
      save(store);
      return { ...updated };
    },

    async deleteProduct(id: string): Promise<void> {
      await pause(latency);
      const store = load();
      signedIn(store);
      const list = products(store);
      if (!list.some((p) => p.id === id)) throw productNotFound();
      store.products = list.filter((p) => p.id !== id);
      save(store);
    },

    async uploadProductPhoto(id: string, jpeg: Blob): Promise<Product> {
      await pause(latency);
      const store = load();
      signedIn(store);
      if (jpeg.type !== 'image/jpeg') throw fail('invalid_request', 'Send the photo as a JPEG (Content-Type: image/jpeg).', 415);
      if (jpeg.size > 4 * 1024 * 1024) throw invalid('That photo is too big. Pick one under 4 MB.');
      const list = products(store);
      const index = list.findIndex((p) => p.id === id);
      if (index === -1) throw productNotFound();
      const updated = { ...list[index]!, imageUrl: await dataUrl(jpeg) };
      list[index] = updated;
      store.products = list;
      saveOrFail(store);
      return { ...updated };
    },

    async stripe(signal?: AbortSignal): Promise<StripeConnection> {
      await pause(latency, signal);
      const store = load();
      signedIn(store);
      return stripeJSON(store);
    },

    async connectStripe(): Promise<StripeConnectLink> {
      // The pretend step: in the real Business area, Stripe's own page opens here.
      await pause(connectStep);
      const store = load();
      signedIn(store);
      const now = clock();
      store.stripe = { connectedAt: iso(now) };
      save(store);
      return { url: '/business/settings?stripe=active', expiresAt: iso(now.getTime() + 5 * 60_000) };
    },

    async noShowSettings(signal?: AbortSignal): Promise<NoShowSettings> {
      await pause(latency, signal);
      const store = load();
      signedIn(store);
      return { ...store.noShowSettings };
    },

    async updateNoShowSettings(patch: Partial<NoShowSettings>): Promise<NoShowSettings> {
      await pause(latency);
      const store = load();
      signedIn(store);
      const next = { ...store.noShowSettings };
      if (patch.enabled !== undefined) next.enabled = Boolean(patch.enabled);
      if (patch.feeMode !== undefined) {
        if (patch.feeMode !== 'percent' && patch.feeMode !== 'flat') throw invalid('feeMode must be percent or flat.');
        next.feeMode = patch.feeMode;
      }
      if (patch.percent !== undefined) {
        if (!Number.isInteger(patch.percent) || patch.percent < 1 || patch.percent > 100) throw invalid('Pick a percentage from 1% to 100%.');
        next.percent = patch.percent;
      }
      if (patch.flatCents !== undefined) {
        if (!Number.isInteger(patch.flatCents) || patch.flatCents < 50 || patch.flatCents > 50_000)
          throw invalid(`Pick a flat fee from ${money(50)} to ${money(50_000)}.`);
        next.flatCents = patch.flatCents;
      }
      if (patch.lateCancelEnabled !== undefined) next.lateCancelEnabled = Boolean(patch.lateCancelEnabled);
      if (patch.lateCancelWindowMinutes !== undefined) {
        const w = patch.lateCancelWindowMinutes;
        if (!Number.isInteger(w) || w < 30 || w > 2880) throw invalid(`Pick a late-cancellation window from ${windowLabel(30)} to ${windowLabel(2880)}.`);
        next.lateCancelWindowMinutes = w;
      }
      store.noShowSettings = next;
      save(store);
      return { ...next };
    },

    async computerSessions(signal?: AbortSignal): Promise<ComputerSession[]> {
      await pause(latency, signal);
      const store = load();
      const current = signedIn(store);
      const now = clock().getTime();
      return store.sessions
        .filter((s) => Date.parse(s.expiresAt) > now)
        .sort((a, b) => b.lastUsedAt.localeCompare(a.lastUsedAt))
        .map((s) => sessionJSON(s, current));
    },

    async signOutComputer(id: string): Promise<void> {
      await pause(latency);
      const store = load();
      signedIn(store);
      if (!store.sessions.some((s) => s.id === id)) throw fail('not_found', "We couldn't find that computer.", 404);
      store.sessions = store.sessions.filter((s) => s.id !== id);
      save(store);
    },

    async signOutAllComputers(): Promise<void> {
      await pause(latency);
      const store = load();
      signedIn(store);
      store.sessions = [];
      save(store);
    },

    /** "Reset the demo": the sample shop back as it started, this computer still signed in. */
    async resetDemo(): Promise<void> {
      await pause(latency);
      const store = load();
      const current = signedIn(store);
      const reset = fresh(clock(), [current]);
      if (inMemoryOnly) memory = reset;
      else {
        removeKey('local', DEMO_BUSINESS_KEY);
        save(reset);
      }
    },
  };

  /** A product's fields as the server takes them, or a 400 that says what's wrong. */
  function checkProduct(input: Partial<ProductInput>, partial = false): Partial<ProductInput> {
    const clean: Partial<ProductInput> = {};
    if (input.name !== undefined || !partial) {
      const name = (input.name ?? '').trim();
      if (name === '') throw invalid('Give the product a name.');
      if (charLength(name) > 80) throw invalid('Keep the name to 80 characters or fewer.');
      if (/[\u0000-\u001f\u007f]/.test(name)) throw invalid('The name has characters we can’t use.');
      clean.name = name;
    }
    if (input.description !== undefined) {
      const description = input.description?.trim() ?? '';
      if (charLength(description) > 500) throw invalid('Keep the description to 500 characters or fewer.');
      clean.description = description === '' ? null : description;
    }
    if (input.priceCents !== undefined) {
      if (input.priceCents !== null && (!Number.isInteger(input.priceCents) || input.priceCents < 0)) throw invalid("The price can't be negative.");
      if (input.priceCents !== null && input.priceCents > 1_000_000) throw invalid('That price is too high.');
      clean.priceCents = input.priceCents;
    }
    if (input.visible !== undefined) clean.visible = Boolean(input.visible);
    return clean;
  }

  return api;
}

/** A photo as a data: URL, which the demo keeps in this browser (its pages allow data: images). */
function dataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new ApiError('invalid_request', "That photo couldn't be read. Try another one.", 400));
    reader.readAsDataURL(blob);
  });
}

/** The demo build's owner API: the real clock, and answers that take a moment like the network's. */
export const demoOwnerApi: OwnerApi = createDemoOwnerApi();
