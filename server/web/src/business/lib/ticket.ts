// The checkout ticket, like the owner app's "Check out": the client (an appointment, or a
// walk-in with an optional name), who gets credit ("Sold by"), and the items (services at
// the barber's price, which can be changed since "From" prices vary; products with a
// quantity, asking for a price when the product has none; and amounts), with the total.
// Cash and other payments are recorded with POST /api/owner/sales; card payments happen
// on the iPhone with Tap to Pay. A sale's Idempotency-Key stays the same until the sale is
// recorded, whichever ticket sends it, so trying again after a lost answer (on the same
// ticket, or on a new one after the panel was closed) can't record the sale twice.

import type { Offering } from '../../api/types';
import { readJSON, removeKey, writeJSON } from '../../lib/storage';
import { newToken } from '../../lib/tokens';
import type { NewSale, NewSaleItem, OwnerAppointment, Product } from '../types';
import { editableMoney, MAX_CENTS, moneyWithCommas, parseMoney, priceFromLabel } from './money';

export const MAX_ITEMS = 20;
export const MAX_QUANTITY = 99;
export const MAX_CUSTOMER_NAME = 60;
export const MAX_ITEM_NAME = 80;

export interface TicketLine {
  /** Unique on this ticket. */
  key: string;
  kind: 'service' | 'product' | 'custom';
  serviceId: string | null;
  productId: string | null;
  name: string;
  /** The price of one, as typed, so a half-typed amount stays on screen. */
  priceText: string;
  quantity: number;
}

export interface TicketAppointment {
  id: string;
  customerName: string;
  serviceName: string;
  barberName: string;
  start: string;
}

export interface Ticket {
  /** Started from an appointment (Today → appointment → Check out); null for a walk-in. */
  appointment: TicketAppointment | null;
  /** A walk-in's name, if given. */
  customerName: string;
  /** Who gets credit. Required. */
  barberId: string | null;
  lines: TicketLine[];
  /** Makes each line's key. */
  nextKey: number;
}

const LAST_BARBER_KEY = 'izzy.business.lastBarber.v1';

/** The barber chosen last on this computer, for the next walk-in. */
export function lastBarber(): string | null {
  const stored = readJSON('local', LAST_BARBER_KEY);
  return typeof stored === 'string' ? stored : null;
}

export function rememberBarber(barberId: string): void {
  writeJSON('local', LAST_BARBER_KEY, barberId);
}

/** "Reset the demo": the barber picked last goes too. */
export function forgetLastBarber(): void {
  removeKey('local', LAST_BARBER_KEY);
}

function withLine(ticket: Ticket, line: Omit<TicketLine, 'key'>): Ticket {
  return { ...ticket, lines: [...ticket.lines, { ...line, key: `line-${ticket.nextKey}` }], nextKey: ticket.nextKey + 1 };
}

/** A walk-in: no client yet, Sold by the barber chosen last on this computer (if still on the team). */
export function walkInTicket(barberId: string | null): Ticket {
  return { appointment: null, customerName: '', barberId, lines: [], nextKey: 1 };
}

/** From an appointment: its barber, and its service at the price it was booked at. */
export function appointmentTicket(appointment: OwnerAppointment, offerings: readonly Offering[]): Ticket {
  const offering = offerings.find((o) => o.id === appointment.offeringId);
  const cents = priceFromLabel(appointment.priceLabel) ?? offering?.priceCents ?? 0;
  const ticket: Ticket = {
    appointment: {
      id: appointment.id,
      customerName: appointment.customer.name,
      serviceName: appointment.serviceName,
      barberName: appointment.barberName,
      start: appointment.start,
    },
    customerName: '',
    barberId: appointment.barberId,
    lines: [],
    nextKey: 1,
  };
  return withLine(ticket, {
    kind: 'service',
    serviceId: appointment.serviceId,
    productId: null,
    name: appointment.serviceName,
    priceText: editableMoney(cents),
    quantity: 1,
  });
}

/** "+ Service": one of the barber's services, at that barber's price (which can be changed). */
export function addService(ticket: Ticket, offering: Offering, name: string): Ticket {
  return withLine(ticket, {
    kind: 'service',
    serviceId: offering.serviceId,
    productId: null,
    name,
    priceText: editableMoney(offering.priceCents),
    quantity: 1,
  });
}

/** "+ Product": one more if it's on the ticket already; a product with no price asks for one. */
export function addProduct(ticket: Ticket, product: Product): Ticket {
  const existing = ticket.lines.find((line) => line.kind === 'product' && line.productId === product.id);
  if (existing) return setQuantity(ticket, existing.key, existing.quantity + 1);
  return withLine(ticket, {
    kind: 'product',
    serviceId: null,
    productId: product.id,
    name: product.name,
    priceText: product.priceCents === null ? '' : editableMoney(product.priceCents),
    quantity: 1,
  });
}

/** "+ Amount": a custom item, "Other" unless named. */
export function addAmount(ticket: Ticket, name: string, cents: number): Ticket {
  const trimmed = name.trim();
  return withLine(ticket, {
    kind: 'custom',
    serviceId: null,
    productId: null,
    name: trimmed === '' ? 'Other' : trimmed,
    priceText: editableMoney(cents),
    quantity: 1,
  });
}

