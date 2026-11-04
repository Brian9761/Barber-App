import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { resolveTarget } from '../src/booking.js';
import { loadCatalog } from '../src/catalog.js';
import { windowLabel } from '../src/feecase.js';
import {
  DEFAULT_NO_SHOW_SETTINGS,
  feeRangeLabel,
  feeWarning,
  money,
  noShowFeeCents,
  policyText,
  protectionFor,
  type NoShowSettings,
} from '../src/noshow.js';
import { protectionOn, useHarness } from './helpers/harness.js';

// The fee rule, the policy wording, the public policy endpoint and the owner's
// settings. The rule's cases are also written to test/fixtures/no-show-rule.json,
// which the Kit's tests read to check its mirror of the rule (the owner app's preview).

const percent = (p: number): NoShowSettings => ({ ...DEFAULT_NO_SHOW_SETTINGS, enabled: true, feeMode: 'percent', percent: p });
const flat = (cents: number): NoShowSettings => ({ ...DEFAULT_NO_SHOW_SETTINGS, enabled: true, feeMode: 'flat', flatCents: cents });
const fixed = (priceCents: number) => ({ priceCents, priceKind: 'fixed' as const });
/** Late cancellations off: only a no-show can be charged. */
const noLate = (settings: NoShowSettings): NoShowSettings => ({ ...settings, lateCancelEnabled: false });
const window = (minutes: number, settings: NoShowSettings = percent(100)): NoShowSettings => ({ ...settings, lateCancelWindowMinutes: minutes });

describe('the fee rule', () => {
  it('percent mode: the share of the price, rounded half up to the cent', () => {
    expect(noShowFeeCents(fixed(4000), percent(50))).toBe(2000);
    expect(noShowFeeCents(fixed(3500), percent(50))).toBe(1750);
    expect(noShowFeeCents(fixed(1999), percent(50))).toBe(1000); // 999.5 → 1000
    expect(noShowFeeCents(fixed(333), percent(50))).toBe(167); // 166.5 → 167
    expect(noShowFeeCents(fixed(3333), percent(10))).toBe(333); // 333.3 → 333
    expect(noShowFeeCents(fixed(3335), percent(10))).toBe(334); // 333.5 → 334
    expect(noShowFeeCents(fixed(15000), percent(100))).toBe(15000);
    expect(noShowFeeCents(fixed(15000), percent(1))).toBe(150);
  });

  it('flat mode: the flat amount, whatever the price', () => {
    expect(noShowFeeCents(fixed(4000), flat(2000))).toBe(2000);
    expect(noShowFeeCents(fixed(1600), flat(2500))).toBe(2500);
    expect(noShowFeeCents(fixed(100), flat(50))).toBe(50);
  });

  it('"starting at" prices use the starting price', () => {
    expect(noShowFeeCents({ priceCents: 8000, priceKind: 'startingAt' }, percent(50))).toBe(4000);
  });

  it('no fee for items included with a cut, free items, or a fee under 50¢', () => {
    expect(noShowFeeCents({ priceCents: 0, priceKind: 'includedWithCut' }, percent(50))).toBeNull();
    expect(noShowFeeCents({ priceCents: 0, priceKind: 'includedWithCut' }, flat(2000))).toBeNull();
    expect(noShowFeeCents({ priceCents: 1500, priceKind: 'includedWithCut' }, flat(2000))).toBeNull();
    expect(noShowFeeCents(fixed(0), flat(2000))).toBeNull();
    expect(noShowFeeCents(fixed(99), percent(50))).toBe(50); // 49.5 → 50: just enough
    expect(noShowFeeCents(fixed(98), percent(50))).toBeNull(); // 49
    expect(noShowFeeCents(fixed(400), percent(10))).toBeNull(); // 40¢
  });
});

