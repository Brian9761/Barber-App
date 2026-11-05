import { describe, expect, it } from 'vitest';
import ownerAppointments from '../../../../test/fixtures/contract/owner-appointments-with-sale.json';
import ownerProducts from '../../../../test/fixtures/contract/owner-products.json';
import { catalog } from '../../test/api';
import type { OwnerAppointment, Product } from '../types';
import {
  addAmount,
  addProduct,
  addService,
  appointmentTicket,
  lastBarber,
  lineTotal,
  newSale,
  rememberBarber,
  removeLine,
  SaleKeys,
  setBarber,
  setCustomerName,
  setPrice,
  setQuantity,
  ticketProblem,
  ticketTotal,
  walkInTicket,
} from './ticket';

// The checkout ticket, like the owner app's "Check out": defaults, adding, removing and
// editing items, the total, what's missing, the sale it sends, and the Idempotency-Key that
// stays the same while the sale does.

const booked = ownerAppointments.appointments[1] as unknown as OwnerAppointment;
const [pomade, beardOil, tonic] = ownerProducts.products as unknown as [Product, Product, Product];
const flowxboriHaircut = catalog.offerings.find((o) => o.id === 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a')!;

describe('starting a ticket', () => {
  it('from an appointment: its barber, and its service at the price it was booked at', () => {
    const ticket = appointmentTicket(booked, catalog.offerings);
    expect(ticket.appointment).toMatchObject({ id: booked.id, customerName: booked.customer.name, serviceName: booked.serviceName });
    expect(ticket.barberId).toBe(booked.barberId);
    expect(ticket.lines).toEqual([
      { key: 'line-1', kind: 'service', serviceId: booked.serviceId, productId: null, name: booked.serviceName, priceText: '45', quantity: 1 },
    ]);
    // Carlos's haircut, booked at $45.
    expect(ticketTotal(ticket)).toBe(4500);
  });

  it('for a walk-in: no client, Sold by the barber chosen last on this computer', () => {
    expect(lastBarber()).toBeNull();
    rememberBarber('carlos-rafael');
    expect(lastBarber()).toBe('carlos-rafael');
    const ticket = walkInTicket(lastBarber());
    expect(ticket).toMatchObject({ appointment: null, customerName: '', barberId: 'carlos-rafael', lines: [] });
    expect(ticketProblem(ticket)).toBe('Add at least one item: a service, a product or an amount.');
    expect(ticketProblem(walkInTicket(null))).toBe('Pick who did the service, under Sold by.');
  });
});

describe('items and the total', () => {
  it('adds services at the barber’s price, products with a quantity, and amounts', () => {
    let ticket = walkInTicket('flowxbori');
    ticket = addService(ticket, flowxboriHaircut, 'Haircut');
    ticket = addProduct(ticket, pomade);
    ticket = addProduct(ticket, pomade);
    ticket = addAmount(ticket, '  ', 500);
    ticket = addAmount(ticket, 'Gift card', 2500);
    expect(ticket.lines.map((l) => [l.kind, l.name, l.priceText, l.quantity])).toEqual([
      ['service', 'Haircut', '35', 1],
      ['product', 'Matte pomade', '18', 2],
      ['custom', 'Other', '5', 1],
      ['custom', 'Gift card', '25', 1],
    ]);
    expect(ticketTotal(ticket)).toBe(3500 + 3600 + 500 + 2500);
    expect(ticketProblem(ticket)).toBeNull();
  });

  it('lets a "From" price be changed, and asks for the price of a product that has none', () => {
    let ticket = addService(walkInTicket('flowxbori'), flowxboriHaircut, 'Haircut');
    ticket = setPrice(ticket, 'line-1', '42.50');
    expect(lineTotal(ticket.lines[0]!)).toBe(4250);
    ticket = addProduct(ticket, tonic);
    expect(ticket.lines[1]!.priceText).toBe('');
    expect(ticketTotal(ticket)).toBeNull();
    expect(ticketProblem(ticket)).toBe('Enter the price of Hair tonic.');
    ticket = setPrice(ticket, 'line-2', 'twelve');
    expect(ticketProblem(ticket)).toBe('Check the price of Hair tonic: type an amount like 25 or 17.50.');
    ticket = setPrice(ticket, 'line-2', '$12');
    expect(ticketTotal(ticket)).toBe(4250 + 1200);
  });

  it('keeps quantities from 1 to 99, and removes items', () => {
    let ticket = addProduct(walkInTicket('flowxbori'), beardOil);
    ticket = setQuantity(ticket, 'line-1', 0);
    expect(ticket.lines[0]!.quantity).toBe(1);
    ticket = setQuantity(ticket, 'line-1', 120);
    expect(ticket.lines[0]!.quantity).toBe(99);
    ticket = removeLine(ticket, 'line-1');
    expect(ticket.lines).toEqual([]);
  });

  it('turns down a sale over $10,000 and a long name', () => {
    let ticket = addAmount(walkInTicket('flowxbori'), 'Big', 1_000_000);
    ticket = addAmount(ticket, 'More', 100);
    expect(ticketProblem(ticket)).toBe('A sale can be at most $10,000. Split it into two sales.');
    ticket = setCustomerName(removeLine(ticket, 'line-2'), 'A'.repeat(61));
    expect(ticketProblem(ticket)).toBe("Keep the client's name to 60 characters or fewer.");
  });
});

describe('the sale it records', () => {
  it('sends every item at the price shown, for the appointment, cash or other', () => {
    let ticket = appointmentTicket(booked, catalog.offerings);
    ticket = addProduct(ticket, pomade);
    ticket = setBarber(ticket, 'israel-flores');
    expect(newSale(ticket, 'cash')).toEqual({
      barberId: 'israel-flores',
      appointmentId: booked.id,
      customerName: null,
      method: 'cash',
      items: [
        { kind: 'service', serviceId: booked.serviceId, unitCents: 4500, quantity: 1 },
        { kind: 'product', productId: pomade.id, unitCents: 1800, quantity: 1 },
      ],
    });
  });

  it('names a walk-in only when a name was typed', () => {
    const ticket = addAmount(walkInTicket('julian-ramos'), 'Gift card', 2500);
    expect(newSale(ticket, 'other')).toMatchObject({ appointmentId: null, customerName: null, method: 'other' });
    expect(newSale(setCustomerName(ticket, '  Andre  '), 'other').customerName).toBe('Andre');
  });

  it('sends the same Idempotency-Key while the sale stays the same, and a new one once anything changes or it’s recorded', () => {
    let n = 0;
    const keys = new SaleKeys(() => `key-${++n}`);
    const ticket = addAmount(walkInTicket('julian-ramos'), 'Gift card', 2500);
    const first = keys.keyFor(newSale(ticket, 'cash'));
    expect(keys.keyFor(newSale(ticket, 'cash'))).toBe(first);
    const changed = keys.keyFor(newSale(ticket, 'other'));
    expect(changed).not.toBe(first);
    expect(keys.keyFor(newSale(ticket, 'other'))).toBe(changed);
    keys.done();
    expect(keys.keyFor(newSale(ticket, 'other'))).not.toBe(changed);
  });

  it('makes keys the server takes: 32 random bytes in base64url', () => {
    const key = new SaleKeys().keyFor(newSale(addAmount(walkInTicket('julian-ramos'), 'Tip', 500), 'cash'));
    expect(key).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});
