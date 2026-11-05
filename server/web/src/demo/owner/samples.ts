// The Business demo's sample shop: SAMPLE appointments and sales, the same every time a
// day is shown, for the five barbers. Clients are "Marcus Sample", "Kim Sample" and so on,
// with numbers in the 555-01xx range kept for examples, and the products are named
// "Sample pomade" and the like, so nothing reads as a real client or a real product.
//
// - Appointments are the client demo's sample bookings (src/demo/api.ts sampleBookings: two
//   or three a day for each barber), so the times the booking demo shows as taken are these.
// - What happened to an appointment depends on when it ended: one that ended before the
//   demo was opened today (or on an earlier day) has its outcome (most checked out, some
//   marked Done without a checkout, a few no-shows and cancellations, with fees charged to
//   a card on file now and then), and walk-ins bought services and products; one still to
//   come (or not marked yet) is booked, for the owner to check out, mark or cancel.
// - Only the last 8 weeks have history (so analytics has something to show), and the next
//   two weeks have bookings.

import type { Catalog, NoShowFee, Offering } from '../../api/types';
import { addDays, clockMinutes, daysBetween, localDate, weekdayOf, zonedInstant } from '../../lib/shopTime';
import type { OwnerAppointment, Product, Sale, SaleItem, SaleMethod } from '../../business/types';
import { sampleBookings } from '../api';

/** Days of history before today, and days of bookings after it. */
export const HISTORY_DAYS = 56;
export const AHEAD_DAYS = 13;

/** An appointment as the demo keeps it: the API's, with the price it was booked at and how it was paid by card. */
export interface DemoAppointment extends OwnerAppointment {
  /** What the appointment costs (the API only says its label). */
  priceCents: number;
  /** A card payment that paid it (Tap to Pay), which voiding a cash sale doesn't undo. */
  cardPayment: { amountCents: number; paidAt: string } | null;
}

export interface DayData {
  appointments: DemoAppointment[];
  sales: Sale[];
}

/** The sample products. Their prices here are the ones sample sales were rung up at. */
export const SAMPLE_PRODUCTS: readonly Product[] = [
  {
    id: 'd3e00000-0000-4000-8000-000000000001',
    name: 'Sample pomade',
    description: 'Medium hold, low shine. A sample product for the demo.',
    priceCents: 1800,
    imageUrl: null,
    visible: true,
  },
  {
    id: 'd3e00000-0000-4000-8000-000000000002',
    name: 'Sample beard oil',
    description: 'Softens the beard and the skin under it. A sample product for the demo.',
    priceCents: 1500,
    imageUrl: null,
    visible: true,
  },
  {
    id: 'd3e00000-0000-4000-8000-000000000003',
    name: 'Sample sea salt spray',
    description: 'Texture and volume for the top. A sample product for the demo.',
    priceCents: 1200,
    imageUrl: null,
    visible: true,
  },
  {
    id: 'd3e00000-0000-4000-8000-000000000004',
    name: 'Sample shampoo',
    description: null,
    priceCents: 1600,
    imageUrl: null,
    visible: true,
  },
  {
    id: 'd3e00000-0000-4000-8000-000000000005',
    name: 'Sample hair tonic',
    description: 'No price yet, so checkout asks for one. Hidden from clients. A sample product for the demo.',
    priceCents: null,
    imageUrl: null,
    visible: false,
  },
];

const FIRST_NAMES = [
  'Marcus', 'Andre', 'Diego', 'Jay', 'Luis', 'Sam', 'Chris', 'Tony', 'Kim', 'Lee', 'Malik', 'Omar', 'Ray', 'Eli', 'Noah',
  'Gabe', 'Isaac', 'Jon', 'Kevin', 'Mateo', 'Nate', 'Oscar', 'Pete', 'Ruben', 'Theo', 'Victor', 'Will', 'Adrian', 'Brandon', 'Carlos',
];

const NOTES = ['Low fade, please.', 'First visit.', "Beard trim too, if there's time.", 'Same as last time.', 'Might be a few minutes late.'];

/** How often each service is booked, among a barber's services of an hour or less. */
const SERVICE_WEIGHTS: Record<string, number> = {
  haircut: 8,
  'haircut-and-beard': 3,
  'military-haircut': 3,
  'seniors-haircut': 1,
  'hot-towel-shave': 1,
};

