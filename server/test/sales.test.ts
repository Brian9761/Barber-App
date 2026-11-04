import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { CARD_SALE_MESSAGE } from '../src/sales.js';
import { RESPONSES } from './helpers/contract.js';
import { useHarness } from './helpers/harness.js';

// Cash and other sales (POST /api/owner/sales), the day's sales, voiding, and what a checkout
// does to its appointment. Card sales are in test/card-sales.test.ts.

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });
const owner = { owner: true } as const;

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const IZZY60 = 'israel-flores/0d069a9e-c5ea-4cca-ae34-3f38bf668940';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const sell = (body: Record<string, unknown>, headers?: Record<string, string>) =>
  h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', ...body }, ...(headers ? { headers } : {}) });
const voidSale = (id: string, body: Record<string, unknown> = {}) => h.call('POST', `/api/owner/sales/${id}/void`, { ...owner, body });
const salesOf = (date: string) => h.call('GET', `/api/owner/sales?date=${date}`, owner);

async function walkIn(options: { offeringId?: string; start?: string; name?: string } = {}) {
  const res = await h.call('POST', '/api/owner/appointments', {
    ...owner,
    body: { offeringId: options.offeringId ?? FLOW45, start: options.start ?? '2026-11-02T20:00:00Z', customer: { name: options.name ?? 'Ben' } },
  });
  expect(res.status, res.text).toBe(201);
  return res.body.appointment as { id: string };
}

async function ownerAppointment(id: string) {
  const list = await h.call('GET', '/api/owner/appointments?from=2026-11-01&to=2026-11-30', owner);
  return list.body.appointments.find((a: { id: string }) => a.id === id);
}

async function product(name: string, priceCents?: number | null, visible = true) {
  const res = await h.call('POST', '/api/owner/products', { ...owner, body: { name, priceCents, visible } });
  expect(res.status, res.text).toBe(201);
  return res.body.product.id as string;
}

const setStatus = (id: string, status: string) => h.call('PATCH', `/api/owner/appointments/${id}`, { ...owner, body: { status } });

