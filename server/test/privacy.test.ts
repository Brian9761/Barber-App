import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { correctAppointment, findPersonData, forgetPerson, PRIVACY_USAGE, privacyCommand, PrivacyError } from '../src/privacy.js';
import { NAME_REMOVED } from '../src/retention.js';
import { protectionOn, useHarness } from './helpers/harness.js';

// The owner's tools for a client's privacy request (src/privacy.ts, scripts/privacy.ts): find and
// export one person's data, correct it, and forget it.

// Monday Nov 2 2026, 9:00 AM PST.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });
const owner = { owner: true } as const;
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const ANDRE = { name: 'Andre Sample', phone: '4425550170', email: 'Andre@Example.com' };

async function saveCard(): Promise<string> {
  await protectionOn(h);
  const token = newManageToken();
  const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip: '192.0.2.80' });
  h.stripe.completeSession(checkout.body.sessionId);
  expect((await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId }, ip: '192.0.2.80' })).status).toBe(201);
  return token;
}

async function book(token: string, start: string, customer: Record<string, string> = ANDRE) {
  const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
  const res = await h.call('POST', '/api/appointments', {
    headers: { 'x-card-token': token },
    body: { offeringId: FLOW45, start, customer, note: 'Low fade, please.', noShowPolicy: policy },
    ip: '203.0.113.81',
  });
  expect(res.status, res.text).toBe(201);
  return res.body.appointment.id as string;
}

/**
 * Andre: Tuesday's 10 AM, checked out in cash; a no-show the Thursday after, its fee charged; and
 * next Monday's, still to come. Ben, another client, books Wednesday. Now: Thursday Nov 5, 9 AM.
 */
