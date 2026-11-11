import { describe, expect, it } from 'vitest';
import { catalog } from '../test/api';
import { anyBarberOption, categories, haircutLine, monogramTone, offeringsForService, serviceDuration, servicePrice, servicePriceRange } from './catalog';
import { cardBrandName, cardLabel, durationLabel, durationRange, fromPrice, list, money, priceLabel, priceSummary, windowLabel } from './format';

const fixed = (dollars: number) => ({ priceCents: dollars * 100, priceKind: 'fixed' as const });
const from = (dollars: number) => ({ priceCents: dollars * 100, priceKind: 'startingAt' as const });
const included = { priceCents: 0, priceKind: 'includedWithCut' as const };

describe('prices', () => {
  it('are whole dollars without cents, like the apps', () => {
    expect(money(3500)).toBe('$35');
    expect(money(750)).toBe('$7.50');
    expect(money(50)).toBe('$0.50');
    expect(money(2005)).toBe('$20.05');
  });

  it('label a menu item like the Kit’s Price.label', () => {
    expect(priceLabel(fixed(35))).toBe('$35');
    expect(priceLabel(from(80))).toBe('From $80');
    expect(priceLabel(included)).toBe('Included with cut');
  });

  it('sum up several barbers like the Kit’s Price.summary, for "Any barber"', () => {
    expect(priceSummary([fixed(35), fixed(45)])).toBe('$35–$45');
    expect(priceSummary([fixed(35), fixed(35)])).toBe('$35');
    expect(priceSummary([from(80), fixed(90)])).toBe('From $80');
    expect(priceSummary([included, fixed(5)])).toBe('$5');
    expect(priceSummary([included])).toBe('Included with cut');
    expect(priceSummary([])).toBe('');
  });

  it('read "$40" or "From $35" across barbers on the menu pages', () => {
    expect(fromPrice([fixed(40)])).toBe('$40');
    expect(fromPrice([fixed(40), fixed(40)])).toBe('$40');
    expect(fromPrice([fixed(35), fixed(45)])).toBe('From $35');
    expect(fromPrice([from(80)])).toBe('From $80');
    expect(fromPrice([included, included])).toBe('Included with cut');
  });

  it('come out right for the shop’s real menu', () => {
    expect(servicePrice(catalog, 'haircut')).toBe('From $35');
    expect(servicePrice(catalog, 'military-haircut')).toBe('From $25');
    expect(servicePrice(catalog, 'seniors-haircut')).toBe('$16');
    expect(servicePrice(catalog, 'vip')).toBe('$80');
    expect(servicePrice(catalog, 'lightener')).toBe('From $80');
    expect(servicePrice(catalog, 'eyebrows')).toBe('Included with cut');
    expect(servicePriceRange(catalog, 'haircut')).toBe('$35–$45');
    expect(anyBarberOption(catalog, 'haircut')?.priceLabel).toBe('$35');
    expect(anyBarberOption(catalog, 'haircut-and-beard')?.priceLabel).toBe('$55–$60');
    expect(anyBarberOption(catalog, 'vip')).toBeNull();
    expect(haircutLine(catalog, 'carlos-rafael')).toBe('Haircut $45');
    expect(haircutLine(catalog, 'flowxbori')).toBe('Haircut from $35');
  });
});

describe('lengths', () => {
  it('read like the Kit’s DurationText', () => {
    expect(durationLabel(15)).toBe('15 min');
    expect(durationLabel(60)).toBe('1 hr');
    expect(durationLabel(75)).toBe('1 hr 15 min');
    expect(durationRange([45])).toBe('45 min');
    expect(durationRange([15, 30])).toBe('15–30 min');
    expect(durationRange([45, 60])).toBe('45 min – 1 hr');
    expect(serviceDuration(catalog, 'haircut')).toBe('45 min – 1 hr');
    expect(serviceDuration(catalog, 'hot-towel-shave')).toBe('15–30 min');
  });
});

describe('the menu', () => {
  it('lists each service’s barbers cheapest first, then in team order', () => {
    expect(offeringsForService(catalog, 'haircut').map((o) => `${o.barberId} ${o.priceCents}`)).toEqual([
      'flowxbori 3500',
      'cristian-ceja 3500',
      'julian-ramos 3500',
      'israel-flores 4000',
      'flowxbori 4000',
      'carlos-rafael 4500',
    ]);
  });

  it('groups services under the app’s categories, in menu order', () => {
    expect(categories(catalog).map((g) => [g.title, g.anchor, g.services.length])).toEqual([
      ['Haircuts', 'haircuts', 3],
      ['Packages', 'packages', 2],
      ['Shaves', 'shaves', 1],
      ['Color & Texture', 'color-texture', 2],
      ['Add-ons', 'add-ons', 4],
    ]);
  });

  it('gives each barber the app’s tile color by their place on the team', () => {
    expect(catalog.barbers.map((b) => monogramTone(catalog, b.id))).toEqual(['bone', 'blue', 'ink', 'bone', 'blue']);
  });
});

describe('words', () => {
  it('list names and windows the way the app says them', () => {
    expect(list(['Flowxbori', 'Cristian', 'Julian'])).toBe('Flowxbori, Cristian or Julian');
    expect(list(['Izzy', 'Carlos'], 'and')).toBe('Izzy and Carlos');
    expect(list(['Izzy'])).toBe('Izzy');
    expect(windowLabel(30)).toBe('30 minutes');
    expect(windowLabel(60)).toBe('1 hour');
    expect(windowLabel(90)).toBe('90 minutes');
    expect(windowLabel(2880)).toBe('48 hours');
  });

  it('name cards the way people say them', () => {
    expect(cardLabel({ brand: 'visa', last4: '4242' })).toBe('Visa •••• 4242');
    expect(cardBrandName('amex')).toBe('American Express');
    expect(cardBrandName('unknown')).toBe('Card');
  });
});
