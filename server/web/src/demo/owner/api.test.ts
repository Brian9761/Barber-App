import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { isApiError } from '../../api/errors';
import type { OwnerApi } from '../../business/api/http';
import { session } from '../../business/session';
import type { OwnerAppointment } from '../../business/types';
import { DEMO_BUSINESS_KEY } from '../../lib/storage';
import { newToken } from '../../lib/tokens';
import { createDemoOwnerApi } from './api';
import { dayId, dayOfId, sampleDay, SAMPLE_PRODUCTS } from './samples';

// The Business demo's stand-in for the shop's server: its sample shop, the server's rules
// for checking out, voiding, statuses and fees, and analytics with the definitions of
// docs/analytics.md, checked by hand on the sample data.
//
// The clock is Wednesday, November 4, 2026 at 8 AM in Oceanside (before the shop opens), so
// today's sample appointments are all still booked, and Tuesday, November 3 is history.

const [POMADE, BEARD_OIL] = SAMPLE_PRODUCTS as unknown as [{ id: string }, { id: string }];

let now: Date;
let api: OwnerApi;

async function rejects(promise: Promise<unknown>): Promise<{ code: string; status: number; message: string }> {
  try {
    await promise;
  } catch (error) {
    if (isApiError(error)) return { code: error.code, status: error.status, message: error.message };
    throw error;
  }
  throw new Error('It went through');
}

function byName(appointments: OwnerAppointment[], name: string, barberId?: string): OwnerAppointment {
  const found = appointments.find((a) => a.customer.name === name && (!barberId || a.barberId === barberId));
  if (!found) throw new Error(`No ${name}`);
  return found;
}

beforeEach(async () => {
  session.reset();
  now = new Date('2026-11-04T16:00:00Z');
  api = createDemoOwnerApi({ now: () => now, latencyMs: 0, connectStepMs: 0 });
  session.signIn(await api.signIn('', 'Chrome on Mac'));
});

afterEach(() => session.reset());

describe('the sample shop', () => {
  it('has today’s bookings for the five barbers, all still to come before the shop opens', async () => {
    const today = await api.appointments('2026-11-04');
    expect(today).toHaveLength(12);
    expect(new Set(today.map((a) => a.barberId))).toEqual(new Set(['israel-flores', 'carlos-rafael', 'flowxbori', 'cristian-ceja', 'julian-ramos']));
    expect(today.every((a) => a.status === 'booked' && a.sale === null)).toBe(true);
    expect(today.every((a) => a.customer.name.endsWith(' Sample'))).toBe(true);
    expect((await api.sales('2026-11-04')).totals).toEqual({ totalCents: 0, count: 0 });
  });

  it('has the days before with their outcomes: checked out, walk-ins, cancellations', async () => {
    const day = await api.appointments('2026-11-03');
    expect(day.filter((a) => a.status === 'completed')).toHaveLength(11);
    expect(day.filter((a) => a.status === 'cancelled')).toHaveLength(1);
    const sales = await api.sales('2026-11-03');
    expect(sales.totals).toEqual({ totalCents: 75800, count: 17 });
    expect(sales.sales.filter((s) => s.appointmentId === null)).toHaveLength(6);
    // Newest first.
    expect(sales.sales.map((s) => s.soldAt)).toEqual([...sales.sales.map((s) => s.soldAt)].sort().reverse());
  });

  it('is the same every time a day is shown, and only the last 8 weeks have history', async () => {
    const ctx = { catalog: (await import('./api')).DEMO_CATALOG, today: '2026-11-04', historyBefore: Date.parse('2026-11-04T16:00:00Z') };
    expect(sampleDay(ctx, '2026-10-20')).toEqual(sampleDay(ctx, '2026-10-20'));
    // 56 days before November 4 is September 9.
    expect(sampleDay(ctx, '2026-09-09').appointments.length).toBeGreaterThan(0);
    expect(sampleDay(ctx, '2026-09-08')).toEqual({ appointments: [], sales: [] });
    expect(dayOfId(dayId('anything', '2026-11-04'))).toBe('2026-11-04');
  });

  it('keeps no one signed in who wasn’t: a token it doesn’t know is turned away, and the session ends', async () => {
    session.signIn({
      token: newToken(),
      session: { id: 'x', name: 'Elsewhere', createdAt: now.toISOString(), lastUsedAt: now.toISOString(), expiresAt: '2027-01-01T00:00:00Z', current: true },
    });
    expect(await rejects(api.appointments('2026-11-04'))).toMatchObject({ code: 'unauthorized', status: 401 });
    expect(session.current()).toMatchObject({ session: null, reason: 'expired' });
  });
});