async function history() {
  const card = await saveCard();
  const tuesday = await book(card, '2026-11-03T18:00:00Z');
  const thursday = await book(card, '2026-11-05T18:00:00Z');
  const nextWeek = await book(card, '2026-11-09T18:00:00Z');
  const ben = await book(await saveCard(), '2026-11-04T18:00:00Z', { name: 'Ben Other', phone: '4425550199' });
  h.setNow('2026-11-03T18:50:00Z');
  const sale = await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: tuesday, items: [{ kind: 'service', serviceId: 'haircut', unitCents: 3500 }] } });
  expect(sale.status, sale.text).toBe(201);
  h.setNow('2026-11-05T18:50:00Z');
  await h.call('PATCH', `/api/owner/appointments/${thursday}`, { ...owner, body: { status: 'noShow' } });
  expect((await h.call('POST', `/api/owner/appointments/${thursday}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('charged');
  h.setNow('2026-11-06T17:00:00Z');
  return { card, tuesday, thursday, nextWeek, ben, saleId: sale.body.sale.id as string };
}

describe('privacy:find', () => {
  it('exports everything kept about one person, with the terms they agreed to, and nobody else’s', async () => {
    const ids = await history();
    for (const phone of ['(442) 555-0170', '+1 442 555 0170', '4425550170']) {
      const found = await findPersonData(h.deps, { phone });
      expect(found.person).toEqual({ phone: '+14425550170' });
      expect(found.appointments.map((a) => a.id)).toEqual([ids.tuesday, ids.thursday, ids.nextWeek]);
    }
    const found = await findPersonData(h.deps, { phone: '(442) 555-0170' });
    expect(found.exportedAt).toBe('2026-11-06T17:00:00Z');
    const first = found.appointments[0]!;
    expect(first).toMatchObject({
      customer: { name: 'Andre Sample', phone: '+14425550170', email: 'Andre@Example.com' },
      note: 'Low fade, please.',
      card: { brand: 'visa', last4: '4242' },
      bookedBy: 'customer',
      noShowConsentAt: '2026-11-02T17:00:00Z',
    });
    expect(first.noShowPolicy).toBe(
      "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $35 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free.",
    );
    expect(found.sales.map((s) => [s.id, s.appointmentId, s.customerName])).toEqual([[ids.saleId, ids.tuesday, 'Andre Sample']]);
    expect(found.payments.map((p) => [p.kind, p.appointmentId, p.amountCents])).toEqual([['noShowFee', ids.thursday, 3500]]);
    expect(found.savedCards).toEqual([
      { id: expect.any(String), brand: 'visa', last4: '4242', expMonth: 12, expYear: 2030, savedAt: '2026-11-02T17:00:00Z', removedAt: null, deleteRequestedAt: null },
    ]);
    expect(JSON.stringify(found)).not.toContain('Ben Other');
    // By email too, whatever the case.
    expect((await findPersonData(h.deps, { email: ' andre@example.COM ' })).appointments).toHaveLength(3);
    // Someone the shop doesn't know: nothing.
    expect(await findPersonData(h.deps, { phone: '(442) 555-0111' })).toMatchObject({ appointments: [], sales: [], payments: [], savedCards: [] });
  });

  it('needs one way to find the person, written so it can be checked', async () => {
    await expect(findPersonData(h.deps, {})).rejects.toThrow('Give the --phone or the --email the client booked with.');
    await expect(findPersonData(h.deps, { phone: '555-01' })).rejects.toThrow('Enter a US mobile number, like (442) 341-3053.');
    await expect(findPersonData(h.deps, { email: 'nope' })).rejects.toThrow('Enter a valid email address.');
    await expect(findPersonData(h.deps, { phone: '4425550170', email: 'a@b.com' })).rejects.toThrow(PrivacyError);
  });
});

describe('privacy:correct', () => {
  it('fixes the name, number or email on an appointment, and the name on its checkout', async () => {
    const ids = await history();
    const res = await correctAppointment(h.deps, ids.tuesday, { name: 'Andre Sampel', phone: '(760) 555-0142', email: '' });
    expect(res.appointment.customer).toEqual({ name: 'Andre Sampel', phone: '+17605550142', email: null });
    expect(res).toMatchObject({ salesCorrected: 1, cardTicketsCorrected: 0 });
    const sale = await h.database.pool.query('SELECT customer_name FROM sales WHERE id = $1', [ids.saleId]);
    expect(sale.rows).toEqual([{ customer_name: 'Andre Sampel' }]);
    // Only what's given changes.
    expect((await correctAppointment(h.deps, ids.thursday, { email: 'andre@example.org' })).appointment.customer).toEqual({
      name: 'Andre Sample',
      phone: '+14425550170',
      email: 'andre@example.org',
    });
  });

  it('fixes the name a card checkout copied from the appointment, and leaves a name typed differently', async () => {
    const ids = await history();
    const pay = async (sale: Record<string, unknown>) => {
      const res = await h.call('POST', '/api/owner/payments', {
        ...owner,
        body: { amountCents: 3500, sale: { appointmentId: ids.nextWeek, items: [{ kind: 'service', serviceId: 'haircut', unitCents: 3500 }], ...sale } },
      });
      expect(res.status, res.text).toBe(201);
      return res.body.paymentIntentId as string;
    };
    const copied = await pay({});
    const typed = await pay({ customerName: 'Leo Sample' });
    const res = await correctAppointment(h.deps, ids.nextWeek, { name: 'Andre Sampel' });
    expect(res).toMatchObject({ salesCorrected: 0, cardTicketsCorrected: 1 });
    const names = await h.database.pool.query(`SELECT id, sale_draft->>'customerName' AS name FROM payments WHERE id = ANY($1) ORDER BY id`, [[copied, typed]]);
    expect(Object.fromEntries(names.rows.map((r) => [r.id, r.name]))).toEqual({ [copied]: 'Andre Sampel', [typed]: 'Leo Sample' });
  });

  it('checks what it’s given, and leaves an appointment whose details were removed alone', async () => {
    const ids = await history();
    await expect(correctAppointment(h.deps, 'nope', { name: 'X' })).rejects.toThrow("That isn't an appointment id");
    await expect(correctAppointment(h.deps, ids.tuesday, {})).rejects.toThrow('Give what to correct: --name, --phone or --email.');
    await expect(correctAppointment(h.deps, ids.tuesday, { name: '  ' })).rejects.toThrow('Enter your name.');
    await expect(correctAppointment(h.deps, ids.tuesday, { phone: '123' })).rejects.toThrow('Enter a US mobile number');
    await expect(correctAppointment(h.deps, ids.tuesday, { email: 'nope' })).rejects.toThrow('Enter a valid email address');
    await expect(correctAppointment(h.deps, '00000000-0000-4000-8000-0000000000ff', { name: 'X' })).rejects.toThrow("We couldn't find that appointment.");
    await forgetPerson(h.deps, { phone: '4425550170' });
    await expect(correctAppointment(h.deps, ids.tuesday, { name: 'X' })).rejects.toThrow('already removed');
  });
});

describe('privacy:forget', () => {
  it('removes the person’s details now, except from appointments still needed, and deletes their card once nothing needs it', async () => {
    const ids = await history();
    // Next Monday's appointment is still to come: kept, and so is the card it holds.
    const dry = await forgetPerson(h.deps, { phone: '(442) 555-0170' }, { dryRun: true });
    expect(dry).toEqual({
      person: { phone: '+14425550170' },
      dryRun: true,
      appointments: { removed: 2, kept: [{ id: ids.nextWeek, start: '2026-11-09T18:00:00Z', reason: 'upcoming' }] },
      sales: 1,
      payments: 1,
      savedCards: { deleted: 0, scheduled: 0, found: 1 },
      runAgainAfter: '2026-11-16T18:00:00Z',
    });
    expect((await h.database.pool.query(`SELECT count(*)::int AS n FROM appointments WHERE anonymized_at IS NOT NULL`)).rows[0].n).toBe(0);

    const done = await forgetPerson(h.deps, { phone: '(442) 555-0170' });
    expect(done).toEqual({ ...dry, dryRun: false, savedCards: { deleted: 0, scheduled: 1, found: 1 } });
    const row = async (id: string) => (await h.database.pool.query('SELECT * FROM appointments WHERE id = $1', [id])).rows[0];
    for (const id of [ids.tuesday, ids.thursday]) {
      expect(await row(id)).toMatchObject({ customer_name: NAME_REMOVED, customer_phone: null, customer_email: null, note: null, manage_token_hash: null });
    }
    expect(await row(ids.nextWeek)).toMatchObject({ customer_name: 'Andre Sample', customer_phone: '+14425550170' });
    expect(await row(ids.ben)).toMatchObject({ customer_name: 'Ben Other' });
    expect((await h.database.pool.query('SELECT customer_name, anonymized_at FROM sales')).rows[0]).toMatchObject({ customer_name: null });
    expect((await h.database.pool.query(`SELECT anonymized_at FROM payments WHERE kind = 'no_show_fee'`)).rows[0].anonymized_at).not.toBeNull();
    // The card is marked: it can't book again, and the daily job deletes it once next Monday's no longer needs it.
    const card = (
      await h.database.pool.query(
        'SELECT c.removed_at, c.delete_requested_at FROM saved_cards c JOIN appointments a ON a.saved_card_id = c.id WHERE a.id = $1',
        [ids.nextWeek],
      )
    ).rows[0];
    expect(card).toMatchObject({ removed_at: null, delete_requested_at: new Date('2026-11-06T17:00:00Z') });

    // After next Monday's visit, running it again finishes the job.
    h.setNow('2026-11-09T18:30:00Z');
    await h.call('PATCH', `/api/owner/appointments/${ids.nextWeek}`, { ...owner, body: { status: 'completed' } });
    h.setNow('2026-11-09T19:00:00Z');
    const again = await forgetPerson(h.deps, { phone: '(442) 555-0170' });
    expect(again).toMatchObject({ appointments: { removed: 1, kept: [] }, savedCards: { deleted: 1, scheduled: 0, found: 1 }, runAgainAfter: null });
    expect(h.stripe.calls.filter((c) => c.method === 'customers.del')).toHaveLength(1);
    expect(await findPersonData(h.deps, { phone: '(442) 555-0170' })).toMatchObject({ appointments: [], sales: [], payments: [], savedCards: [] });
  });
});

describe('the command line', () => {
  const run = (...argv: string[]) => privacyCommand(argv, h.deps);

  it('find, correct and forget, with friendly errors and the usage', async () => {
    const ids = await history();
    const found = await run('find', '--phone', '(442) 555-0170');
    expect(found.exitCode).toBe(0);
    expect(JSON.parse(found.output).appointments).toHaveLength(3);
    const saved = await run('find', '--email', 'andre@example.com', '--out', 'request.json');
    expect(saved).toMatchObject({ exitCode: 0, output: 'Saved to request.json.', file: { path: 'request.json' } });
    expect(JSON.parse(saved.file!.text).person).toEqual({ email: 'andre@example.com' });
    const corrected = await run('correct', '--appointment', ids.tuesday, '--name', 'Andre Sampel');
    expect(JSON.parse(corrected.output).appointment.customer.name).toBe('Andre Sampel');
    expect(JSON.parse((await run('forget', '--phone', '4425550170', '--dry-run')).output).dryRun).toBe(true);
    expect(JSON.parse((await run('forget', '--phone', '4425550170')).output).appointments.removed).toBe(2);

    expect(await run('find')).toEqual({ output: 'Give the --phone or the --email the client booked with.', exitCode: 1 });
    expect(await run('correct', '--name', 'X')).toEqual({ output: 'Give the --appointment id (privacy:find shows it).', exitCode: 1 });
    expect(await run('help')).toMatchObject({ exitCode: 2 });
    expect(await run('--help')).toEqual({ output: PRIVACY_USAGE, exitCode: 0 });
    expect(await run()).toEqual({ output: PRIVACY_USAGE, exitCode: 2 });
    expect((await run('find', '--phonee', '1')).exitCode).toBe(2);
  });
});