describe('POST /api/owner/sales', () => {
  it('records a cash sale of every kind of item, with names and prices filled in', async () => {
    const pomade = await product('Matte pomade', 1800);
    const spray = await product('Sea salt spray', null);
    const res = await sell({
      barberId: 'israel-flores',
      customerName: '  Andre ',
      items: [
        { kind: 'service', serviceId: 'haircut' },
        { kind: 'product', productId: pomade, quantity: 2 },
        { kind: 'product', productId: spray, unitCents: 1200 },
        { kind: 'custom', name: ' Gift card ', unitCents: 2500 },
      ],
    });
    expect(res.status, res.text).toBe(201);
    expect(RESPONSES['sale-created'].safeParse(res.body).success).toBe(true);
    expect(res.body).toEqual({
      sale: {
        id: expect.stringMatching(UUID),
        barberId: 'israel-flores',
        barberName: 'Izzy',
        appointmentId: null,
        customerName: 'Andre',
        method: 'cash',
        paymentIntentId: null,
        totalCents: 4000 + 3600 + 1200 + 2500,
        items: [
          { kind: 'service', serviceId: 'haircut', productId: null, name: 'Haircut', quantity: 1, unitCents: 4000, totalCents: 4000 },
          { kind: 'product', serviceId: null, productId: pomade, name: 'Matte pomade', quantity: 2, unitCents: 1800, totalCents: 3600 },
          { kind: 'product', serviceId: null, productId: spray, name: 'Sea salt spray', quantity: 1, unitCents: 1200, totalCents: 1200 },
          { kind: 'custom', serviceId: null, productId: null, name: 'Gift card', quantity: 1, unitCents: 2500, totalCents: 2500 },
        ],
        soldAt: '2026-11-02T19:10:00Z',
        voidedAt: null,
        voidReason: null,
      },
    });
    // Names and prices are the ones at the time: renaming or repricing later changes nothing.
    await h.call('PATCH', `/api/owner/products/${pomade}`, { ...owner, body: { name: 'Clay pomade', priceCents: 2000 } });
    expect((await salesOf('2026-11-02')).body.sales[0].items[1]).toMatchObject({ name: 'Matte pomade', unitCents: 1800 });
  });

  it('an other (Zelle, Cash App…) sale; a free item; a price entered for a service the barber doesn’t offer', async () => {
    const other = await sell({ barberId: 'julian-ramos', method: 'other', items: [{ kind: 'service', serviceId: 'haircut', unitCents: 3000 }] });
    expect(other.status).toBe(201);
    expect(other.body.sale).toMatchObject({ method: 'other', totalCents: 3000, customerName: null });
    const free = await sell({ barberId: 'carlos-rafael', items: [{ kind: 'service', serviceId: 'eyebrows' }] });
    expect(free.body.sale).toMatchObject({ totalCents: 0, items: [{ name: 'Eyebrows', unitCents: 0 }] });
    // Eyebrows are Carlos's; Izzy can still ring them up with a price.
    const noPrice = await sell({ barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'eyebrows' }] });
    expect(noPrice.status).toBe(400);
    expect(noPrice.body.error).toEqual({ code: 'invalid_request', message: "Izzy doesn't offer Eyebrows. Enter the price." });
    const priced = await sell({ barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'eyebrows', unitCents: 500, quantity: 2 }] });
    expect(priced.body.sale.items[0]).toMatchObject({ name: 'Eyebrows', quantity: 2, unitCents: 500, totalCents: 1000 });
    // Flowxbori has two haircut prices ($35 and $40), so a walk-in's needs the price.
    const two = await sell({ barberId: 'flowxbori', items: [{ kind: 'service', serviceId: 'haircut' }] });
    expect(two.body.error).toEqual({ code: 'invalid_request', message: 'Flowxbori has more than one price for Haircut. Enter the price.' });
  });

  it('checks out an appointment: the barber, client and price default to it; it becomes completed and paid', async () => {
    const pomade = await product('Matte pomade', 1800, false); // hidden from the app: still sells
    // Flowxbori's 45-minute haircut ($35), booked for noon by phone.
    const appointment = await walkIn();
    const res = await sell({
      appointmentId: appointment.id.toUpperCase(),
      method: 'other',
      items: [
        { kind: 'service', serviceId: 'haircut' },
        { kind: 'product', productId: pomade },
      ],
    });
    expect(res.status, res.text).toBe(201);
    expect(res.body.sale).toMatchObject({
      barberId: 'flowxbori',
      barberName: 'Flowxbori',
      appointmentId: appointment.id,
      customerName: 'Ben',
      method: 'other',
      totalCents: 3500 + 1800,
      items: [{ name: 'Haircut', unitCents: 3500 }, { name: 'Matte pomade', unitCents: 1800 }],
    });
    const after = await ownerAppointment(appointment.id);
    expect(after).toMatchObject({
      status: 'completed',
      payment: { status: 'paid', amountCents: 5300, paidAt: '2026-11-02T19:10:00Z' },
      sale: { id: res.body.sale.id, totalCents: 5300, method: 'other' },
    });
    // Somebody else may get the credit, and the client's name can be changed.
    const second = await walkIn({ start: '2026-11-02T22:00:00Z', name: 'Cy' });
    const credited = await sell({ appointmentId: second.id, barberId: 'cristian-ceja', customerName: 'Cyrus', items: [{ kind: 'service', serviceId: 'haircut' }] });
    // The appointment's own service keeps its booked price, whoever gets the credit.
    expect(credited.body.sale).toMatchObject({ barberId: 'cristian-ceja', customerName: 'Cyrus', totalCents: 3500 });
  });

  it('an appointment already completed can be checked out; a cancelled or no-show one can’t', async () => {
    const done = await walkIn();
    await setStatus(done.id, 'completed');
    expect((await sell({ appointmentId: done.id, items: [{ kind: 'service', serviceId: 'haircut' }] })).status).toBe(201);
    expect((await ownerAppointment(done.id)).status).toBe('completed');

    const cancelled = await walkIn({ start: '2026-11-02T22:00:00Z' });
    await setStatus(cancelled.id, 'cancelled');
    const refused = await sell({ appointmentId: cancelled.id, items: [{ kind: 'service', serviceId: 'haircut' }] });
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({
      code: 'not_checkoutable',
      message: "This appointment was cancelled, so it can't be checked out. Reopen it first, or check out without the appointment.",
    });
    const noShow = await walkIn({ start: '2026-11-02T23:00:00Z' });
    await setStatus(noShow.id, 'noShow');
    const noShowRefused = await sell({ appointmentId: noShow.id, items: [{ kind: 'service', serviceId: 'haircut' }] });
    expect(noShowRefused.status).toBe(409);
    expect(noShowRefused.body.error.message).toBe(
      "This appointment was marked a no-show, so it can't be checked out. Reopen it first, or check out without the appointment.",
    );
    // Nothing was recorded for them.
    expect((await salesOf('2026-11-02')).body.totals).toEqual({ totalCents: 3500, count: 1 });
  });

  it('one live sale per appointment; it stays completed until the sale is voided', async () => {
    const appointment = await walkIn();
    const first = await sell({ appointmentId: appointment.id, items: [{ kind: 'service', serviceId: 'haircut' }] });
    expect(first.status).toBe(201);
    const again = await sell({ appointmentId: appointment.id, items: [{ kind: 'custom', name: 'Tip', unitCents: 500 }] });
    expect(again.status).toBe(409);
    expect(again.body.error).toEqual({ code: 'already_checked_out', message: 'This appointment was already checked out.' });
    // Checked out: it can't be reopened, cancelled or made a no-show, but "completed" again is fine.
    for (const status of ['booked', 'noShow', 'cancelled']) {
      const res = await setStatus(appointment.id, status);
      expect(res.status, status).toBe(409);
      expect(res.body.error).toEqual({ code: 'already_checked_out', message: 'This appointment was checked out. Void its sale first, then change it.' });
    }
    expect((await setStatus(appointment.id, 'completed')).status).toBe(200);
    // Two checkouts at the same moment: one wins.
    const other = await walkIn({ start: '2026-11-02T22:00:00Z' });
    const race = await Promise.all([1, 2].map(() => sell({ appointmentId: other.id, items: [{ kind: 'service', serviceId: 'haircut' }] })));
    expect(race.map((r) => r.status).sort()).toEqual([201, 409]);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM sales WHERE appointment_id = $1', [other.id])).rows[0].n).toBe(1);
  });

  it('validates the ticket, in plain words', async () => {
    const pomade = await product('Matte pomade', 1800);
    const spray = await product('Sea salt spray', null);
    const service = { kind: 'service', serviceId: 'haircut' };
    const cases: [Record<string, unknown>, string, number?][] = [
      [{ method: 'card', barberId: 'israel-flores', items: [service] }, CARD_SALE_MESSAGE],
      [{ method: 'zelle', barberId: 'israel-flores', items: [service] }, 'method must be cash or other.'],
      [{ method: undefined, barberId: 'israel-flores', items: [service] }, 'method must be cash or other.'],
      [{ barberId: 'israel-flores', items: [] }, 'Add at least one item.'],
      [{ barberId: 'israel-flores', items: 'haircut' }, 'Send the items as a list.'],
      [{ barberId: 'israel-flores', items: Array.from({ length: 21 }, () => service) }, 'A sale can have at most 20 items.'],
      [{ barberId: 'israel-flores', items: [{ serviceId: 'haircut' }] }, 'Each item needs a kind: service, product or custom.'],
      [{ barberId: 'israel-flores', items: [{ kind: 'gift', name: 'x' }] }, 'Each item needs a kind: service, product or custom.'],
      [{ barberId: 'israel-flores', items: [{ ...service, quantity: 0 }] }, 'The quantity must be a whole number from 1 to 99.'],
      [{ barberId: 'israel-flores', items: [{ ...service, quantity: 100 }] }, 'The quantity must be a whole number from 1 to 99.'],
      [{ barberId: 'israel-flores', items: [{ ...service, quantity: 1.5 }] }, 'The quantity must be a whole number from 1 to 99.'],
      [{ barberId: 'israel-flores', items: [{ ...service, unitCents: -1 }] }, 'Prices must be whole cents, from $0 to $10,000.'],
      [{ barberId: 'israel-flores', items: [{ ...service, unitCents: 12.5 }] }, 'Prices must be whole cents, from $0 to $10,000.'],
      [{ barberId: 'israel-flores', items: [{ ...service, unitCents: '4000' }] }, 'Prices must be whole cents, from $0 to $10,000.'],
      [{ barberId: 'israel-flores', items: [{ kind: 'custom', name: 'Gift card' }] }, 'Enter the price of each custom item.'],
      [{ barberId: 'israel-flores', items: [{ kind: 'custom', name: '  ', unitCents: 100 }] }, 'Give the item a name, like Gift card.'],
      [{ barberId: 'israel-flores', items: [{ kind: 'custom', name: 'n'.repeat(81), unitCents: 100 }] }, 'Keep the item name to 80 characters or fewer.'],
      [
        { barberId: 'israel-flores', items: [{ kind: 'custom', name: 'Gift card', unitCents: 600_000 }, { kind: 'custom', name: 'Gift card', unitCents: 400_001 }] },
        'A sale can be at most $10,000. Split it into two sales.',
      ],
      [{ items: [service] }, 'Pick the barber who gets credit for this sale.'],
      [{ barberId: 'nobody', items: [service] }, "That barber isn't on the team. Pick who did the service."],
      [{ barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'buzz-cut' }] }, "That service isn't on the menu. Pick another, or add it as a custom item."],
      [{ barberId: 'israel-flores', items: [{ kind: 'product', productId: spray }] }, 'Sea salt spray has no price. Enter the price.'],
      [{ barberId: 'israel-flores', customerName: 'x'.repeat(61), items: [service] }, 'Keep the name to 60 characters or fewer.'],
      [{ barberId: 'israel-flores', items: [{ kind: 'product', productId: '00000000-0000-4000-8000-0000000000ee' }] }, "We couldn't find that product. It may have been deleted.", 404],
      [{ barberId: 'israel-flores', items: [{ kind: 'product', productId: 'pomade' }] }, "We couldn't find that product. It may have been deleted.", 404],
      [{ appointmentId: '00000000-0000-4000-8000-0000000000ee', items: [service] }, "We couldn't find that appointment.", 404],
      [{ appointmentId: 'tomorrow', items: [service] }, "We couldn't find that appointment.", 404],
    ];
    for (const [body, message, status = 400] of cases) {
      const res = await sell(body);
      expect(res.status, JSON.stringify(body)).toBe(status);
      expect(res.body.error.message, JSON.stringify(body)).toBe(message);
    }
    // A barber who left the team can't get new sales.
    await h.database.pool.query(`UPDATE barbers SET active = false WHERE id = 'julian-ramos'`);
    try {
      expect((await sell({ barberId: 'julian-ramos', items: [service] })).body.error.message).toBe("That barber isn't on the team. Pick who did the service.");
    } finally {
      await h.database.pool.query(`UPDATE barbers SET active = true WHERE id = 'julian-ramos'`);
    }
    // Exactly $10,000 is fine, and so is a product priced on the spot below its list price.
    expect((await sell({ barberId: 'israel-flores', items: [{ kind: 'custom', name: 'Gift card', unitCents: 1_000_000 }] })).status).toBe(201);
    expect((await sell({ barberId: 'israel-flores', items: [{ kind: 'product', productId: pomade, unitCents: 1500 }] })).body.sale.totalCents).toBe(1500);
    // Not JSON: 415, like every other body.
    expect((await h.call('POST', '/api/owner/sales', { ...owner, rawBody: 'method=cash', headers: { 'content-type': 'application/x-www-form-urlencoded' } })).status).toBe(415);
    expect((await salesOf('2026-11-02')).body.totals.count).toBe(2);
  });

  it('Idempotency-Key: Save again after a lost answer gets the same sale (200); racing copies record one', async () => {
    const appointment = await walkIn();
    const key = newManageToken();
    const body = { appointmentId: appointment.id, items: [{ kind: 'service', serviceId: 'haircut' }, { kind: 'custom', name: 'Tip', unitCents: 500 }] };
    const first = await sell(body, { 'idempotency-key': key });
    expect(first.status).toBe(201);
    // Later, the appointment is checked out (by this very sale), and the clock has moved: same answer.
    h.advance(5);
    const replay = await sell(body, { 'idempotency-key': key });
    expect(replay.status).toBe(200);
    expect(replay.body).toEqual(first.body);
    // The same key for a different ticket is refused; a malformed key too.
    const different = await sell({ ...body, items: [{ kind: 'service', serviceId: 'haircut', unitCents: 4000 }] }, { 'idempotency-key': key });
    expect(different.status).toBe(400);
    expect(different.body.error).toEqual({ code: 'invalid_request', message: 'That sale key was already used for another sale.' });
    expect((await sell({ ...body, method: 'other' }, { 'idempotency-key': key })).status).toBe(400);
    const malformed = await sell(body, { 'idempotency-key': 'abc' });
    expect(malformed.status).toBe(400);
    expect(malformed.body.error.message).toBe('Idempotency-Key must be 32 random bytes in base64url (43 characters).');
    // A voided sale replays as it is now (voided), and doesn't record another.
    await voidSale(first.body.sale.id);
    const afterVoid = await sell(body, { 'idempotency-key': key });
    expect(afterVoid.status).toBe(200);
    expect(afterVoid.body.sale.voidedAt).not.toBeNull();

    const walkInKey = newManageToken();
    const walkInSale = { barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'haircut' }] };
    const copies = await Promise.all([1, 2, 3].map(() => sell(walkInSale, { 'idempotency-key': walkInKey })));
    expect(copies.map((c) => c.status).sort()).toEqual([200, 200, 201]);
    expect(new Set(copies.map((c) => c.body.sale.id)).size).toBe(1);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM sales')).rows[0].n).toBe(2);
    // Without a key, the same walk-in rung up twice is two sales.
    await sell(walkInSale);
    await sell(walkInSale);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM sales')).rows[0].n).toBe(4);
  });
});

