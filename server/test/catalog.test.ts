import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { Catalog, loadCatalog } from '../src/catalog.js';
import { configFromEnv } from '../src/config.js';
import type { Deps } from '../src/deps.js';
import { loadWebsiteCatalog, websiteCatalogSchema } from '../src/website.js';

// GET /api/catalog: the website's catalog, which is data/catalog.json as the Kit
// exports it (the booking rules plus the shop and the menu's and team's words).

const raw = JSON.parse(readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8'));

/** The app with its database down: the catalog needs none. */
function appWithoutDatabase() {
  const down = async (): Promise<never> => {
    throw new Error('connection refused');
  };
  // Asserted rather than annotated: Deps grows as the server's other parts land (a computer's
  // sign-in code, say), and the catalog needs none of it, so this keeps compiling either way.
  const deps = {
    db: { query: down, transaction: down },
    config: configFromEnv({}),
    catalog: loadCatalog(),
    now: () => new Date('2026-11-04T18:00:00Z'),
    uuid: () => '00000000-0000-4000-8000-000000000001',
    manageToken: () => 'x'.repeat(43),
    stripe: () => {
      throw new Error('No Stripe in this test');
    },
    blob: { put: down, del: down },
    fetch: down,
    clientIp: () => undefined,
    log: { error: () => undefined, warn: () => undefined },
    computerCode: () => '000000',
  } as Deps;
  return createApp(deps);
}

async function get(path = '/api/catalog', method = 'GET') {
  const response = await appWithoutDatabase().fetch(new Request(`https://izzy-clipz-api.test${path}`, { method }));
  const text = await response.text();
  return { status: response.status, headers: response.headers, body: text ? JSON.parse(text) : undefined };
}

describe('GET /api/catalog', () => {
  it('answers with catalog.json, cacheable for 5 minutes, without a database', async () => {
    const res = await get();
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toBe('public, max-age=300');
    expect(res.headers.get('content-type')).toBe('application/json; charset=utf-8');
    expect(res.headers.get('x-content-type-options')).toBe('nosniff');
    // Everything the Kit exports, nothing more and nothing less.
    expect(res.body).toEqual(raw);
  });

  it('books against the same menu, team, hours and rules as the server', async () => {
    const { body } = await get();
    const server = loadCatalog();
    // The server's own catalog loads it as is.
    const website = new Catalog(body);
    expect(website.data).toEqual(server.data);
    expect(website.data.offerings.some((o) => 'note' in o)).toBe(false);
    expect(body).toMatchObject({ timeZone: 'America/Los_Angeles', slotIntervalMinutes: 30, leadTimeMinutes: 30, windowDays: 60 });
    // The booking code reads the same offerings (a barber's note is only for the website).
    expect(body.offerings.map(({ note: _note, ...offering }: { note?: string }) => offering)).toEqual(server.data.offerings);
    expect(body.offerings.find((o: { id: string }) => o.id === 'carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41').note).toBe(
      'Includes mustache & eyebrows, plus straight-razor detail and styling.',
    );
    expect(body.firstAvailable).toEqual(server.data.firstAvailable);
    expect(body.hours).toEqual(server.data.hours);
    expect(body.offerings.find((o: { serviceId: string }) => o.serviceId === 'lightener')).toMatchObject({
      priceKind: 'startingAt',
      priceLabel: 'From $80',
      priceCents: 8000,
    });
  });

  it("carries the shop's details: phone, address, map links and Instagram", async () => {
    const { shop } = (await get()).body;
    expect(shop).toMatchObject({
      name: 'Izzy Clipz',
      fullName: 'Izzy Clipz Barbershop',
      phone: { e164: '+14423413053', display: '(442) 341-3053' },
      address: {
        street: '1919 Mission Ave',
        unit: 'Ste 105',
        city: 'Oceanside',
        state: 'CA',
        postalCode: '92058',
        lines: ['1919 Mission Ave, Ste 105', 'Oceanside, CA 92058'],
      },
      coordinate: { latitude: 33.2034409, longitude: -117.364815 },
      instagram: { handle: 'izzy_clipz_barbershop_', url: 'https://www.instagram.com/izzy_clipz_barbershop_/' },
      websiteUrl: 'https://www.izzyclipzbarbershop.net',
      paymentMethods: ['Credit card', 'Gift card'],
    });
    expect(shop.appleMapsUrl).toMatch(/^https:\/\/maps\.apple\.com\/\?/);
    expect(shop.appleMapsDirectionsUrl).toMatch(/^https:\/\/maps\.apple\.com\/\?daddr=/);
    expect(shop.googleMapsUrl).toContain('query_place_id=ChIJGz5HChRv3IARYJJy_6jyRm8');
    expect(shop.googleMapsDirectionsUrl).toMatch(/^https:\/\/www\.google\.com\/maps\/dir\/\?api=1&destination=/);
    expect(shop.googleReviewUrl).toBe('https://search.google.com/local/writereview?placeid=ChIJGz5HChRv3IARYJJy_6jyRm8');
    expect(shop.highlights).toContain('Walk-ins welcome');
    expect(shop.about.length).toBeGreaterThan(0);
    expect(shop.accessibility.length).toBeGreaterThan(0);
  });

  it('describes every service, in menu order by category, with the favorites marked', async () => {
    const { services } = (await get()).body as { services: { id: string; description?: string; category: string; popular: boolean }[] };
    for (const service of services) expect(service.description, service.id).toMatch(/\S/);
    expect(services.find((s) => s.id === 'vip')?.description).toBe('The works in one appointment: a haircut, a shave and a facial.');
    expect([...new Set(services.map((s) => s.category))]).toEqual(['Haircuts', 'Packages', 'Shaves', 'Color & Texture', 'Add-ons']);
    expect(services.filter((s) => s.popular).map((s) => s.id)).toEqual(['haircut', 'haircut-and-beard', 'vip', 'hot-towel-shave']);
  });

  it("profiles every barber with the app's tile letters", async () => {
    const { barbers } = (await get()).body as { barbers: { id: string; title: string; bio: string; monogram: string; instagram?: unknown }[] };
    expect(barbers.map((b) => b.monogram)).toEqual(['IZ', 'CA', 'FL', 'CR', 'JU']);
    expect(barbers[0]).toMatchObject({ id: 'israel-flores', title: 'Owner · Barber', instagram: { handle: 'izzy_clipz_' } });
    for (const barber of barbers) expect(barber.bio, barber.id).toMatch(/\S/);
    expect(barbers.slice(1).every((b) => b.instagram === undefined)).toBe(true);
  });

  it('only answers GET', async () => {
    const res = await get('/api/catalog', 'POST');
    expect(res.status).toBe(405);
    expect(res.headers.get('allow')).toBe('GET');
    expect(res.body.error.code).toBe('invalid_request');
  });

  it("turns down a catalog.json without the website's fields", () => {
    expect(websiteCatalogSchema.safeParse(raw).success).toBe(true);
    expect(loadWebsiteCatalog()).toEqual(raw);
    const { shop: _shop, ...withoutShop } = raw;
    expect(websiteCatalogSchema.safeParse(withoutShop).success).toBe(false);
    const blankDescription = { ...raw, services: raw.services.map((s: object, i: number) => (i === 0 ? { ...s, description: '' } : s)) };
    expect(websiteCatalogSchema.safeParse(blankDescription).success).toBe(false);
    const httpLink = { ...raw, shop: { ...raw.shop, googleMapsUrl: 'http://maps.example' } };
    expect(websiteCatalogSchema.safeParse(httpLink).success).toBe(false);
    // The booking code still reads a catalog from before the website (it ignores these fields).
    const { shop: _ignored, ...older } = raw;
    expect(() => new Catalog(older)).not.toThrow();
  });
});
