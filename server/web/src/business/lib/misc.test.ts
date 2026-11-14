import { describe, expect, it } from 'vitest';
import analyticsFixture from '../../../../test/fixtures/contract/analytics.json';
import rule from '../../../../test/fixtures/no-show-rule.json';
import noShowSettings from '../../../../test/fixtures/contract/no-show-settings.json';
import stripeActive from '../../../../test/fixtures/contract/stripe-connection-active.json';
import stripeOff from '../../../../test/fixtures/contract/stripe-connection-off.json';
import stripeNotConnected from '../../../../test/fixtures/contract/stripe-connection-not-connected.json';
import { catalog } from '../../test/api';
import type { Analytics, NoShowSettings, StripeConnection } from '../types';
import { computerName } from './computerName';
import { metricLabel, rankBy } from './leaderboard';
import { compactMoney, editableMoney, moneyWithCommas, parseMoney, percent, priceFromLabel } from './money';
import * as noShow from './noShow';
import { stripeReturnLine, stripeView } from './stripe';
import { blockTimeText } from '../pages/TodayPage';
import { saleLine } from '../pages/today/SalesList';

describe('amounts', () => {
  it('reads what the owner types', () => {
    expect(parseMoney('40')).toBe(4000);
    expect(parseMoney('17.5')).toBe(1750);
    expect(parseMoney('$17.50')).toBe(1750);
    expect(parseMoney(' 1,200 ')).toBe(120000);
    expect(parseMoney('.5')).toBe(50);
    expect(parseMoney('12.345')).toBeNull();
    expect(parseMoney('-5')).toBeNull();
    expect(parseMoney('')).toBeNull();
    expect(parseMoney('abc')).toBeNull();
  });

  it('shows amounts the app’s way', () => {
    expect(editableMoney(4000)).toBe('40');
    expect(editableMoney(1750)).toBe('17.50');
    expect(moneyWithCommas(123456)).toBe('$1,234.56');
    expect(moneyWithCommas(1000000)).toBe('$10,000');
    expect(compactMoney(80000)).toBe('$800');
    expect(compactMoney(150000)).toBe('$1.5K');
    expect(compactMoney(2500000)).toBe('$25K');
    expect(percent(0.2307)).toBe('23%');
  });

  it('reads the price an appointment was booked at from its label', () => {
    expect(priceFromLabel('$35')).toBe(3500);
    expect(priceFromLabel('$7.50')).toBe(750);
    expect(priceFromLabel('From $80')).toBe(8000);
    expect(priceFromLabel('Included with cut')).toBe(0);
    expect(priceFromLabel('Ask')).toBeNull();
  });
});

describe('the leaderboard by metric', () => {
  const data = analyticsFixture as unknown as Analytics;

  it('keeps the server’s order and places for sales', () => {
    expect(rankBy(data.leaderboard, 'sales').map((r) => [r.place, r.entry.name])).toEqual([
      [1, 'Izzy'],
      [2, 'Carlos'],
      [3, 'Flowxbori'],
      [4, 'Julian'],
      [5, 'Cristian'],
    ]);
  });

  it('orders by services, products or clients served, highest first, sharing places on a tie', () => {
    // Services: Izzy 3, Julian 3, Carlos 2, Flowxbori 2, Cristian 2.
    expect(rankBy(data.leaderboard, 'services').map((r) => [r.place, r.entry.name, r.value])).toEqual([
      [1, 'Izzy', 3],
      [1, 'Julian', 3],
      [3, 'Carlos', 2],
      [3, 'Cristian', 2],
      [3, 'Flowxbori', 2],
    ]);
    expect(rankBy(data.leaderboard, 'products')[0]!.entry.name).toBe('Carlos');
    const carlos = data.leaderboard.find((e) => e.name === 'Carlos')!;
    expect(metricLabel(carlos, 'products')).toBe('4 products');
    expect(metricLabel(carlos, 'sales')).toBe('$188');
    expect(metricLabel(carlos, 'clients')).toBe('3 clients');
  });
});