describe('checking out, like the server', () => {
  it('checks out an appointment with products, marks it paid, and answers a retry with the same sale', async () => {
    const nate = byName(await api.appointments('2026-11-04'), 'Nate Sample');
    const body = {
      barberId: nate.barberId,
      appointmentId: nate.id,
      method: 'cash' as const,
      items: [
        { kind: 'service' as const, serviceId: nate.serviceId },
        { kind: 'product' as const, productId: POMADE.id, quantity: 2 },
      ],
    };
    const key = newToken();
    const sale = await api.createSale(body, key);
    expect(sale).toMatchObject({ barberName: 'Izzy', customerName: 'Nate Sample', method: 'cash', totalCents: 9100, voidedAt: null });
    expect(sale.items.map((i) => [i.name, i.quantity, i.unitCents, i.totalCents])).toEqual([
      ['Haircut & Beard', 1, 5500, 5500],
      ['Sample pomade', 2, 1800, 3600],
    ]);
    const after = byName(await api.appointments('2026-11-04'), 'Nate Sample');
    expect(after).toMatchObject({
      status: 'completed',
      sale: { id: sale.id, totalCents: 9100, method: 'cash' },
      payment: { status: 'paid', amountCents: 9100 },
    });

    // The same key again (an answer that was lost): the same sale, nothing recorded twice.
    expect(await api.createSale(body, key)).toEqual(sale);
    expect((await api.sales('2026-11-04')).totals).toEqual({ totalCents: 9100, count: 1 });
    // The same key for something else is turned down.
    expect(await rejects(api.createSale({ ...body, method: 'other' }, key))).toMatchObject({
      code: 'invalid_request',
      message: 'That sale key was already used for another sale.',
    });
    // A checked-out appointment can't be checked out again, nor changed until its sale is voided.
    expect(await rejects(api.createSale(body, newToken()))).toMatchObject({ code: 'already_checked_out', status: 409 });
    expect(await rejects(api.setStatus(nate.id, 'booked'))).toMatchObject({
      code: 'already_checked_out',
      message: 'This appointment was checked out. Void its sale first, then change it.',
    });
  });

  it('turns down a cancelled appointment, an unknown barber, a product with no price, and a sale over $10,000', async () => {
    const today = await api.appointments('2026-11-04');
    const brandon = byName(today, 'Brandon Sample');
    await api.setStatus(brandon.id, 'cancelled');
    const service = { kind: 'service' as const, serviceId: brandon.serviceId };
    expect(
      await rejects(api.createSale({ barberId: brandon.barberId, appointmentId: brandon.id, method: 'cash', items: [service] }, newToken())),
    ).toMatchObject({
      code: 'not_checkoutable',
      status: 409,
    });
    expect(
      await rejects(api.createSale({ barberId: 'nobody', method: 'cash', items: [{ kind: 'custom', name: 'Tip', unitCents: 500 }] }, newToken())),
    ).toMatchObject({
      message: "That barber isn't on the team. Pick who did the service.",
    });
    const tonic = SAMPLE_PRODUCTS.find((p) => p.priceCents === null)!;
    expect(
      await rejects(api.createSale({ barberId: 'julian-ramos', method: 'cash', items: [{ kind: 'product', productId: tonic.id }] }, newToken())),
    ).toMatchObject({
      message: 'Sample hair tonic has no price. Enter the price.',
    });
    // Flowxbori has two prices for a haircut: the price must be given.
    expect(
      await rejects(api.createSale({ barberId: 'flowxbori', method: 'cash', items: [{ kind: 'service', serviceId: 'haircut' }] }, newToken())),
    ).toMatchObject({
      message: 'Flowxbori has more than one price for Haircut. Enter the price.',
    });
    expect(
      await rejects(
        api.createSale(
          {
            barberId: 'julian-ramos',
            method: 'cash',
            items: [
              { kind: 'custom', name: 'A lot', unitCents: 1_000_000 },
              { kind: 'custom', name: 'More', unitCents: 1 },
            ],
          },
          newToken(),
        ),
      ),
    ).toMatchObject({ message: 'A sale can be at most $10,000. Split it into two sales.' });
  });

  it('voids a sale: it stops counting, its appointment is unpaid again and stays done, and voiding again answers the same', async () => {
    const nate = byName(await api.appointments('2026-11-04'), 'Nate Sample');
    const sale = await api.createSale(
      { barberId: nate.barberId, appointmentId: nate.id, method: 'cash', items: [{ kind: 'service', serviceId: nate.serviceId }] },
      newToken(),
    );
    const voided = await api.voidSale(sale.id, 'Rang up twice');
    expect(voided).toMatchObject({ sale: { voidReason: 'Rang up twice' }, message: 'The sale was voided, so it no longer counts in your sales.' });
    expect(voided.sale.voidedAt).not.toBeNull();
    expect(await api.voidSale(sale.id, null)).toEqual(voided);
    expect(byName(await api.appointments('2026-11-04'), 'Nate Sample')).toMatchObject({
      status: 'completed',
      sale: null,
      payment: { status: 'unpaid', amountCents: null },
    });
    expect((await api.sales('2026-11-04')).totals).toEqual({ totalCents: 0, count: 0 });
  });

  it('voids a card sale without refunding it, and says the refund is made in Stripe', async () => {
    const day = await api.sales('2026-11-03');
    const card = day.sales.find((s) => s.method === 'card' && s.appointmentId !== null)!;
    const result = await api.voidSale(card.id, null);
    expect(result.message).toBe(
      "The sale was voided, so it no longer counts in your sales. Voiding doesn't refund the card: refunds are made in the Stripe Dashboard.",
    );
    const appointment = (await api.appointments('2026-11-03')).find((a) => a.id === card.appointmentId)!;
    // The card paid it: it stays paid.
    expect(appointment).toMatchObject({ sale: null, payment: { status: 'paid', amountCents: card.totalCents } });
  });
});

