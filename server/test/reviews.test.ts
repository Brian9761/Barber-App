import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { GOOGLE_FIELD_MASK, normalizeGoogle, normalizeYelp } from '../src/reviews.js';
import { CRON_SECRET, useHarness } from './helpers/harness.js';

const fixture = (path: string) => JSON.parse(readFileSync(new URL(`./fixtures/${path}`, import.meta.url), 'utf8'));
const GOOGLE = fixture('google/place-details.json');
const GOOGLE_403 = fixture('google/error-403.json');
const YELP_BUSINESS = fixture('yelp/business.json');
const YELP_REVIEWS = fixture('yelp/reviews.json');
const YELP_403 = fixture('yelp/error-403.json');

const MAPS_URL = 'https://www.google.com/maps/search/?api=1&query=Izzy%20Clipz%20Barbershop&query_place_id=ChIJGz5HChRv3IARYJJy_6jyRm8';
const YELP_URL = 'https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside';
const PLACES = 'https://places.googleapis.com/v1/places/';
const YELP_API = 'https://api.yelp.com/v3/businesses/';

const h = useHarness({ now: '2026-11-02T19:10:00Z' });

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

function googleOn(body: unknown = GOOGLE, status = 200) {
  h.config.googlePlacesApiKey = 'AIzaFixtureKey';
  h.fetch.on(PLACES, () => jsonResponse(body, status));
}

function yelpOn(business: unknown = YELP_BUSINESS, reviews: unknown = YELP_REVIEWS, status = { business: 200, reviews: 200 }) {
  h.config.yelpApiKey = 'yelp-fixture-key';
  h.fetch.on(YELP_API, (url) =>
    url.pathname.endsWith('/reviews') ? jsonResponse(reviews, status.reviews) : jsonResponse(business, status.business),
  );
}

const EXPECTED_GOOGLE = {
  available: true,
  rating: 4.9,
  count: 59,
  url: GOOGLE.googleMapsUri,
  fetchedAt: '2026-11-02T19:10:00Z',
  reviews: [
    {
      author: 'Fixture Reviewer One',
      authorPhotoUrl: 'https://lh3.googleusercontent.com/a-/ALV-UjXFixtureAvatarOne=s128-c0x00000000-cc-rp-mo',
      authorUrl: 'https://www.google.com/maps/contrib/100000000000000000001/reviews',
      rating: 5,
      text: 'Fixture review one. Test data shaped like a Places API (New) review, not a real review.',
      relativeTime: '2 weeks ago',
      publishedAt: '2026-10-17T21:04:33Z',
      url: GOOGLE.reviews[0].googleMapsUri,
    },
    {
      author: 'Fixture Reviewer Two',
      authorPhotoUrl: 'https://lh3.googleusercontent.com/a/ACg8ocFixtureAvatarTwo=s128-c0x00000000-cc-rp-mo-ba2',
      authorUrl: 'https://www.google.com/maps/contrib/100000000000000000002/reviews',
      rating: 4,
      text: 'Fixture review two, translated by Google from Spanish. Test data only.',
      relativeTime: 'a month ago',
      publishedAt: '2026-09-28T16:20:05Z',
      url: GOOGLE.reviews[1].googleMapsUri,
    },
    {
      author: 'Fixture Reviewer Three',
      authorPhotoUrl: 'https://lh3.googleusercontent.com/a-/ALV-UjXFixtureAvatarThree=s128-c0x00000000-cc-rp-mo',
      authorUrl: 'https://www.google.com/maps/contrib/100000000000000000003/reviews',
      rating: 5,
      text: '',
      relativeTime: '3 months ago',
      publishedAt: '2026-07-30T03:11:48Z',
      url: GOOGLE.reviews[2].googleMapsUri,
    },
    {
      author: 'Fixture Reviewer Four',
      authorPhotoUrl: 'https://lh3.googleusercontent.com/a-/ALV-UjXFixtureAvatarFour=s128-c0x00000000-cc-rp-mo-ba3',
      authorUrl: 'https://www.google.com/maps/contrib/100000000000000000004/reviews',
      rating: 5,
      text: 'Fixture review four. Test data only.\n\nIt has a line break.',
      relativeTime: '5 months ago',
      publishedAt: '2026-05-22T18:45:00Z',
      url: GOOGLE.reviews[3].googleMapsUri,
    },
    {
      author: 'Fixture Reviewer Five',
      authorPhotoUrl: 'https://lh3.googleusercontent.com/a/ACg8ocFixtureAvatarFive=s128-c0x00000000-cc-rp-mo',
      authorUrl: 'https://www.google.com/maps/contrib/100000000000000000005/reviews',
      rating: 3,
      text: 'Fixture review five. Test data only.',
      relativeTime: 'a year ago',
      publishedAt: '2025-10-02T12:00:00Z',
      url: GOOGLE.reviews[4].googleMapsUri,
    },
  ],
};