describe('Card payments (Stripe)', () => {
  it('words each status as the app does, with its button', () => {
    expect(stripeView(stripeActive as StripeConnection)).toEqual({ label: 'Connected', tone: 'good', action: null });
    expect(stripeView(stripeNotConnected as StripeConnection)).toMatchObject({ label: 'Not connected', action: 'Connect Stripe' });
    expect(stripeView({ status: 'needsInfo' })).toMatchObject({ label: 'Finish setting up', action: 'Finish setting up' });
    expect(stripeView({ status: 'restricted' })).toMatchObject({ label: 'Paused by Stripe', action: 'Finish setting up' });
    expect(stripeView({ status: 'pending' })).toMatchObject({ label: 'Stripe is checking your details', action: null });
    expect(stripeView({ status: 'direct' }).label).toBe("Uses the server's Stripe key");
    expect(stripeView(stripeOff as StripeConnection)).toMatchObject({ label: 'Not set up on the server', action: null });
    expect(stripeView({ status: 'somethingNew' }).label).toBe('Stripe');
  });

  it('says what happened once Stripe sends the owner back', () => {
    expect(stripeReturnLine('active')).toEqual({ text: "You're connected. You can take card payments now.", good: true });
    expect(stripeReturnLine('needsInfo')).toEqual({ text: 'Stripe still needs a few details: click Finish setting up.', good: false });
    // Each names only a button its status offers.
    expect(stripeReturnLine('notConnected')).toEqual({ text: "Stripe wasn't connected. Click Connect Stripe to try again.", good: false });
    expect(stripeView({ status: 'notConnected' }).action).toBe('Connect Stripe');
    expect(stripeReturnLine('restricted').text).toContain('Finish setting up');
    expect(stripeView({ status: 'restricted' }).action).toBe('Finish setting up');
    for (const status of ['off', 'direct', 'pending', 'somethingNew']) {
      expect(stripeView({ status } as never).action).toBeNull();
      expect(stripeReturnLine(status).text).not.toMatch(/click/i);
    }
  });
});

describe('No-show protection', () => {
  const saved = noShowSettings.noShowSettings as NoShowSettings;

  it('works out the fee, the policy and the notice exactly as the server does', () => {
    // The fixture has a flat fee over the service's price (the cap), and says "may be charged".
    expect(rule.fees.some((f) => f.settings.feeMode === 'flat' && f.settings.flatCents > f.priceCents && f.feeCents === f.priceCents)).toBe(true);
    expect(rule.policies.every((p) => p.warning === null || p.warning.message.includes('may be charged'))).toBe(true);
    for (const fee of rule.fees) {
      expect(noShow.feeCents(fee.priceCents, fee.priceKind === 'includedWithCut', fee.settings as NoShowSettings), JSON.stringify(fee)).toBe(fee.feeCents);
    }
    for (const policy of rule.policies) {
      if (policy.minFeeCents === null || policy.maxFeeCents === null) continue;
      const settings = policy.settings as NoShowSettings;
      expect(noShow.policyText(policy.minFeeCents, policy.maxFeeCents, settings)).toBe(policy.policyText);
      expect(noShow.clientNotice(policy.minFeeCents, policy.maxFeeCents, settings)).toEqual(policy.warning);
    }
  });

  it('sends only what the owner changed, and says what the server would turn down', () => {
    const draft = noShow.draftFrom(saved);
    expect(noShow.hasChanges(draft, saved)).toBe(false);
    const edited = { ...draft, enabled: true, feeMode: 'flat' as const, flatText: '25' };
    expect(noShow.draftChanges(edited, saved)).toEqual({ enabled: true, feeMode: 'flat', flatCents: 2500 });
    expect(noShow.draftProblem({ ...edited, flatText: '600' })).toBe('Pick a flat fee from $0.50 to $500.');
    expect(noShow.draftProblem({ ...edited, flatText: 'twenty' })).toBe('Enter the flat fee in dollars, like 20 or 17.50.');
    // A flat amount that can't be read only matters while the fee is a flat amount.
    expect(noShow.draftProblem({ ...draft, flatText: 'twenty' })).toBeNull();
  });

  it('steps the percentage by 5, from 10% to 100%', () => {
    expect(noShow.increasePercent(100)).toBe(100);
    expect(noShow.decreasePercent(100)).toBe(95);
    expect(noShow.decreasePercent(12)).toBe(10);
    expect(noShow.decreasePercent(10)).toBe(10);
    expect(noShow.increasePercent(12)).toBe(15);
    expect(noShow.percentLabel(100)).toBe('100% of the service (the full price)');
  });

  it('shows an example and sums it up like the app', () => {
    const on = { ...saved, enabled: true };
    expect(noShow.examples(on, catalog)).toEqual(['A $40 haircut: $40', 'A $5 hot lather shave: $5']);
    // A flat fee is never more than the service's price: $25 on a $5 shave is $5, as the server charges it.
    const flat = { ...on, feeMode: 'flat' as const, flatCents: 2500 };
    expect(noShow.examples(flat, catalog)).toEqual(['A $40 haircut: $25', 'A $5 hot lather shave: $5']);
    expect(noShow.feeCents(500, false, flat)).toBe(500);
    expect(noShow.summary(on)).toBe('On: the full service price for no-shows and cancellations less than 1 hour before');
    expect(noShow.summary(saved)).toBe('Off: clients book online without a card');
    expect(noShow.costsText(4000)).toContain('about $1.46 of a $40 fee');
    expect(noShow.windowChoices(90)).toEqual([30, 60, 90, 120, 180, 240, 360, 720, 1440, 2880]);
  });

  it('says when Stripe stands in the way', () => {
    expect(noShow.stripeNote(stripeNotConnected as StripeConnection, true)).toContain("Stripe isn't connected yet");
    expect(noShow.stripeNote(stripeOff as StripeConnection, true)).toContain("Stripe isn't set up on the server yet");
    expect(noShow.stripeNote(stripeActive as StripeConnection, true)).toContain('Stripe is in test mode');
    expect(noShow.stripeNote(stripeActive as StripeConnection, false)).toBeNull();
  });

  it('says plainly in the demo that client bookings never ask for a card, so the notice never shows there', () => {
    // The real site: what new bookings do, and where the notice shows.
    expect(noShow.savedLine(false)).toBe('Saved. New bookings use these settings.');
    expect(noShow.clientViewNote(false)).toBe(
      'For the example haircut. The notice shows while clients pick a day and time and on Review; they agree to the policy before booking.',
    );
    // The demo: its client side never asks for a card (src/demo/api.ts), Stripe connected or not.
    expect(noShow.savedLine(true)).toBe("Saved. In the demo, client bookings never ask for a card, so the fee notice doesn't show there.");
    expect(noShow.clientViewNote(true)).toBe(
      "For the example haircut. On the real site, the notice shows while clients pick a day and time and on Review, and they agree to the policy before booking. In the demo, client bookings never ask for a card, so it doesn't show there.",
    );
    const demoNote = "In the demo, client bookings never ask for a card, with Stripe connected or not, so the fee notice doesn't show there.";
    for (const connection of [stripeNotConnected, stripeOff, stripeActive]) {
      for (const enabled of [true, false]) expect(noShow.stripeNote(connection as StripeConnection, enabled, true)).toBe(demoNote);
    }
    // Nothing until the Stripe status is in.
    expect(noShow.stripeNote(null, true, true)).toBeNull();
  });
});