describe('statuses and fees, like the server', () => {
  it('marks a no-show with a card on file only once it has started, and charges the fee once Stripe is connected', async () => {
    const kim = byName(await api.appointments('2026-11-04'), 'Kim Sample');
    expect(kim.card).not.toBeNull();
    expect(await rejects(api.setStatus(kim.id, 'noShow'))).toMatchObject({
      code: 'not_started',
      message: 'You can mark a no-show once the appointment has started.',
    });
    now = new Date('2026-11-04T20:30:00Z'); // 12:30 PM, Kim's 12 PM appointment has started
    expect((await api.setStatus(kim.id, 'noShow')).noShowFee).toMatchObject({ status: 'none', reason: 'noShow' });
    expect(await rejects(api.chargeFee(kim.id))).toMatchObject({
      code: 'stripe_not_configured',
      status: 503,
      message: 'Connect Stripe in Settings to take card payments.',
    });
    expect(await api.connectStripe()).toMatchObject({ url: '/business/settings?stripe=active' });
    expect(await api.stripe()).toMatchObject({ status: 'active', businessName: 'Izzy Clipz Barbershop' });
    const charged = await api.chargeFee(kim.id);
    expect(charged.noShowFee).toMatchObject({ status: 'charged', amountCents: 3500, reason: 'noShow', chargedAt: '2026-11-04T20:30:00Z' });
    // Charging again changes nothing.
    expect(await api.chargeFee(kim.id)).toEqual(charged);
  });

  it('turns down a fee there is nothing to charge for, and declines the card that ends in 0002', async () => {
    await api.connectStripe();
    const today = await api.appointments('2026-11-04');
    expect(await rejects(api.chargeFee(byName(today, 'Nate Sample').id))).toMatchObject({
      code: 'not_chargeable',
      message: "This booking has no card on file, so there's no fee to charge.",
    });
    const gabe = byName(today, 'Gabe Sample');
    expect(gabe.card?.last4).toBe('0002');
    expect(await rejects(api.chargeFee(gabe.id))).toMatchObject({ code: 'not_chargeable', message: 'Mark the appointment as a no-show first.' });
    now = new Date('2026-11-04T19:00:00Z');
    await api.setStatus(gabe.id, 'noShow');
    expect((await api.chargeFee(gabe.id)).noShowFee).toMatchObject({
      status: 'declined',
      message: 'The card was declined. Ask the client to pay at the shop.',
    });
  });

  it('cancels as the shop and reopens, unless another booking took the time', async () => {
    const brandon = byName(await api.appointments('2026-11-04'), 'Brandon Sample');
    expect(await api.setStatus(brandon.id, 'cancelled')).toMatchObject({ status: 'cancelled', cancelledBy: 'shop' });
    expect(await api.setStatus(brandon.id, 'booked')).toMatchObject({ status: 'booked', cancelledBy: null });
  });
});