describe('POST /api/owner/sales/:id/void', () => {
  it('voids once (again answers the same), keeps the reason, and the appointment can be checked out again', async () => {
    const appointment = await walkIn();
    const sale = (await sell({ appointmentId: appointment.id, items: [{ kind: 'service', serviceId: 'haircut' }] })).body.sale;
    h.advance(3);
    const res = await voidSale(sale.id, { reason: '  Rang up the wrong client ' });
    expect(res.status, res.text).toBe(200);
    expect(RESPONSES['sale-voided'].safeParse(res.body).success).toBe(true);
    expect(res.body).toEqual({
      sale: { ...sale, voidedAt: '2026-11-02T19:13:00Z', voidReason: 'Rang up the wrong client' },
      message: 'The sale was voided, so it no longer counts in your sales.',
    });
    // The appointment stays completed, is unpaid again, and has no sale.
    expect(await ownerAppointment(appointment.id)).toMatchObject({
      status: 'completed',
      payment: { status: 'unpaid', amountCents: null, paidAt: null },
      sale: null,
    });
    // Voiding again changes nothing.
    h.advance(10);
    const again = await voidSale(sale.id, { reason: 'Another reason' });
    expect(again.status).toBe(200);
    expect(again.body).toEqual(res.body);
    // It can be checked out again now, and reopened only after that sale is voided too.
    const redo = await sell({ appointmentId: appointment.id, items: [{ kind: 'service', serviceId: 'haircut', unitCents: 4000 }] });
    expect(redo.status).toBe(201);
    expect((await ownerAppointment(appointment.id)).payment).toMatchObject({ status: 'paid', amountCents: 4000 });
    await voidSale(redo.body.sale.id);
    expect((await setStatus(appointment.id, 'booked')).status).toBe(200);
  });

  it('404 for unknown sales; the body is JSON with an optional short reason', async () => {
    const sale = (await sell({ barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'haircut' }] })).body.sale;
    expect((await voidSale('00000000-0000-4000-8000-0000000000ee')).status).toBe(404);
    expect((await voidSale('nope')).body.error).toEqual({ code: 'not_found', message: "We couldn't find that sale." });
    expect((await voidSale(sale.id, { reason: 'r'.repeat(201) })).status).toBe(400);
    expect((await voidSale(sale.id, { reason: 7 })).body.error.message).toBe('The reason must be text.');
    expect((await voidSale(sale.id, { reason: 'Wrong\u0000client' })).body.error.message).toBe('The reason has characters we can’t use.');
    const empty = await h.call('POST', `/api/owner/sales/${sale.id}/void`, owner);
    expect(empty.status).toBe(415);
    const voided = await voidSale(sale.id, { reason: '' });
    expect(voided.body.sale).toMatchObject({ voidReason: null, voidedAt: '2026-11-02T19:10:00Z' });
  });

  it('a card payment already paid the appointment: checking out and voiding leave the card’s numbers alone', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const appointment = await walkIn();
    // An older app took $30 by card for it, without a ticket.
    const { paymentIntentId } = (await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3000, appointmentId: appointment.id } })).body;
    h.stripe.succeed(paymentIntentId);
    await h.call('POST', `/api/owner/payments/${paymentIntentId}/complete`, owner);
    const paid = { status: 'paid', amountCents: 3000, paidAt: '2026-11-02T19:10:00Z' };
    h.advance(2);
    const sale = (await sell({ appointmentId: appointment.id, items: [{ kind: 'service', serviceId: 'haircut' }, { kind: 'custom', name: 'Tip', unitCents: 500 }] })).body.sale;
    expect(await ownerAppointment(appointment.id)).toMatchObject({ payment: paid, sale: { id: sale.id, totalCents: 4000, method: 'cash' } });
    await voidSale(sale.id);
    expect(await ownerAppointment(appointment.id)).toMatchObject({ status: 'completed', payment: paid, sale: null });
  });
});