/** A small random number generator that gives the same numbers for the same text. */
export function seeded(text: string): () => number {
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

function hex(random: () => number, length: number): string {
  let out = '';
  while (out.length < length) out += Math.floor(random() * 0x10000).toString(16).padStart(4, '0');
  return out.slice(0, length);
}

/**
 * A uuid-shaped id that says which shop day it belongs to (the last group starts with
 * YYYYMMDD), so the demo finds an appointment's or a sale's day from its id.
 */
export function dayId(seed: string, date: string, random: () => number = seeded(seed)): string {
  const h = hex(random, 22);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(12, 15)}-8${h.slice(15, 18)}-${date.replaceAll('-', '')}${h.slice(18, 22)}`;
}

/** The shop day in an id made by `dayId`, or null. */
export function dayOfId(id: string): string | null {
  const match = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-(\d{4})(\d{2})(\d{2})[0-9a-f]{4}$/.exec(id);
  return match ? `${match[1]}-${match[2]}-${match[3]}` : null;
}

function iso(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function pick<T>(items: readonly T[], random: () => number): T {
  return items[Math.floor(random() * items.length)]!;
}

function weighted(offerings: Offering[], catalog: Catalog, random: () => number): Offering | null {
  const weightOf = (o: Offering) => {
    const service = catalog.services.find((s) => s.id === o.serviceId);
    if (!service || service.category === 'Add-ons') return 0;
    return SERVICE_WEIGHTS[o.serviceId] ?? 1;
  };
  const total = offerings.reduce((sum, o) => sum + weightOf(o), 0);
  if (total === 0) return null;
  let roll = random() * total;
  for (const offering of offerings) {
    roll -= weightOf(offering);
    if (roll < 0 && weightOf(offering) > 0) return offering;
  }
  return offerings.find((o) => weightOf(o) > 0) ?? null;
}

function method(random: () => number): SaleMethod {
  const roll = random();
  return roll < 0.55 ? 'card' : roll < 0.85 ? 'cash' : 'other';
}

function item(kind: SaleItem['kind'], name: string, unitCents: number, quantity: number, ids: { serviceId?: string; productId?: string }): SaleItem {
  return {
    kind,
    serviceId: ids.serviceId ?? null,
    productId: ids.productId ?? null,
    name,
    quantity,
    unitCents,
    totalCents: unitCents * quantity,
  };
}

const PRICED_PRODUCTS = SAMPLE_PRODUCTS.filter((p): p is Product & { priceCents: number } => p.priceCents !== null);

function productItem(random: () => number): SaleItem {
  const product = pick(PRICED_PRODUCTS, random);
  return item('product', product.name, product.priceCents, random() < 0.8 ? 1 : 2, { productId: product.id });
}

export interface SampleContext {
  catalog: Catalog;
  /** The shop's today. */
  today: string;
  /** Appointments that ended before this (ms) have their outcome; later ones are still booked. */
  historyBefore: number;
}

/** Whether a day has sample data: the last 8 weeks and the next two. */
export function hasSamples(date: string, today: string): boolean {
  const offset = daysBetween(today, date);
  return offset >= -HISTORY_DAYS && offset <= AHEAD_DAYS;
}

/** A sample appointment, as booked, from one of the day's sample bookings. */
function bookedAppointment(catalog: Catalog, date: string, barberId: string, start: number, random: () => number): DemoAppointment | null {
  const offerings = catalog.offerings.filter((o) => o.barberId === barberId && o.priceKind === 'fixed' && o.priceCents > 0 && o.durationMinutes <= 60);
  const offering = weighted(offerings, catalog, random);
  if (!offering) return null;
  const barber = catalog.barbers.find((b) => b.id === barberId);
  const service = catalog.services.find((s) => s.id === offering.serviceId);
  const first = pick(FIRST_NAMES, random);
  const phone = random() < 0.1 ? null : `+144255501${String(Math.floor(random() * 100)).padStart(2, '0')}`;
  const email = random() < 0.2 ? `${first.toLowerCase()}@example.com` : null;
  const note = random() < 0.15 ? pick(NOTES, random) : null;
  const hasCard = phone !== null && random() < 0.25;
  const card = hasCard ? { brand: random() < 0.6 ? 'visa' : 'mastercard', last4: random() < 0.15 ? '0002' : String(1000 + Math.floor(random() * 9000)) } : null;
  const noShowFee: NoShowFee | null = card
    ? {
        amountCents: offering.priceCents,
        fullPrice: true,
        status: 'none',
        chargedAt: null,
        message: null,
        customerCancelledAt: null,
        lateCancelWindowMinutes: 60,
        reason: null,
      }
    : null;
  const createdAt = start - (1 + Math.floor(random() * 6)) * 86_400_000 - Math.floor(random() * 10) * 3_600_000;
  return {
    id: dayId(`appt|${date}|${barberId}|${start}`, date),
    offeringId: offering.id,
    serviceId: offering.serviceId,
    serviceName: service?.name ?? 'Appointment',
    barberId,
    barberName: barber?.name ?? barberId,
    start: iso(start),
    end: iso(start + offering.durationMinutes * 60_000),
    durationMinutes: offering.durationMinutes,
    priceLabel: offering.priceLabel,
    status: 'booked',
    cancelledBy: null,
    payment: { status: 'unpaid', amountCents: null, paidAt: null },
    customer: { name: `${first} Sample`, phone, email },
    note,
    createdAt: iso(createdAt),
    card,
    noShowFee,
    sale: null,
    priceCents: offering.priceCents,
    cardPayment: null,
  };
}

function checkoutSale(appointment: DemoAppointment, random: () => number, zone: string): Sale {
  const items = [item('service', appointment.serviceName, appointment.priceCents, 1, { serviceId: appointment.serviceId })];
  if (random() < 0.35) items.push(productItem(random));
  if (random() < 0.04) items.push(item('custom', 'Gift card', 2500, 1, {}));
  const paidWith = method(random);
  const soldAt = Date.parse(appointment.end);
  const total = items.reduce((sum, i) => sum + i.totalCents, 0);
  return {
    id: dayId(`sale|${appointment.id}`, localDate(new Date(soldAt), zone)),
    barberId: appointment.barberId,
    barberName: appointment.barberName,
    appointmentId: appointment.id,
    customerName: appointment.customer.name,
    method: paidWith,
    paymentIntentId: paidWith === 'card' ? `pi_demo_${appointment.id.slice(0, 8)}` : null,
    totalCents: total,
    items,
    soldAt: iso(soldAt),
    voidedAt: null,
    voidReason: null,
  };
}

/** What happened to an appointment that ended before the history line: its outcome, and its sale if it was checked out. */
function outcome(appointment: DemoAppointment, random: () => number, ctx: SampleContext): Sale | null {
  const start = Date.parse(appointment.start);
  const roll = random();
  if (roll < 0.78) {
    const sale = checkoutSale(appointment, random, ctx.catalog.timeZone);
    appointment.status = 'completed';
    appointment.sale = { id: sale.id, totalCents: sale.totalCents, method: sale.method };
    appointment.payment = { status: 'paid', amountCents: sale.totalCents, paidAt: sale.soldAt };
    if (sale.method === 'card') appointment.cardPayment = { amountCents: sale.totalCents, paidAt: sale.soldAt };
    return sale;
  }
  if (roll < 0.85) {
    // Marked Done without a checkout: it counts at its booked price.
    appointment.status = 'completed';
    return null;
  }
  const fee = appointment.noShowFee;
  if (roll < 0.92) {
    appointment.status = 'noShow';
    const chargedAt = start + 25 * 60_000;
    if (fee && appointment.card?.last4 !== '0002' && random() < 0.6 && chargedAt <= ctx.historyBefore) {
      appointment.noShowFee = { ...fee, status: 'charged', chargedAt: iso(chargedAt), reason: 'noShow' };
    }
    return null;
  }
  appointment.status = 'cancelled';
  if (random() < 0.7) {
    appointment.cancelledBy = 'customer';
    const minutesBefore = random() < 0.35 ? 10 + Math.floor(random() * 45) : 90 + Math.floor(random() * 1200);
    const cancelledAt = start - minutesBefore * 60_000;
    if (fee) {
      const late = minutesBefore < (fee.lateCancelWindowMinutes ?? 0);
      const chargedAt = start + 15 * 60_000;
      const charged = late && appointment.card?.last4 !== '0002' && random() < 0.5 && chargedAt <= ctx.historyBefore;
      appointment.noShowFee = {
        ...fee,
        customerCancelledAt: iso(cancelledAt),
        ...(charged ? { status: 'charged' as const, chargedAt: iso(chargedAt), reason: 'lateCancel' as const } : {}),
      };
    }
  } else {
    appointment.cancelledBy = 'shop';
  }
  return null;
}

/** Walk-ins on a day of history: one to three sales for some barbers, with no appointment. */
function walkIns(catalog: Catalog, date: string, historyBefore: number): Sale[] {
  const hours = catalog.hours[String(weekdayOf(date))];
  if (!hours) return [];
  const opens = clockMinutes(hours.opens);
  const closes = clockMinutes(hours.closes);
  const sales: Sale[] = [];
  for (const barber of catalog.barbers) {
    const random = seeded(`walkin|${date}|${barber.id}`);
    const count = Math.floor(random() * 3);
    for (let i = 0; i < count; i += 1) {
      const minute = opens + 20 + Math.floor(random() * Math.max(1, closes - opens - 40));
      const at = zonedInstant(date, minute, catalog.timeZone);
      if (!at || at.getTime() >= historyBefore) continue;
      const items: SaleItem[] = [];
      if (random() < 0.6) {
        const quick = catalog.offerings.filter(
          (o) => o.barberId === barber.id && o.priceKind === 'fixed' && o.priceCents > 0 && (o.serviceId === 'military-haircut' || o.serviceId === 'haircut'),
        );
        const offering = quick.length > 0 ? pick(quick, random) : null;
        if (offering) {
          const name = catalog.services.find((s) => s.id === offering.serviceId)?.name ?? 'Haircut';
          items.push(item('service', name, offering.priceCents, 1, { serviceId: offering.serviceId }));
        }
        if (random() < 0.2) items.push(productItem(random));
      } else {
        items.push(productItem(random));
        if (random() < 0.3) items.push(productItem(random));
      }
      if (items.length === 0) continue;
      const paidWith = method(random);
      const id = dayId(`walkin|${date}|${barber.id}|${i}`, date);
      sales.push({
        id,
        barberId: barber.id,
        barberName: barber.name,
        appointmentId: null,
        customerName: null,
        method: paidWith,
        paymentIntentId: paidWith === 'card' ? `pi_demo_${id.slice(0, 8)}` : null,
        totalCents: items.reduce((sum, it) => sum + it.totalCents, 0),
        items,
        soldAt: iso(at.getTime()),
        voidedAt: null,
        voidReason: null,
      });
    }
  }
  return sales;
}

/** A day of the sample shop: its appointments (soonest first) and its sales (newest first). */
export function sampleDay(ctx: SampleContext, date: string): DayData {
  if (!hasSamples(date, ctx.today)) return { appointments: [], sales: [] };
  const appointments: DemoAppointment[] = [];
  const sales: Sale[] = [];
  for (const slot of sampleBookings(ctx.catalog, date)) {
    const random = seeded(`biz|${date}|${slot.barberId}|${slot.start}`);
    const appointment = bookedAppointment(ctx.catalog, date, slot.barberId, slot.start, random);
    if (!appointment) continue;
    if (Date.parse(appointment.end) <= ctx.historyBefore) {
      const sale = outcome(appointment, random, ctx);
      if (sale) sales.push(sale);
    }
    appointments.push(appointment);
  }
  sales.push(...walkIns(ctx.catalog, date, ctx.historyBefore));
  appointments.sort((a, b) => a.start.localeCompare(b.start) || a.barberId.localeCompare(b.barberId));
  sales.sort((a, b) => b.soldAt.localeCompare(a.soldAt) || b.id.localeCompare(a.id));
  return { appointments, sales };
}

/** The days around today that have sample data, oldest first. */
export function sampleDays(today: string): string[] {
  return Array.from({ length: HISTORY_DAYS + AHEAD_DAYS + 1 }, (_, i) => addDays(today, i - HISTORY_DAYS));
}