describe('analytics, with the definitions of docs/analytics.md, worked out by hand', () => {
  it('a day of history (Tuesday, November 3): 17 checkouts, 6 of them walk-ins', async () => {
    const a = await api.analytics({ from: '2026-11-03', to: '2026-11-03', barberId: null });
    // 17 live sales, one service each: 13 haircuts ($495), 3 military haircuts ($75), a haircut & beard ($55).
    expect(a.totals).toEqual({
      salesCents: 75800,
      servicesCents: 62500,
      productsCents: 13300,
      otherCents: 0,
      feesCents: 0,
      servicesCount: 17,
      productsCount: 9,
      // 11 appointments marked done (all checked out), and 6 walk-ins.
      clientsServed: 17,
      checkouts: 17,
      // $758 / 17 = $44.588…
      averageTicketCents: 4459,
    });
    expect(a.productivity).toEqual({
      // Tuesday 10 AM – 7 PM, 9 hours, for 5 barbers.
      openMinutes: 2700,
      // 7 appointments of 45 minutes and 4 of an hour; the cancelled one doesn't count.
      bookedMinutes: 555,
      chairTimeBooked: 555 / 2700,
      appointments: { booked: 0, completed: 11, noShows: 0, cancelled: 1, lateCancellations: 0, upcoming: 0 },
      completionRate: 1,
      noShowRate: 0,
      // $758 × 60 / 2700 minutes = $16.84 an hour.
      salesPerHourCents: 1684,
      // 7 of the 17 sales had a product.
      productAttachRate: 7 / 17,
    });
    expect(a.leaderboard.map((e) => [e.rank, e.name, e.salesCents, e.servicesCount, e.productsCount, e.clientsServed])).toEqual([
      [1, 'Cristian', 22700, 5, 3, 5],
      [2, 'Julian', 16100, 4, 2, 4],
      [3, 'Izzy', 13500, 3, 2, 3],
      [4, 'Flowxbori', 13000, 3, 1, 3],
      [5, 'Carlos', 10500, 2, 1, 2],
    ]);
    expect(a.topBarber).toEqual({ barberId: 'cristian-ceja', name: 'Cristian', salesCents: 22700, servicesCount: 5, productsCount: 3 });
    expect(a.services).toEqual([
      { serviceId: 'haircut', name: 'Haircut', count: 13, salesCents: 49500 },
      { serviceId: 'military-haircut', name: 'Military Haircut', count: 3, salesCents: 7500 },
      { serviceId: 'haircut-and-beard', name: 'Haircut & Beard', count: 1, salesCents: 5500 },
    ]);
    expect(a.products.map((p) => [p.name, p.quantity, p.salesCents])).toEqual([
      ['Sample beard oil', 7, 10500],
      ['Sample shampoo', 1, 1600],
      ['Sample sea salt spray', 1, 1200],
    ]);
    expect(a.series).toEqual([
      { date: '2026-11-03', salesCents: 75800, servicesCents: 62500, productsCents: 13300, otherCents: 0, feesCents: 0, servicesCount: 17, productsCount: 9 },
    ]);
  });

  it('today, as the owner checks out, marks, cancels, voids and charges', async () => {
    let today = await api.appointments('2026-11-04');
    // A checkout: Nate's haircut & beard ($55) and two pomades ($36), in cash, for Izzy.
    const nate = byName(today, 'Nate Sample');
    await api.createSale(
      {
        barberId: nate.barberId,
        appointmentId: nate.id,
        method: 'cash',
        items: [
          { kind: 'service', serviceId: nate.serviceId },
          { kind: 'product', productId: POMADE.id, quantity: 2 },
        ],
      },
      newToken(),
    );
    // A walk-in for Carlos: a $25 gift card and a beard oil ($15), paid another way.
    await api.createSale(
      {
        barberId: 'carlos-rafael',
        method: 'other',
        items: [
          { kind: 'custom', name: 'Gift card', unitCents: 2500 },
          { kind: 'product', productId: BEARD_OIL.id },
        ],
      },
      newToken(),
    );
    // A sale rung up by mistake, then voided: it doesn't count.
    const mistake = await api.createSale({ barberId: 'julian-ramos', method: 'cash', items: [{ kind: 'custom', name: 'Other', unitCents: 2000 }] }, newToken());
    await api.voidSale(mistake.id, 'Rang up by mistake');
    // Carlos Sample's haircut with Izzy ($40) marked done without a checkout: it counts at its booked price.
    await api.setStatus(byName(today, 'Carlos Sample').id, 'completed');
    // Brandon's appointment cancelled by the shop.
    await api.setStatus(byName(today, 'Brandon Sample').id, 'cancelled');
    // At 12:30 PM Kim didn't come: a no-show, and her $35 fee charged to her card.
    now = new Date('2026-11-04T20:30:00Z');
    const kim = byName(today, 'Kim Sample');
    await api.setStatus(kim.id, 'noShow');
    await api.connectStripe();
    await api.chargeFee(kim.id);

    const a = await api.analytics({ from: '2026-11-04', to: '2026-11-04', barberId: null });
    expect(a.totals).toEqual({
      // $55 + $40 services, $51 products, $25 other, $35 fee.
      salesCents: 20600,
      servicesCents: 9500,
      productsCents: 5100,
      otherCents: 2500,
      feesCents: 3500,
      servicesCount: 2,
      productsCount: 3,
      // Nate and Carlos Sample done, and the walk-in.
      clientsServed: 3,
      // Two live sales and one appointment done without a checkout.
      checkouts: 3,
      // ($95 + $51 + $25) / 3, fees left out.
      averageTicketCents: 5700,
    });
    expect(a.productivity.appointments).toEqual({ booked: 8, completed: 2, noShows: 1, cancelled: 1, lateCancellations: 0, upcoming: 7 });
    expect(a.productivity).toMatchObject({
      openMinutes: 2700,
      // Done: 60 + 60; still booked: four of 45 minutes, three of an hour, and Gabe's 45.
      bookedMinutes: 525,
      completionRate: 2 / 3,
      noShowRate: 1 / 3,
      // $171 × 60 / 2700 minutes.
      salesPerHourCents: 380,
      productAttachRate: 1,
    });
    expect(a.leaderboard.map((e) => [e.rank, e.name, e.salesCents])).toEqual([
      [1, 'Izzy', 13100],
      [2, 'Carlos', 4000],
      [3, 'Cristian', 3500],
      [4, 'Flowxbori', 0],
      [4, 'Julian', 0],
    ]);
    expect(a.topBarber).toEqual({ barberId: 'israel-flores', name: 'Izzy', salesCents: 13100, servicesCount: 2, productsCount: 2 });
    expect(a.services).toEqual([
      { serviceId: 'haircut-and-beard', name: 'Haircut & Beard', count: 1, salesCents: 5500 },
      { serviceId: 'haircut', name: 'Haircut', count: 1, salesCents: 4000 },
    ]);
    expect(a.products.map((p) => [p.name, p.quantity, p.salesCents])).toEqual([
      ['Sample pomade', 2, 3600],
      ['Sample beard oil', 1, 1500],
    ]);

    // One barber's page: only his numbers; the leaderboard and top barber stay the whole shop's.
    const cristian = await api.analytics({ from: '2026-11-04', to: '2026-11-04', barberId: 'cristian-ceja' });
    expect(cristian.totals).toMatchObject({ salesCents: 3500, feesCents: 3500, servicesCount: 0, checkouts: 0, clientsServed: 0, averageTicketCents: 0 });
    expect(cristian.productivity).toMatchObject({
      openMinutes: 540,
      bookedMinutes: 60,
      appointments: { booked: 1, completed: 0, noShows: 1, cancelled: 0, lateCancellations: 0, upcoming: 1 },
      completionRate: 0,
      noShowRate: 1,
    });
    expect(cristian.topBarber?.name).toBe('Izzy');
    expect(cristian.leaderboard).toEqual(a.leaderboard);

    // This week so far, Monday to today: a day for each, and the 3 days before to compare with.
    const week = await api.analytics({ from: '2026-11-02', to: '2026-11-04', barberId: null });
    expect(week.granularity).toBe('day');
    expect(week.series.map((s) => s.date)).toEqual(['2026-11-02', '2026-11-03', '2026-11-04']);
    expect(week.series[1]).toMatchObject({ salesCents: 75800 });
    expect(week.series[2]).toEqual({
      date: '2026-11-04',
      salesCents: 20600,
      servicesCents: 9500,
      productsCents: 5100,
      otherCents: 2500,
      feesCents: 3500,
      servicesCount: 2,
      productsCount: 3,
    });
    expect(week.previous).toMatchObject({ from: '2026-10-30', to: '2026-11-01' });
    // The year so far, by month.
    const year = await api.analytics({ from: '2026-01-01', to: '2026-11-04', barberId: null });
    expect(year.granularity).toBe('month');
    expect(year.series).toHaveLength(11);
  });

  it('keeps a deleted product’s name, and turns down a range the server would', async () => {
    await api.createSale({ barberId: 'julian-ramos', method: 'cash', items: [{ kind: 'product', productId: POMADE.id }] }, newToken());
    await api.deleteProduct(POMADE.id);
    const a = await api.analytics({ from: '2026-11-04', to: '2026-11-04', barberId: null });
    expect(a.products).toEqual([{ productId: null, name: 'Sample pomade', quantity: 1, salesCents: 1800 }]);
    expect(await rejects(api.analytics({ from: '2026-11-05', to: '2026-11-04', barberId: null }))).toMatchObject({ message: 'to must be on or after from.' });
    expect(await rejects(api.analytics({ from: '2025-11-03', to: '2026-11-04', barberId: null }))).toMatchObject({
      message: 'Ask for at most 366 days at a time.',
    });
    expect(await rejects(api.analytics({ from: '2026-11-04', to: '2026-11-04', barberId: 'nobody' }))).toMatchObject({
      message: "That barber isn't on the team.",
    });
  });
});

