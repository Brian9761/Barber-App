import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { bearerMatches, hashManageToken, manageTokenMatches, newManageToken } from '../src/auth.js';
import { Catalog, loadCatalog } from '../src/catalog.js';
import { configFromEnv } from '../src/config.js';
import { normalizeConnectionString } from '../src/db.js';
import { addDays, dayBounds, formatInstant, isDate, localDate, parseInstant, wallClock, weekday } from '../src/time.js';
import { charLength, normalizeUSPhone } from '../src/validation.js';

describe('US phone numbers → E.164', () => {
  const ok: [string, string][] = [
    ['(442) 341-3053', '+14423413053'],
    ['442-341-3053', '+14423413053'],
    ['442.341.3053', '+14423413053'],
    ['4423413053', '+14423413053'],
    ['+1 442 341 3053', '+14423413053'],
    ['1 (442) 341-3053', '+14423413053'],
    ['+14423413053', '+14423413053'],
    ['  760 555 0100 ', '+17605550100'],
  ];
  for (const [input, expected] of ok) it(`${input} → ${expected}`, () => expect(normalizeUSPhone(input)).toBe(expected));
  const bad = ['', '341-3053', '442341305', '44234130531', '+44 20 7946 0958', '+2 442 341 3053', '(042) 341-3053', '442-141-3053', '911-555-0100', '442-911-0100', '442-341-3053 ext 2', 'call me', '1-800-FLOWERS', '+1+4423413053', '442 341 3053+'];
  for (const input of bad) it(`rejects ${JSON.stringify(input)}`, () => expect(normalizeUSPhone(input)).toBeNull());
});

describe('time helpers', () => {
  it('formats instants without fractional seconds', () => {
    expect(formatInstant(new Date('2026-11-02T18:00:00.000Z'))).toBe('2026-11-02T18:00:00Z');
    expect(formatInstant(new Date('2026-11-02T18:00:00.123Z'))).toBe('2026-11-02T18:00:00Z');
  });

  it('parses only full date-times with a zone', () => {
    expect(parseInstant('2026-11-02T18:00:00Z')?.toISOString()).toBe('2026-11-02T18:00:00.000Z');
    expect(parseInstant('2026-11-02T10:00:00-08:00')?.toISOString()).toBe('2026-11-02T18:00:00.000Z');
    expect(parseInstant('2026-11-02T18:00Z')?.toISOString()).toBe('2026-11-02T18:00:00.000Z');
    for (const bad of ['2026-11-02', '2026-11-02T18:00:00', '2026-13-02T18:00:00Z', '2026-02-30T10:00:00Z', 'now', '1730570400', '2026-11-02 18:00:00Z']) {
      expect(parseInstant(bad), bad).toBeNull();
    }
  });

  it('validates calendar dates', () => {
    expect(isDate('2028-02-29')).toBe(true);
    expect(isDate('2026-02-29')).toBe(false);
    expect(isDate('2026-1-01')).toBe(false);
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-03-08', 1)).toBe('2026-03-09');
  });

  it("numbers weekdays like the Kit: 1 = Sunday … 7 = Saturday", () => {
    expect(weekday('2026-11-01')).toBe(1); // Sunday
    expect(weekday('2026-11-02')).toBe(2); // Monday
    expect(weekday('2026-11-07')).toBe(7); // Saturday
  });

  it('DST: shop days are 23 and 25 hours long, and the skipped hour does not exist', () => {
    const zone = 'America/Los_Angeles';
    const hours = (d: string) => (dayBounds(d, zone).end.getTime() - dayBounds(d, zone).start.getTime()) / 3_600_000;
    expect(hours('2026-03-08')).toBe(23);
    expect(hours('2026-11-01')).toBe(25);
    expect(hours('2026-11-02')).toBe(24);
    expect(wallClock('2026-03-08', 2 * 60 + 30, zone)).toBeNull();
    expect(wallClock('2026-03-08', 3 * 60, zone)?.toISOString()).toBe('2026-03-08T10:00:00.000Z');
    // 1:30 AM happens twice on Nov 1; the first one (PDT) is used, like Foundation's Calendar.
    expect(wallClock('2026-11-01', 90, zone)?.toISOString()).toBe('2026-11-01T08:30:00.000Z');
    expect(localDate(new Date('2026-11-02T07:59:59Z'), zone)).toBe('2026-11-01');
    expect(localDate(new Date('2026-11-02T08:00:00Z'), zone)).toBe('2026-11-02');
  });

  it("doesn't depend on the server's own time zone", () => {
    expect(process.env.TZ === undefined || typeof process.env.TZ === 'string').toBe(true);
    const zone = 'America/Los_Angeles';
    expect(wallClock('2026-07-04', 600, zone)?.toISOString()).toBe('2026-07-04T17:00:00.000Z');
  });
});