export function setQuantity(ticket: Ticket, key: string, quantity: number): Ticket {
  const q = Math.min(MAX_QUANTITY, Math.max(1, Math.round(quantity)));
  return { ...ticket, lines: ticket.lines.map((line) => (line.key === key ? { ...line, quantity: q } : line)) };
}

export function setPrice(ticket: Ticket, key: string, priceText: string): Ticket {
  return { ...ticket, lines: ticket.lines.map((line) => (line.key === key ? { ...line, priceText } : line)) };
}

export function removeLine(ticket: Ticket, key: string): Ticket {
  return { ...ticket, lines: ticket.lines.filter((line) => line.key !== key) };
}

export function setBarber(ticket: Ticket, barberId: string): Ticket {
  return { ...ticket, barberId };
}

export function setCustomerName(ticket: Ticket, customerName: string): Ticket {
  return { ...ticket, customerName };
}

/** One item's price in cents, or null while it isn't an amount (or is over $10,000). */
export function unitCents(line: TicketLine): number | null {
  const cents = parseMoney(line.priceText);
  return cents === null || cents > MAX_CENTS ? null : cents;
}

export function lineTotal(line: TicketLine): number | null {
  const cents = unitCents(line);
  return cents === null ? null : cents * line.quantity;
}

/** The total, or null while an item has no price. */
export function ticketTotal(ticket: Ticket): number | null {
  let total = 0;
  for (const line of ticket.lines) {
    const cents = lineTotal(line);
    if (cents === null) return null;
    total += cents;
  }
  return total;
}

/** What's missing or wrong, in plain words, or null when the sale can be recorded. */
export function ticketProblem(ticket: Ticket): string | null {
  if (!ticket.barberId) return 'Pick who did the service, under Sold by.';
  if (ticket.lines.length === 0) return 'Add at least one item: a service, a product or an amount.';
  if (ticket.lines.length > MAX_ITEMS) return `A sale can have at most ${MAX_ITEMS} items.`;
  for (const line of ticket.lines) {
    if (unitCents(line) === null)
      return line.priceText.trim() === '' ? `Enter the price of ${line.name}.` : `Check the price of ${line.name}: type an amount like 25 or 17.50.`;
  }
  const total = ticketTotal(ticket) ?? 0;
  if (total > MAX_CENTS) return `A sale can be at most ${moneyWithCommas(MAX_CENTS)}. Split it into two sales.`;
  if ([...ticket.customerName.trim()].length > MAX_CUSTOMER_NAME) return `Keep the client's name to ${MAX_CUSTOMER_NAME} characters or fewer.`;
  return null;
}

/** POST /api/owner/sales's body: every price as shown on the ticket. */
export function newSale(ticket: Ticket, method: 'cash' | 'other'): NewSale {
  if (!ticket.barberId) throw new Error('A sale needs its barber');
  const items: NewSaleItem[] = ticket.lines.map((line) => {
    const cents = unitCents(line) ?? 0;
    if (line.kind === 'service') return { kind: 'service', serviceId: line.serviceId ?? '', unitCents: cents, quantity: line.quantity };
    if (line.kind === 'product') return { kind: 'product', productId: line.productId ?? '', unitCents: cents, quantity: line.quantity };
    return { kind: 'custom', name: line.name, unitCents: cents, quantity: line.quantity };
  });
  const name = ticket.customerName.trim();
  return {
    barberId: ticket.barberId,
    appointmentId: ticket.appointment?.id ?? null,
    // An appointment's client is the server's default; a walk-in's name only if one was typed.
    customerName: ticket.appointment ? null : name === '' ? null : name,
    method,
    items,
  };
}

/** How many sales sent without an answer keep their keys (the oldest is forgotten first). */
const PENDING_SALES = 20;

/**
 * The Idempotency-Key to send a sale with: the same one every time the same sale is sent
 * until it's recorded (a retry after a lost answer, also from a new ticket once the panel
 * was closed: the server then answers with the sale it already has), a new one for a sale
 * that differs in anything, and a new one for the same sale rung up again once it's recorded.
 */
export class SaleKeys {
  /** What was sent (the body) → its key, for sales sent without a confirmed answer. */
  private readonly pending = new Map<string, string>();

  constructor(private readonly make: () => string = () => newToken()) {}

  keyFor(sale: NewSale): string {
    const body = JSON.stringify(sale);
    const known = this.pending.get(body);
    if (known) return known;
    const key = this.make();
    this.pending.set(body, key);
    if (this.pending.size > PENDING_SALES) this.pending.delete(this.pending.keys().next().value!);
    return key;
  }

  /** Recorded: the same sale rung up again later is a new sale, with a new key. */
  done(sale: NewSale): void {
    this.pending.delete(JSON.stringify(sale));
  }
}

/** The keys of every ticket on this page, kept while it stays open (closing a ticket doesn't lose them). */
export const saleKeys = new SaleKeys();