describe('products, settings and computers', () => {
  it('adds, edits and deletes products with the server’s checks', async () => {
    expect(await rejects(api.createProduct({ name: '  ', description: null, priceCents: 1000, visible: true }))).toMatchObject({
      message: 'Give the product a name.',
    });
    const created = await api.createProduct({ name: 'Hair clay', description: ' Strong hold ', priceCents: 2000, visible: false });
    expect(created).toMatchObject({ name: 'Hair clay', description: 'Strong hold', priceCents: 2000, visible: false, imageUrl: null });
    const edited = await api.updateProduct(created.id, { priceCents: null, visible: true });
    expect(edited).toMatchObject({ priceCents: null, visible: true });
    const photo = await api.uploadProductPhoto(created.id, new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xe0])], { type: 'image/jpeg' }));
    expect(photo.imageUrl).toMatch(/^data:image\/jpeg;base64,/);
    await api.deleteProduct(created.id);
    expect((await api.products()).some((p) => p.id === created.id)).toBe(false);
    expect(await rejects(api.deleteProduct(created.id))).toMatchObject({ code: 'not_found', status: 404 });
  });

  it('saves the no-show settings with the server’s limits', async () => {
    expect(await api.noShowSettings()).toEqual({
      enabled: false,
      feeMode: 'percent',
      percent: 100,
      flatCents: 2000,
      lateCancelEnabled: true,
      lateCancelWindowMinutes: 60,
    });
    expect(await api.updateNoShowSettings({ enabled: true, feeMode: 'flat', flatCents: 2500 })).toMatchObject({
      enabled: true,
      feeMode: 'flat',
      flatCents: 2500,
    });
    expect(await rejects(api.updateNoShowSettings({ flatCents: 60_000 }))).toMatchObject({ message: 'Pick a flat fee from $0.50 to $500.' });
    expect(await rejects(api.updateNoShowSettings({ lateCancelWindowMinutes: 10 }))).toMatchObject({
      message: 'Pick a late-cancellation window from 30 minutes to 48 hours.',
    });
  });

  it('lists the computers signed in, signs one out, and all of them, this one too', async () => {
    const computers = await api.computerSessions();
    expect(computers.map((c) => [c.name, c.current])).toEqual([
      ['Chrome on Mac', true],
      ['Safari on iPad (sample)', false],
    ]);
    await api.signOutComputer(computers[1]!.id);
    expect(await api.computerSessions()).toHaveLength(1);
    await api.signOutAllComputers();
    expect(await rejects(api.products())).toMatchObject({ code: 'unauthorized', status: 401 });
    expect(session.current().reason).toBe('expired');
  });

  it('keeps everything in this browser, and Reset brings the sample shop back', async () => {
    const nate = byName(await api.appointments('2026-11-04'), 'Nate Sample');
    await api.setStatus(nate.id, 'completed');
    await api.connectStripe();
    expect(localStorage.getItem(DEMO_BUSINESS_KEY)).toContain('"connectedAt"');
    // Another page (a reload) sees the same.
    const again = createDemoOwnerApi({ now: () => now, latencyMs: 0 });
    expect(byName(await again.appointments('2026-11-04'), 'Nate Sample').status).toBe('completed');
    await again.resetDemo();
    expect(byName(await again.appointments('2026-11-04'), 'Nate Sample').status).toBe('booked');
    expect((await again.stripe()).status).toBe('notConnected');
    // Still signed in after the reset.
    expect(session.current().session).not.toBeNull();
  });
});