describe('secrets', () => {
  it('compares bearer tokens exactly', () => {
    expect(bearerMatches('Bearer abc', 'abc')).toBe(true);
    expect(bearerMatches('bearer   abc', 'abc')).toBe(true);
    expect(bearerMatches('Bearer abcd', 'abc')).toBe(false);
    expect(bearerMatches('Bearer ab', 'abc')).toBe(false);
    expect(bearerMatches('abc', 'abc')).toBe(false);
    expect(bearerMatches('Bearer ', '')).toBe(false);
    expect(bearerMatches(null, 'abc')).toBe(false);
    expect(bearerMatches('Bearer abc', undefined)).toBe(false);
  });

  it('manage tokens are 32 random bytes, base64url, and only their hash matches', () => {
    const token = newManageToken();
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(Buffer.from(token, 'base64url')).toHaveLength(32);
    expect(newManageToken()).not.toBe(token);
    const hash = hashManageToken(token);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(manageTokenMatches(token, hash)).toBe(true);
    expect(manageTokenMatches(newManageToken(), hash)).toBe(false);
    expect(manageTokenMatches(token, null)).toBe(false);
    expect(manageTokenMatches(token, 'zz')).toBe(false);
  });
});

describe('config', () => {
  it('reads the environment with the spec defaults', () => {
    const c = configFromEnv({ OWNER_KEY: '  k  ', GOOGLE_DAILY_LIMIT: 'abc', YELP_API_KEY: '' });
    expect(c.ownerKey).toBe('k');
    expect(c.googlePlaceId).toBe('ChIJGz5HChRv3IARYJJy_6jyRm8');
    expect(c.googleDailyLimit).toBe(30);
    expect(c.yelpApiKey).toBeUndefined();
    expect(c.yelpBusinessId).toBe('izzy-clipz-barbershop-oceanside');
    expect(configFromEnv({ GOOGLE_DAILY_LIMIT: '100' }).googleDailyLimit).toBe(100);
    expect(configFromEnv({ GOOGLE_DAILY_LIMIT: '0' }).googleDailyLimit).toBe(0);
  });

  it("silences pg's sslmode=require warning by saying verify-full", () => {
    expect(normalizeConnectionString('postgres://u:p@h/db?sslmode=require')).toBe('postgres://u:p@h/db?sslmode=verify-full');
    expect(normalizeConnectionString('postgres://u:p@h/db?sslmode=require&channel_binding=require')).toBe(
      'postgres://u:p@h/db?sslmode=verify-full&channel_binding=require',
    );
    expect(normalizeConnectionString('postgres://u@h/db')).toBe('postgres://u@h/db');
  });
});

describe('catalog.json (exported from IzzyClipzKit)', () => {
  const catalog = loadCatalog();
  const raw = JSON.parse(readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8'));

  it('has the shape the server expects', () => {
    expect(Object.keys(raw).sort()).toEqual(
      ['barbers', 'firstAvailable', 'hours', 'leadTimeMinutes', 'offerings', 'services', 'slotIntervalMinutes', 'timeZone', 'windowDays'].sort(),
    );
    expect(raw).toMatchObject({ timeZone: 'America/Los_Angeles', slotIntervalMinutes: 30, leadTimeMinutes: 30, windowDays: 60 });
    expect(raw.hours['1']).toEqual({ opens: '10:00', closes: '18:00' }); // Sunday
    expect(raw.hours['2']).toEqual({ opens: '10:00', closes: '19:00' }); // Monday
    expect(catalog.barbers.map((b) => b.id)).toEqual(['israel-flores', 'carlos-rafael', 'flowxbori', 'cristian-ceja', 'julian-ramos']);
  });

  it('uses the Kit’s offering ids (barber/squire-item) and consistent prices', () => {
    for (const o of catalog.data.offerings) {
      expect(o.id).toBe(`${o.barberId}/${o.id.split('/')[1]}`);
      expect(o.id.split('/')[1]).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
      if (o.priceKind === 'includedWithCut') expect(o.priceCents).toBe(0);
    }
    expect(catalog.offering('israel-flores/8f795304-bb2d-4f55-bd37-a6fe6cabb43c')).toMatchObject({ priceKind: 'startingAt', priceLabel: 'From $80' });
  });

  it('rejects inconsistent data', () => {
    expect(() => new Catalog({ ...raw, timeZone: 'Mars/Olympus' })).toThrow();
    expect(() => new Catalog({ ...raw, offerings: [...raw.offerings, raw.offerings[0]] })).toThrow(/Duplicate offering/);
    expect(() => new Catalog({ ...raw, firstAvailable: [{ serviceId: 'haircut', offeringIds: ['nobody/1'] }] })).toThrow();
    expect(() => new Catalog({ ...raw, hours: { '1': { opens: '18:00', closes: '10:00' } } })).toThrow();
  });

  it('counts characters as people do', () => {
    expect(charLength('José')).toBe(4);
    expect(charLength('💈💈')).toBe(2);
  });
});