describe('Google reviews', () => {
  it('without a key: unavailable with the Maps link, and no call to Google', async () => {
    const res = await h.call('GET', '/api/reviews');
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(res.body.google).toEqual({ available: false, rating: null, count: null, url: MAPS_URL, reviews: [], fetchedAt: null });
    expect(h.fetch.calls).toHaveLength(0);
  });

  it('normalizes the recorded Place Details (New) response, in Google’s order', async () => {
    googleOn();
    const res = await h.call('GET', '/api/reviews');
    expect(res.body.google).toEqual(EXPECTED_GOOGLE);
    const call = h.fetch.calls[0]!;
    expect(call.url).toBe(`${PLACES}ChIJGz5HChRv3IARYJJy_6jyRm8?languageCode=en&regionCode=US`);
    expect(call.headers['x-goog-api-key']).toBe('AIzaFixtureKey');
    expect(call.headers['x-goog-fieldmask']).toBe('rating,userRatingCount,reviews,googleMapsUri');
    expect(GOOGLE_FIELD_MASK).not.toContain('reviewSummary');
  });

  it('stores nothing from Google: no review text, author, rating or link anywhere in the database', async () => {
    googleOn();
    await h.call('GET', '/api/reviews');
    const tables = (await h.database.pool.query(`SELECT tablename FROM pg_tables WHERE schemaname = 'public'`)).rows.map((r) => r.tablename);
    let dump = '';
    for (const table of tables) dump += JSON.stringify((await h.database.pool.query(`SELECT * FROM ${table}`)).rows);
    // (No bare "4.9" needle: it shows up inside timestamps such as "…:54.93Z".)
    for (const needle of ['Fixture Reviewer', 'Fixture review', 'Reseña', 'googleusercontent', 'maps/contrib', 'places/ChIJ', 'local/review', 'cid=8018362994233872992', '2 weeks ago']) {
      expect(dump).not.toContain(needle);
    }
    // Only our own counter.
    const usage = await h.database.pool.query('SELECT day, counter, count FROM api_usage');
    expect(usage.rows).toEqual([{ day: '2026-11-02', counter: 'google_places_details', count: 1 }]);
  });

  it('stops calling Google after GOOGLE_DAILY_LIMIT calls in a shop-local day', async () => {
    googleOn();
    h.config.googleDailyLimit = 3;
    for (let i = 0; i < 3; i++) expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(true);
    const capped = await h.call('GET', '/api/reviews');
    expect(capped.body.google).toMatchObject({ available: false, url: MAPS_URL, reviews: [] });
    expect(h.fetch.calls).toHaveLength(3);
    // 11:59 PM PST is still the same day; midnight PST is a new one.
    h.setNow('2026-11-03T07:59:00Z');
    expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(false);
    h.setNow('2026-11-03T08:00:00Z');
    expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(true);
  });

  it('a limit of 0 turns Google off', async () => {
    googleOn();
    h.config.googleDailyLimit = 0;
    expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(false);
    expect(h.fetch.calls).toHaveLength(0);
  });

  it('falls back to the Maps link on an API error, a network failure or a response it cannot read', async () => {
    googleOn(GOOGLE_403, 403);
    expect((await h.call('GET', '/api/reviews')).body.google).toMatchObject({ available: false, url: MAPS_URL });
    h.fetch.clear();
    h.fetch.on(PLACES, () => {
      throw new TypeError('fetch failed');
    });
    expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(false);
    h.fetch.clear();
    h.fetch.on(PLACES, () => new Response('<html>oops</html>', { status: 200 }));
    expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(false);
    h.fetch.clear();
    h.fetch.on(PLACES, () => jsonResponse({ reviews: 'nope' }));
    expect((await h.call('GET', '/api/reviews')).body.google.available).toBe(false);
    expect(h.logs.filter((l) => l.message.startsWith('Google'))).toHaveLength(3);
  });

  it('copes with a place that has no reviews yet, and drops unusable entries', () => {
    expect(normalizeGoogle({}, MAPS_URL, new Date('2026-11-02T19:10:00Z'))).toEqual({
      available: true,
      rating: null,
      count: null,
      url: MAPS_URL,
      reviews: [],
      fetchedAt: '2026-11-02T19:10:00Z',
    });
    const odd = normalizeGoogle(
      {
        rating: 4.86,
        userRatingCount: 7,
        googleMapsUri: 'javascript:alert(1)',
        reviews: [{ rating: 'five' }, { rating: 4.6, authorAttribution: { displayName: '  ' }, publishTime: 'yesterday' }],
      },
      MAPS_URL,
      new Date('2026-11-02T19:10:00Z'),
    )!;
    expect(odd.rating).toBe(4.9);
    expect(odd.url).toBe(MAPS_URL);
    expect(odd.reviews).toEqual([
      { author: 'Google user', authorPhotoUrl: null, authorUrl: null, rating: 5, text: '', relativeTime: null, publishedAt: null, url: null },
    ]);
  });
});