describe('GET /api/owner/sales', () => {
  it('a shop-local day, newest first, voided sales listed but not counted', async () => {
    const haircut = { barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'haircut' }] };
    const morning = (await sell(haircut)).body.sale;
    h.setNow('2026-11-03T07:30:00Z'); // 11:30 PM PST, still Monday
    const late = (await sell({ ...haircut, method: 'other' })).body.sale;
    h.setNow('2026-11-03T07:40:00Z');
    const mistake = (await sell(haircut)).body.sale;
    await voidSale(mistake.id, { reason: 'Twice' });
    h.setNow('2026-11-03T08:05:00Z'); // 12:05 AM, Tuesday
    const tuesday = (await sell(haircut)).body.sale;

    const monday = await salesOf('2026-11-02');
    expect(monday.status).toBe(200);
    expect(RESPONSES['sales-day'].safeParse(monday.body).success).toBe(true);
    expect(monday.body.date).toBe('2026-11-02');
    expect(monday.body.sales.map((s: { id: string }) => s.id)).toEqual([mistake.id, late.id, morning.id]);
    expect(monday.body.sales[0]).toMatchObject({ voidedAt: '2026-11-03T07:40:00Z', voidReason: 'Twice' });
    expect(monday.body.totals).toEqual({ totalCents: 8000, count: 2 });
    // Today by default.
    const today = await h.call('GET', '/api/owner/sales', owner);
    expect(today.body).toMatchObject({ date: '2026-11-03', totals: { totalCents: 4000, count: 1 } });
    expect(today.body.sales.map((s: { id: string }) => s.id)).toEqual([tuesday.id]);
    expect((await salesOf('2026-11-04')).body).toEqual({ date: '2026-11-04', sales: [], totals: { totalCents: 0, count: 0 } });
    for (const query of ['date=2026-02-30', 'date=11/02/2026']) {
      expect((await h.call('GET', `/api/owner/sales?${query}`, owner)).status, query).toBe(400);
    }
  });

  it('a product deleted after it was sold keeps its name on the sale', async () => {
    const gel = await product('Old gel', 1000);
    await sell({ barberId: 'israel-flores', items: [{ kind: 'product', productId: gel }] });
    expect((await h.call('DELETE', `/api/owner/products/${gel}`, owner)).status).toBe(204);
    const day = await salesOf('2026-11-02');
    expect(day.body.sales[0].items).toEqual([
      { kind: 'product', serviceId: null, productId: null, name: 'Old gel', quantity: 1, unitCents: 1000, totalCents: 1000 },
    ]);
  });
});