describe('this computer’s name in the app’s list', () => {
  it('says the browser and the system', () => {
    expect(computerName('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36')).toBe(
      'Chrome on Mac',
    );
    expect(computerName('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0')).toBe(
      'Edge on Windows',
    );
    expect(computerName('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15', 5)).toBe(
      'Safari on iPad',
    );
    expect(
      computerName('Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1'),
    ).toBe('Safari on iPhone');
    expect(computerName('Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0')).toBe('Firefox on Linux');
    expect(computerName('Something else')).toBe('Computer');
  });
});

describe('amounts of $1,000 and more', () => {
  it('have their commas in what a chart’s column says, like the total next to them', async () => {
    const { columnDescription } = await import('../components/charts');
    const october = { date: '2026-10', salesCents: 2054600, servicesCents: 1633000, productsCents: 371600, otherCents: 25000, feesCents: 25000, servicesCount: 400, productsCount: 200 };
    expect(columnDescription(october)).toBe('October 2026: $20,546. Services $16,330, products $3,716, other and fees $500.');
  });
});

describe('time off on Today', () => {
  const zone = 'America/Los_Angeles';
  const block = (start: string, end: string) => ({ id: 'b', barberId: 'carlos-rafael', start, end, reason: 'Vacation' });

  it('says the times for time off within the day shown, as the app does', () => {
    expect(blockTimeText(block('2026-11-04T21:00:00Z', '2026-11-04T22:00:00Z'), '2026-11-04', zone).replace(/\s/g, ' ')).toBe('1 – 2 PM');
    // Up to midnight is still that day.
    expect(blockTimeText(block('2026-11-05T04:00:00Z', '2026-11-05T08:00:00Z'), '2026-11-04', zone).replace(/\s/g, ' ')).toBe('8 PM – 12 AM');
  });

  it('says the days for time off that runs into other days, on each of them, as the app does', () => {
    // Monday, November 2 at 6:50 PM to Friday, November 6 at 6:50 PM.
    const vacation = block('2026-11-03T02:50:00Z', '2026-11-07T02:50:00Z');
    const days = 'Mon, Nov 2 at 6:50 PM – Fri, Nov 6 at 6:50 PM';
    for (const date of ['2026-11-02', '2026-11-04', '2026-11-06']) {
      expect(blockTimeText(vacation, date, zone).replace(/\s/g, ' ')).toBe(days);
    }
    // Past midnight runs into the next day too.
    expect(blockTimeText(block('2026-11-05T05:00:00Z', '2026-11-05T09:00:00Z'), '2026-11-04', zone).replace(/\s/g, ' ')).toBe(
      'Wed, Nov 4 at 9 PM – Thu, Nov 5 at 1 AM',
    );
  });
});

describe('what Void asks about a sale it only knows from its appointment', () => {
  const zone = 'America/Los_Angeles';
  const known = { id: 's', appointmentId: 'a', customerName: 'Luis Sample', totalCents: 125000 };

  it('names the amount and how it was paid, in plain words, and nothing it can’t be sure of', () => {
    expect(saleLine({ ...known, method: 'cash' }, zone, '2026-11-05')).toBe('Luis Sample: a $1,250 cash sale.');
    expect(saleLine({ ...known, method: 'other' }, zone, '2026-11-05')).toBe('Luis Sample: a $1,250 sale paid another way.');
    expect(saleLine({ ...known, method: 'card', customerName: null }, zone, null)).toBe('Walk-in: a $1,250 card sale.');
  });
});