const EXPECTED_YELP = {
  available: true,
  rating: 4.5,
  count: 12,
  url: YELP_BUSINESS.url,
  fetchedAt: '2026-11-02T19:10:00Z',
  reviews: [
    {
      author: 'Fixture A.',
      authorPhotoUrl: 'https://s3-media0.fl.yelpcdn.com/photo/FixtureUserPhoto0001/o.jpg',
      authorUrl: 'https://www.yelp.com/user_details?userid=FixtureYelpUser0000001',
      rating: 5,
      text: 'Fixture Yelp excerpt one. Test data shaped like a Yelp Places API review excerpt, not a real review...',
      relativeTime: null,
      publishedAt: '2026-08-15T00:22:09Z',
      url: YELP_REVIEWS.reviews[0].url,
    },
    {
      author: 'Fixture B.',
      authorPhotoUrl: null,
      authorUrl: 'https://www.yelp.com/user_details?userid=FixtureYelpUser0000002',
      rating: 4,
      text: 'Fixture Yelp excerpt two. Test data only...',
      relativeTime: null,
      publishedAt: '2026-01-03T17:05:44Z',
      url: YELP_REVIEWS.reviews[1].url,
    },
    {
      author: 'Fixture C.',
      authorPhotoUrl: null,
      authorUrl: 'https://www.yelp.com/user_details?userid=FixtureYelpUser0000003',
      rating: 5,
      text: 'Fixture Yelp excerpt three. Test data only...',
      relativeTime: null,
      publishedAt: '2025-11-21T04:41:13Z',
      url: YELP_REVIEWS.reviews[2].url,
    },
  ],
};