describe('the checkout on the appointment', () => {
  it('the owner sees it on every owner view; the client never does', async () => {
    const booked = await h.call('POST', '/api/appointments', {
      body: { offeringId: IZZY60, start: '2026-11-02T22:00:00Z', customer: { name: 'Online Client', phone: '4425550123' } },
    });
    expect(booked.status, booked.text).toBe(201);
    expect(booked.body.appointment).not.toHaveProperty('sale');
    const { id } = booked.body.appointment;
    const sale = (await sell({ appointmentId: id, items: [{ kind: 'service', serviceId: 'haircut' }] })).body.sale;
    const summary = { id: sale.id, totalCents: 4000, method: 'cash' };
    expect((await ownerAppointment(id)).sale).toEqual(summary);
    expect((await setStatus(id, 'completed')).body.appointment.sale).toEqual(summary);
    const mine = await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': booked.body.manageToken } });
    expect(mine.status).toBe(200);
    expect(mine.body.appointment).not.toHaveProperty('sale');
    expect(mine.body.appointment).toMatchObject({ status: 'completed', payment: { status: 'paid', amountCents: 4000 } });
    expect(RESPONSES.appointment.safeParse(mine.body).success).toBe(true);
    const list = await h.call('GET', '/api/owner/appointments?date=2026-11-02', owner);
    expect(RESPONSES['owner-appointments'].safeParse(list.body).success).toBe(true);
  });
});
