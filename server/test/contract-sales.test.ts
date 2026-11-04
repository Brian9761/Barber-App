import { describe, expect, it } from 'vitest';
import { ERROR_STATUS } from '../src/http.js';
import { checkFixture, ErrorBody, recordFixture } from './helpers/contract.js';
import { useHarness, type CallResult } from './helpers/harness.js';
import { seedWeek, WEBHOOK_SECRET } from './helpers/week.js';

// The contract fixtures for sales and analytics, written by the real handlers after checking
// them against the strict schemas in helpers/contract.ts (like test/contract.test.ts does for
// the rest). The Swift Kit decodes the same files. Run with UPDATE_CONTRACT_FIXTURES=1 to
// rewrite them; otherwise this fails if a handler's output drifts from the committed files.

// Monday Nov 2 2026, 10:20 AM PST.
const h = useHarness({ now: '2026-11-02T18:20:00Z' });
const owner = { owner: true } as const;
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const CARLOS45 = 'carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41';

describe('contract fixtures: sales and analytics', () => {
  it('sales, card checkouts and the appointment’s checkout', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    h.config.stripeWebhookSecret = WEBHOOK_SECRET;
    const pomade = (await h.call('POST', '/api/owner/products', { ...owner, body: { name: 'Matte pomade', priceCents: 1800 } })).body.product.id;
    const book = async (offeringId: string, start: string, name: string) =>
      (await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId, start, customer: { name } } })).body.appointment.id as string;
    const andre = await book(FLOW45, '2026-11-02T18:20:00Z', 'Andre');
    const chris = await book(CARLOS45, '2026-11-02T19:00:00Z', 'Chris');

    // 11:05 AM: Andre pays cash for his haircut, a pomade and a gift card.
    h.setNow('2026-11-02T19:05:00Z');
    const created = checkFixture(
      'sale-created',
      await h.call('POST', '/api/owner/sales', {
        ...owner,
        body: {
          appointmentId: andre,
          method: 'cash',
          items: [
            { kind: 'service', serviceId: 'haircut' },
            { kind: 'product', productId: pomade, quantity: 2 },
            { kind: 'custom', name: 'Gift card', unitCents: 2500 },
          ],
        },
      }),
      201,
    ).sale;
    checkFixture('owner-appointments-with-sale', await h.call('GET', '/api/owner/appointments?date=2026-11-02', owner));

    // 11:50 AM: Chris taps his card for a haircut and a pomade.
    h.setNow('2026-11-02T19:50:00Z');
    const payment = checkFixture(
      'payment-created-with-sale',
      await h.call('POST', '/api/owner/payments', {
        ...owner,
        body: {
          amountCents: 6300,
          sale: { appointmentId: chris, items: [{ kind: 'service', serviceId: 'haircut' }, { kind: 'product', productId: pomade }] },
        },
      }),
      201,
    );
    h.stripe.succeed(payment.paymentIntentId);
    h.advance(1);
    checkFixture('payment-completed-with-sale', await h.call('POST', `/api/owner/payments/${payment.paymentIntentId}/complete`, owner));

    // A walk-in pays by Zelle; a mistake is rung up and voided.
    h.setNow('2026-11-02T21:30:00Z');
    await h.call('POST', '/api/owner/sales', {
      ...owner,
      body: { barberId: 'israel-flores', customerName: 'Walk-in', method: 'other', items: [{ kind: 'service', serviceId: 'military-haircut' }] },
    });
    h.setNow('2026-11-02T22:00:00Z');
    const mistake = (
      await h.call('POST', '/api/owner/sales', { ...owner, body: { barberId: 'julian-ramos', method: 'cash', items: [{ kind: 'service', serviceId: 'haircut' }] } })
    ).body.sale;
    h.advance(2);
    checkFixture('sale-voided', await h.call('POST', `/api/owner/sales/${mistake.id}/void`, { ...owner, body: { reason: 'Rang up twice' } }));
    const day = checkFixture('sales-day', await h.call('GET', '/api/owner/sales?date=2026-11-02', owner));
    expect(day.sales.map((s) => s.method)).toEqual(['cash', 'other', 'card', 'cash']);
    expect(day.sales[3]?.id).toBe(created.id);
  });

  it('analytics for a week, for the shop and for one barber', async () => {
    await seedWeek(h);
    checkFixture('analytics', await h.call('GET', '/api/owner/analytics?from=2026-11-01&to=2026-11-07', owner));
    checkFixture('analytics-barber', await h.call('GET', '/api/owner/analytics?from=2026-11-01&to=2026-11-07&barberId=flowxbori', owner));
  });

  it('one example of each new error code', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const appointment = (
      await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start: '2026-11-02T19:00:00Z', customer: { name: 'Ben' } } })
    ).body.appointment.id;
    const haircut = [{ kind: 'service', serviceId: 'haircut' }];
    const examples: Record<string, CallResult> = {};
    await h.call('POST', '/api/owner/sales', { ...owner, body: { appointmentId: appointment, method: 'cash', items: haircut } });
    examples.already_checked_out = await h.call('POST', '/api/owner/sales', { ...owner, body: { appointmentId: appointment, method: 'cash', items: haircut } });
    const cancelled = (
      await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start: '2026-11-02T20:00:00Z', customer: { name: 'Cy' } } })
    ).body.appointment.id;
    await h.call('PATCH', `/api/owner/appointments/${cancelled}`, { ...owner, body: { status: 'cancelled' } });
    examples.not_checkoutable = await h.call('POST', '/api/owner/sales', { ...owner, body: { appointmentId: cancelled, method: 'cash', items: haircut } });
    examples.amount_mismatch = await h.call('POST', '/api/owner/payments', {
      ...owner,
      body: { amountCents: 4000, sale: { barberId: 'julian-ramos', items: haircut } },
    });
    for (const [code, result] of Object.entries(examples)) {
      expect(result.status, code).toBe(ERROR_STATUS[code as keyof typeof ERROR_STATUS]);
      expect(ErrorBody.parse(result.body).error.code).toBe(code);
      recordFixture(`errors/${code}.json`, result.body);
    }
    expect(Object.keys(examples).sort()).toEqual(['already_checked_out', 'amount_mismatch', 'not_checkoutable']);
  });
});