describe('Yelp reviews', () => {
  it('without YELP_API_KEY: unavailable with the Yelp page link, no calls', async () => {
    const res = await h.call('GET', '/api/reviews');
    expect(res.body.yelp).toEqual({ available: false, rating: null, count: null, url: YELP_URL, reviews: [], fetchedAt: null });
    expect(h.fetch.calls).toHaveLength(0);
  });

  it('normalizes Business Details + Reviews, keeping Yelp’s links (and tracking parameters) as they are', async () => {
    yelpOn();
    const res = await h.call('GET', '/api/reviews');
    expect(res.body.yelp).toEqual(EXPECTED_YELP);
    expect(res.body.yelp.url).toContain('utm_source=FixtureCreative00000000');
    const urls = h.fetch.calls.map((c) => c.url).sort();
    expect(urls).toEqual([
      `${YELP_API}izzy-clipz-barbershop-oceanside/reviews?locale=en_US&sort_by=yelp_sort`,
      `${YELP_API}izzy-clipz-barbershop-oceanside?locale=en_US`,
    ]);
    expect(h.fetch.calls[0]!.headers.authorization).toBe('Bearer yelp-fixture-key');
  });

  it('serves the cache for 12 hours, then refreshes', async () => {
    yelpOn();
    await h.call('GET', '/api/reviews');
    expect(h.fetch.calls).toHaveLength(2);
    h.advance(11 * 60 + 59);
    const cached = await h.call('GET', '/api/reviews');
    expect(cached.body.yelp.fetchedAt).toBe('2026-11-02T19:10:00Z');
    expect(h.fetch.calls).toHaveLength(2);
    h.advance(1);
    const fresh = await h.call('GET', '/api/reviews');
    expect(fresh.body.yelp.fetchedAt).toBe('2026-11-03T07:10:00Z');
    expect(h.fetch.calls).toHaveLength(4);
  });

  it('if Yelp is down, serves a copy younger than 24 hours, and never one older', async () => {
    yelpOn();
    await h.call('GET', '/api/reviews');
    h.fetch.clear();
    h.fetch.on(YELP_API, () => jsonResponse({ error: { code: 'INTERNAL_ERROR', description: 'down' } }, 503));
    h.advance(13 * 60);
    const stale = await h.call('GET', '/api/reviews');
    expect(stale.body.yelp).toMatchObject({ available: true, fetchedAt: '2026-11-02T19:10:00Z' });
    h.advance(11 * 60); // exactly 24 hours old
    const expired = await h.call('GET', '/api/reviews');
    expect(expired.body.yelp).toEqual({ available: false, rating: null, count: null, url: YELP_URL, reviews: [], fetchedAt: null });
    // And the expired copy is gone from the database.
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM yelp_cache')).rows[0].n).toBe(0);
  });

  it('on the Base plan (no review excerpts) shows rating and count only', async () => {
    yelpOn(YELP_BUSINESS, YELP_403, { business: 200, reviews: 403 });
    const res = await h.call('GET', '/api/reviews');
    expect(res.body.yelp).toEqual({ ...EXPECTED_YELP, reviews: [] });
  });

  it('a failing business lookup without a cached copy is unavailable', async () => {
    yelpOn({ error: { code: 'NOT_FOUND', description: 'Resource Not Found' } }, YELP_REVIEWS, { business: 404, reviews: 404 });
    expect((await h.call('GET', '/api/reviews')).body.yelp.available).toBe(false);
    expect(normalizeYelp({ rating: 'x' }, null, YELP_URL, new Date())).toBeNull();
  });

  it('the daily cron purges every cached Yelp row', async () => {
    yelpOn();
    await h.call('GET', '/api/reviews');
    const cron = await h.call('GET', '/api/cron/daily', { headers: { authorization: `Bearer ${CRON_SECRET}` } });
    expect(cron.status).toBe(200);
    expect(cron.body.deleted.yelpCache).toBe(1);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM yelp_cache')).rows[0].n).toBe(0);
  });

  it('Google and Yelp stay separate: two sources, never a combined rating', async () => {
    googleOn();
    yelpOn();
    const res = await h.call('GET', '/api/reviews');
    expect(Object.keys(res.body)).toEqual(['google', 'yelp']);
    expect(res.body.google.rating).toBe(4.9);
    expect(res.body.yelp.rating).toBe(4.5);
  });
});