describe('the policy clients see', () => {
  it('formats money like the apps', () => {
    expect([money(2000), money(1750), money(2705), money(5), money(50), money(50_000)]).toEqual([
      '$20',
      '$17.50',
      '$27.05',
      '$0.05',
      '$0.50',
      '$500',
    ]);
    expect(feeRangeLabel(2000, 2000)).toBe('$20');
    expect(feeRangeLabel(1750, 2250)).toBe('$17.50–$22.50');
  });

  it('the agreed policy: a late cancellation or a no-show may be charged; cancelling earlier is free', () => {
    expect(policyText(4000, 4000, percent(100))).toBe(
      "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $40 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free.",
    );
    expect(policyText(1750, 2250, window(120, percent(50)))).toBe(
      "No payment now. If you cancel less than 2 hours before your appointment, or don't come, Izzy Clipz may charge $17.50–$22.50 (50% of the service) to this card. Cancelling in the app more than 2 hours before is free.",
    );
    expect(policyText(2500, 2500, window(30, flat(2500)))).toBe(
      "No payment now. If you cancel less than 30 minutes before your appointment, or don't come, Izzy Clipz may charge $25 to this card. Cancelling in the app more than 30 minutes before is free.",
    );
    // Short enough for Stripe's custom text (1,200 characters).
    expect(policyText(1, 50_000, window(2880, percent(100))).length).toBeLessThan(300);
  });

  it('with late cancellations off: only a no-show may be charged, and cancelling before the start is free', () => {
    expect(policyText(2000, 2000, noLate(percent(50)))).toBe(
      "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $20 (50% of the service) to this card. Cancelling in the app before your appointment is free.",
    );
    expect(policyText(1750, 2250, noLate(percent(50)))).toBe(
      "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $17.50–$22.50 (50% of the service) to this card. Cancelling in the app before your appointment is free.",
    );
    expect(policyText(2500, 2500, noLate(flat(2500)))).toBe(
      "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $25 to this card. Cancelling in the app before your appointment is free.",
    );
  });

  it('says the window in plain words', () => {
    expect([30, 45, 60, 90, 120, 180, 1440, 2880].map(windowLabel)).toEqual([
      '30 minutes',
      '45 minutes',
      '1 hour',
      '90 minutes',
      '2 hours',
      '3 hours',
      '24 hours',
      '48 hours',
    ]);
  });

  it('the warning clients see while booking: "Full Service Cancellation & No-Show Fee"', () => {
    expect(feeWarning(4000, 4000, percent(100))).toEqual({
      title: 'Full Service Cancellation & No-Show Fee',
      message:
        'Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($40). Cancelling in the app more than 1 hour before is free.',
    });
    // Any barber: the range of their prices.
    expect(feeWarning(5500, 6000, percent(100)).message).toBe(
      'Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($55–$60). Cancelling in the app more than 1 hour before is free.',
    );
    // Less than the full price: the title doesn't say "Full Service".
    expect(feeWarning(2000, 2000, window(180, percent(50)))).toEqual({
      title: 'Late Cancellation & No-Show Fee',
      message:
        'Cancelling less than 3 hours before your appointment, or not showing up, is charged $20 (50% of the service). Cancelling in the app more than 3 hours before is free.',
    });
    expect(feeWarning(2500, 2500, flat(2500))).toEqual({
      title: 'Late Cancellation & No-Show Fee',
      message:
        'Cancelling less than 1 hour before your appointment, or not showing up, is charged $25. Cancelling in the app more than 1 hour before is free.',
    });
    // Late cancellations off: only the no-show part.
    expect(feeWarning(4000, 4000, noLate(percent(100)))).toEqual({
      title: 'No-Show Fee',
      message: 'Not showing up is charged the full service price ($40). Cancelling in the app before your appointment is free.',
    });
    expect(feeWarning(2000, 2000, noLate(flat(2000)))).toEqual({
      title: 'No-Show Fee',
      message: 'Not showing up is charged $20. Cancelling in the app before your appointment is free.',
    });
  });

  it('any barber: the range of the barbers’ fees; one barber: their fee', () => {
    const catalog = loadCatalog();
    const any = resolveTarget(catalog, { serviceId: 'haircut-and-beard', barberId: 'any' });
    const { policy, fees } = protectionFor(any, percent(50), true);
    expect(policy).toMatchObject({ required: true, minFeeCents: 2750, maxFeeCents: 3000, lateCancelWindowMinutes: 60 });
    expect(policy.policyText).toContain('$27.50–$30 (50% of the service)');
    expect(policy.warning).toEqual(feeWarning(2750, 3000, percent(50)));
    const carlos = catalog.data.offerings.find((o) => o.barberId === 'carlos-rafael' && o.serviceId === 'haircut-and-beard')!;
    expect(fees.get(carlos.id)).toBe(3000);
    expect([...fees.values()].sort()).toEqual([2750, 2750, 2750, 2750, 3000]);
    const sameFee = protectionFor(resolveTarget(catalog, { serviceId: 'haircut', barberId: 'any' }), percent(50), true).policy;
    expect(sameFee).toMatchObject({ required: true, minFeeCents: 1750, maxFeeCents: 1750 });
    expect(sameFee.policyText).toContain('may charge $17.50 (50% of the service)');
    const flatAny = protectionFor(any, flat(2000), true).policy;
    expect(flatAny).toMatchObject({ minFeeCents: 2000, maxFeeCents: 2000 });
    // Late cancellations off: no window, and the policy and warning are only about no-shows.
    const noShowOnly = protectionFor(any, noLate(percent(100)), true).policy;
    expect(noShowOnly).toMatchObject({ required: true, minFeeCents: 5500, maxFeeCents: 6000, lateCancelWindowMinutes: null });
    expect(noShowOnly.policyText).toBe(policyText(5500, 6000, noLate(percent(100))));
    expect(noShowOnly.warning?.title).toBe('No-Show Fee');
  });

  it('not required without Stripe, with protection off, or when the item has no fee', () => {
    const catalog = loadCatalog();
    const target = resolveTarget(catalog, { offeringId: 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a' });
    const off = { required: false, minFeeCents: null, maxFeeCents: null, policyText: null, lateCancelWindowMinutes: null, warning: null };
    expect(protectionFor(target, percent(50), false).policy).toEqual(off);
    expect(protectionFor(target, { ...percent(50), enabled: false }, true).policy).toEqual(off);
    const lineup = resolveTarget(catalog, { offeringId: 'carlos-rafael/0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb' });
    expect(protectionFor(lineup, percent(50), true).policy).toEqual(off);
    expect(protectionFor(target, percent(50), true).policy.required).toBe(true);
  });
});

describe('test/fixtures/no-show-rule.json (read by the Kit)', () => {
  it('lists the rule for every menu item and every policy, and is up to date', () => {
    const catalog = loadCatalog();
    const settings: NoShowSettings[] = [
      percent(50),
      percent(10),
      percent(100),
      percent(33),
      flat(2000),
      flat(50),
      flat(50_000),
      noLate(percent(100)),
      noLate(percent(50)),
      noLate(flat(2500)),
      window(30),
      window(45, percent(50)),
      window(90, flat(2000)),
      window(120),
      window(1440),
      window(2880, percent(25)),
    ];
    const extraPrices = [
      fixed(1999),
      fixed(333),
      fixed(99),
      fixed(98),
      fixed(0),
      { priceCents: 8000, priceKind: 'startingAt' as const },
      { priceCents: 0, priceKind: 'includedWithCut' as const },
    ];
    const items = [...catalog.data.offerings.map((o) => ({ priceCents: o.priceCents, priceKind: o.priceKind })), ...extraPrices];
    const unique = [...new Map(items.map((i) => [`${i.priceKind}:${i.priceCents}`, i])).values()];
    // The late-cancellation settings don't change the fee, so fees use only the fee settings.
    const feeSettings = settings.slice(0, 7);
    const fees = feeSettings.flatMap((s) => unique.map((item) => ({ settings: s, ...item, feeCents: noShowFeeCents(item, s) })));
    const policies = settings.flatMap((s) =>
      [
        [2000, 2000],
        [1750, 2250],
        [50, 50_000],
        [2705, 3000],
      ].map(([min, max]) => ({
        settings: s,
        minFeeCents: min,
        maxFeeCents: max,
        policyText: policyText(min!, max!, s),
        warning: feeWarning(min!, max!, s),
      })),
    );
    const windows = [30, 45, 59, 60, 61, 90, 120, 150, 180, 360, 720, 1440, 2880].map((minutes) => ({ minutes, label: windowLabel(minutes) }));
    const document = { fees, policies, windows };
    const file = new URL('./fixtures/no-show-rule.json', import.meta.url);
    const text = `${JSON.stringify(document, null, 2)}\n`;
    if (process.env.UPDATE_CONTRACT_FIXTURES === '1' || !existsSync(file)) writeFileSync(file, text);
    expect(JSON.parse(readFileSync(file, 'utf8')), 'no-show-rule.json is out of date: run UPDATE_CONTRACT_FIXTURES=1 npm test').toEqual(document);
  });
});

const h = useHarness({ now: '2026-11-02T17:00:00Z' });
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';

describe('GET /api/no-show-policy', () => {
  it('without Stripe: no card needed', async () => {
    const res = await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ required: false, minFeeCents: null, maxFeeCents: null, policyText: null, lateCancelWindowMinutes: null, warning: null });
    expect(res.headers.get('cache-control')).toBe('no-store');
  });

  it('a Stripe key alone doesn’t turn protection on: the owner does', async () => {
    for (const key of ['sk_test_fixture', 'sk_live_fixture']) {
      h.config.stripeSecretKey = key;
      expect((await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.required, key).toBe(false);
    }
  });

  it('with Stripe: the fee for one barber, or the range for any barber, following the owner’s settings', async () => {
    await protectionOn(h);
    const one = await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`);
    // The starting settings: the full price ($35) for a no-show or a cancellation less than 1 hour before.
    expect(one.body).toEqual({
      required: true,
      minFeeCents: 3500,
      maxFeeCents: 3500,
      policyText:
        "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $35 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free.",
      lateCancelWindowMinutes: 60,
      warning: {
        title: 'Full Service Cancellation & No-Show Fee',
        message:
          'Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($35). Cancelling in the app more than 1 hour before is free.',
      },
    });
    const any = await h.call('GET', '/api/no-show-policy?serviceId=haircut-and-beard&barberId=any');
    expect(any.body).toMatchObject({ required: true, minFeeCents: 5500, maxFeeCents: 6000, lateCancelWindowMinutes: 60 });
    expect(any.body.warning.message).toContain('the full service price ($55–$60)');

    // The owner changes the window, then turns late cancellations off.
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { lateCancelWindowMinutes: 180 } });
    const longer = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body;
    expect(longer.lateCancelWindowMinutes).toBe(180);
    expect(longer.policyText).toContain('If you cancel less than 3 hours before your appointment');
    expect(longer.warning.message).toContain('Cancelling less than 3 hours before your appointment');
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { lateCancelEnabled: false } });
    const noLateFee = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body;
    expect(noLateFee).toEqual({
      required: true,
      minFeeCents: 3500,
      maxFeeCents: 3500,
      policyText:
        "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $35 (100% of the service) to this card. Cancelling in the app before your appointment is free.",
      lateCancelWindowMinutes: null,
      warning: {
        title: 'No-Show Fee',
        message: 'Not showing up is charged the full service price ($35). Cancelling in the app before your appointment is free.',
      },
    });

    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { feeMode: 'flat', flatCents: 2000 } });
    expect((await h.call('GET', '/api/no-show-policy?serviceId=haircut-and-beard&barberId=any')).body).toMatchObject({
      minFeeCents: 2000,
      maxFeeCents: 2000,
    });
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { enabled: false } });
    expect((await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.required).toBe(false);
  });

  it('turns down a target that isn’t on the menu, like availability', async () => {
    await protectionOn(h);
    expect((await h.call('GET', '/api/no-show-policy')).status).toBe(400);
    expect((await h.call('GET', '/api/no-show-policy?offeringId=nope')).status).toBe(400);
    expect((await h.call('GET', '/api/no-show-policy?serviceId=haircut')).status).toBe(400);
    expect((await h.call('GET', '/api/no-show-policy?serviceId=perm&barberId=any')).status).toBe(400);
  });
});

describe('GET/PATCH /api/owner/no-show-settings', () => {
  const get = () => h.call('GET', '/api/owner/no-show-settings', { owner: true });
  const patch = (body: unknown) => h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body });

  const DEFAULTS = { enabled: false, feeMode: 'percent', percent: 100, flatCents: 2000, lateCancelEnabled: true, lateCancelWindowMinutes: 60 };

  it('starts off (the owner turns it on), at the full service price, late cancellations 1 hour, a $20 flat amount ready', async () => {
    const res = await get();
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ noShowSettings: DEFAULTS });
    // Setting a Stripe key changes nothing here either.
    h.config.stripeSecretKey = 'sk_live_fixture';
    expect((await get()).body.noShowSettings.enabled).toBe(false);
  });

  it('changes only what is sent, and keeps it', async () => {
    expect((await patch({ enabled: true })).body.noShowSettings).toEqual({ ...DEFAULTS, enabled: true });
    expect((await patch({ percent: 40 })).body.noShowSettings).toEqual({ ...DEFAULTS, enabled: true, percent: 40 });
    expect((await patch({ feeMode: 'flat', flatCents: 2500 })).body.noShowSettings).toEqual({
      ...DEFAULTS,
      enabled: true,
      feeMode: 'flat',
      percent: 40,
      flatCents: 2500,
    });
    expect((await patch({ lateCancelWindowMinutes: 120 })).body.noShowSettings.lateCancelWindowMinutes).toBe(120);
    // Late cancellations off keeps the window for when they're back on.
    expect((await patch({ lateCancelEnabled: false })).body.noShowSettings).toMatchObject({ lateCancelEnabled: false, lateCancelWindowMinutes: 120 });
    expect((await patch({ enabled: false })).body.noShowSettings.enabled).toBe(false);
    const after = { enabled: false, feeMode: 'flat', percent: 40, flatCents: 2500, lateCancelEnabled: false, lateCancelWindowMinutes: 120 };
    expect((await patch({})).body.noShowSettings).toEqual(after);
    expect((await get()).body.noShowSettings).toEqual(after);
  });

  it('two changes at once both stick', async () => {
    await Promise.all([patch({ percent: 30 }), patch({ flatCents: 1500 })]);
    expect((await get()).body.noShowSettings).toMatchObject({ percent: 30, flatCents: 1500 });
  });

  it('validates every field, in plain words, and changes nothing on a bad request', async () => {
    const bad: [unknown, string][] = [
      [{ percent: 0 }, 'Pick a percentage from 1% to 100%.'],
      [{ percent: 101 }, 'Pick a percentage from 1% to 100%.'],
      [{ percent: 50.5 }, 'Pick a whole percentage from 1% to 100%.'],
      [{ percent: '50' }, 'Pick a percentage from 1% to 100%.'],
      [{ flatCents: 49 }, 'Pick a flat fee from $0.50 to $500.'],
      [{ flatCents: 50_001 }, 'Pick a flat fee from $0.50 to $500.'],
      [{ flatCents: 20.5 }, 'The flat fee must be a whole number of cents.'],
      [{ feeMode: 'half' }, 'feeMode must be percent or flat.'],
      [{ enabled: 'yes' }, 'enabled must be true or false.'],
      [{ percentage: 40 }, 'Unexpected field: percentage.'],
      [{ percent: 40, enabled: null }, 'enabled must be true or false.'],
      [{ lateCancelEnabled: 1 }, 'lateCancelEnabled must be true or false.'],
      [{ lateCancelWindowMinutes: 29 }, 'Pick a late-cancellation window from 30 minutes to 48 hours.'],
      [{ lateCancelWindowMinutes: 2881 }, 'Pick a late-cancellation window from 30 minutes to 48 hours.'],
      [{ lateCancelWindowMinutes: '60' }, 'Pick a late-cancellation window from 30 minutes to 48 hours.'],
      [{ lateCancelWindowMinutes: 60.5 }, 'The late-cancellation window must be a whole number of minutes.'],
      [{ lateCancelWindowMinutes: null }, 'Pick a late-cancellation window from 30 minutes to 48 hours.'],
      [{ lateCancelHours: 1 }, 'Unexpected field: lateCancelHours.'],
    ];
    for (const [body, message] of bad) {
      const res = await patch(body);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body.error).toEqual({ code: 'invalid_request', message });
    }
    expect((await patch({ percent: 1 })).status).toBe(200);
    expect((await patch({ percent: 100, flatCents: 50 })).status).toBe(200);
    expect((await patch({ flatCents: 50_000 })).status).toBe(200);
    expect((await patch({ lateCancelWindowMinutes: 30 })).status).toBe(200);
    expect((await patch({ lateCancelWindowMinutes: 2880, lateCancelEnabled: true })).status).toBe(200);
    expect((await get()).body.noShowSettings).toEqual({ ...DEFAULTS, percent: 100, flatCents: 50_000, lateCancelWindowMinutes: 2880 });
  });

  it('falls back to the defaults for anything stored that isn’t valid', async () => {
    await h.database.pool.query(
      `INSERT INTO settings (key, value, updated_at)
       VALUES ('no_show', '{"percent": 0, "feeMode": "flat", "flatCents": "x", "lateCancelEnabled": false, "lateCancelWindowMinutes": 5}', now())`,
    );
    expect((await get()).body.noShowSettings).toEqual({ ...DEFAULTS, feeMode: 'flat', lateCancelEnabled: false });
  });
});
