import { DateTime } from 'luxon';
import { z } from 'zod';
import type { Deps } from './deps.js';
import { json } from './http.js';
import type { Context } from './router.js';
import { formatInstant, localDate, parseInstant } from './time.js';

// GET /api/reviews → { google, yelp }, never cached.
//
// Google (Places API New, Place Details): fetched live on every request and
// passed through. Nothing from Google is stored, per the Maps terms: only our
// own call counter, to cap calls per day (GOOGLE_DAILY_LIMIT).
//
// Yelp (only with YELP_API_KEY): cached in yelp_cache, refreshed when older than
// 12 hours, and never served or kept past 24 hours, per the Yelp API terms.

export interface Review {
  author: string;
  authorPhotoUrl: string | null;
  authorUrl: string | null;
  rating: number;
  text: string;
  relativeTime: string | null;
  publishedAt: string | null;
  url: string | null;
}

export interface ReviewSource {
  available: boolean;
  rating: number | null;
  count: number | null;
  url: string;
  reviews: Review[];
  fetchedAt: string | null;
}

export const GOOGLE_FIELD_MASK = 'rating,userRatingCount,reviews,googleMapsUri';
export const GOOGLE_USAGE_COUNTER = 'google_places_details';
export const YELP_REFRESH_MS = 12 * 60 * 60 * 1000;
export const YELP_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const FETCH_TIMEOUT_MS = 6_000;

export function googleMapsUrl(placeId: string): string {
  return `https://www.google.com/maps/search/?api=1&query=Izzy%20Clipz%20Barbershop&query_place_id=${encodeURIComponent(placeId)}`;
}

export function yelpPageUrl(businessId: string): string {
  return `https://www.yelp.com/biz/${encodeURIComponent(businessId)}`;
}

function unavailable(url: string): ReviewSource {
  return { available: false, rating: null, count: null, url, reviews: [], fetchedAt: null };
}

/** A web URL we're willing to hand to the app, or null. */
function httpsUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const text = value.startsWith('//') ? `https:${value}` : value;
  try {
    const url = new URL(text);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : null;
  } catch {
    return null;
  }
}

function stars(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return Math.min(5, Math.max(1, Math.round(value)));
}

function average(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 5) return null;
  return Math.round(value * 10) / 10;
}

function count(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : null;
}

// Google ------------------------------------------------------------------------------

const googleText = z.object({ text: z.string().optional() }).partial().nullish();
const googlePlace = z.object({
  rating: z.unknown().optional(),
  userRatingCount: z.unknown().optional(),
  googleMapsUri: z.unknown().optional(),
  reviews: z
    .array(
      z.object({
        rating: z.unknown().optional(),
        text: googleText,
        originalText: googleText,
        relativePublishTimeDescription: z.string().nullish(),
        publishTime: z.string().nullish(),
        googleMapsUri: z.unknown().optional(),
        authorAttribution: z
          .object({ displayName: z.string().nullish(), uri: z.unknown().optional(), photoUri: z.unknown().optional() })
          .nullish(),
      }),
    )
    .nullish(),
});

/** Place Details (New) JSON → ReviewSource, in Google's own order ("most relevant"). */
export function normalizeGoogle(body: unknown, fallbackUrl: string, fetchedAt: Date): ReviewSource | null {
  const parsed = googlePlace.safeParse(body);
  if (!parsed.success) return null;
  const place = parsed.data;
  const reviews: Review[] = [];
  for (const r of place.reviews ?? []) {
    const rating = stars(r.rating);
    if (rating === null) continue;
    const published = r.publishTime ? parseInstant(r.publishTime) : null;
    reviews.push({
      author: r.authorAttribution?.displayName?.trim() || 'Google user',
      authorPhotoUrl: httpsUrl(r.authorAttribution?.photoUri),
      authorUrl: httpsUrl(r.authorAttribution?.uri),
      rating,
      text: (r.text?.text ?? r.originalText?.text ?? '').trim(),
      relativeTime: r.relativePublishTimeDescription?.trim() || null,
      publishedAt: published ? formatInstant(published) : null,
      url: httpsUrl(r.googleMapsUri),
    });
  }
  return {
    available: true,
    rating: average(place.rating),
    count: count(place.userRatingCount),
    url: httpsUrl(place.googleMapsUri) ?? fallbackUrl,
    reviews: reviews.slice(0, 5),
    fetchedAt: formatInstant(fetchedAt),
  };
}

async function countGoogleCall(deps: Deps, now: Date): Promise<number> {
  const day = localDate(now, deps.catalog.timeZone);
  const { rows } = await deps.db.query<{ count: number }>(
    `INSERT INTO api_usage (day, counter, count) VALUES ($1, $2, 1)
     ON CONFLICT (day, counter) DO UPDATE SET count = api_usage.count + 1
     RETURNING count`,
    [day, GOOGLE_USAGE_COUNTER],
  );
  return rows[0]?.count ?? 1;
}

export async function googleReviews(deps: Deps): Promise<ReviewSource> {
  const { googlePlacesApiKey: key, googlePlaceId: placeId, googleDailyLimit } = deps.config;
  const mapsUrl = googleMapsUrl(placeId);
  if (!key) return unavailable(mapsUrl);
  const now = deps.now();
  try {
    // Counted before calling, so failures and retries are inside the cap too.
    if ((await countGoogleCall(deps, now)) > googleDailyLimit) return unavailable(mapsUrl);
    const response = await deps.fetch(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?languageCode=en&regionCode=US`,
      {
        headers: { 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': GOOGLE_FIELD_MASK },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      },
    );
    if (!response.ok) {
      deps.log.warn('Google Place Details failed', { status: response.status });
      return unavailable(mapsUrl);
    }
    return normalizeGoogle(await response.json(), mapsUrl, now) ?? unavailable(mapsUrl);
  } catch (error) {
    deps.log.warn('Google Place Details failed', { error: error instanceof Error ? error.message : String(error) });
    return unavailable(mapsUrl);
  }
}

// Yelp --------------------------------------------------------------------------------

const yelpBusiness = z.object({
  rating: z.unknown().optional(),
  review_count: z.unknown().optional(),
  url: z.unknown().optional(),
});
const yelpReviews = z.object({
  reviews: z
    .array(
      z.object({
        url: z.unknown().optional(),
        text: z.string().nullish(),
        rating: z.unknown().optional(),
        time_created: z.string().nullish(),
        user: z.object({ name: z.string().nullish(), profile_url: z.unknown().optional(), image_url: z.unknown().optional() }).nullish(),
      }),
    )
    .nullish(),
});

/** Yelp's "2016-08-29 00:41:13" is Pacific time (Yelp's own zone). */
function yelpTime(text: string | null | undefined): string | null {
  if (!text) return null;
  const dt = DateTime.fromFormat(text, 'yyyy-MM-dd HH:mm:ss', { zone: 'America/Los_Angeles' });
  return dt.isValid ? formatInstant(dt.toJSDate()) : null;
}

/** Business Details + Reviews JSON → ReviewSource. URLs are passed through unmodified (Yelp terms). */
export function normalizeYelp(business: unknown, reviewsBody: unknown, pageUrl: string, fetchedAt: Date): ReviewSource | null {
  const b = yelpBusiness.safeParse(business);
  if (!b.success) return null;
  const rating = average(b.data.rating);
  const total = count(b.data.review_count);
  if (rating === null || total === null) return null;
  const r = yelpReviews.safeParse(reviewsBody ?? {});
  const reviews: Review[] = [];
  for (const item of r.success ? (r.data.reviews ?? []) : []) {
    const stars_ = stars(item.rating);
    if (stars_ === null) continue;
    reviews.push({
      author: item.user?.name?.trim() || 'Yelp user',
      authorPhotoUrl: httpsUrl(item.user?.image_url),
      authorUrl: typeof item.user?.profile_url === 'string' && httpsUrl(item.user.profile_url) ? item.user.profile_url : null,
      rating: stars_,
      text: (item.text ?? '').trim(),
      relativeTime: null,
      publishedAt: yelpTime(item.time_created),
      url: typeof item.url === 'string' && httpsUrl(item.url) ? item.url : null,
    });
  }
  return {
    available: true,
    rating,
    count: total,
    url: typeof b.data.url === 'string' && httpsUrl(b.data.url) ? b.data.url : pageUrl,
    reviews: reviews.slice(0, 7),
    fetchedAt: formatInstant(fetchedAt),
  };
}

async function fetchYelp(deps: Deps, key: string, businessId: string, pageUrl: string, now: Date): Promise<ReviewSource | null> {
  const base = `https://api.yelp.com/v3/businesses/${encodeURIComponent(businessId)}`;
  const init = { headers: { Authorization: `Bearer ${key}`, Accept: 'application/json' }, signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) };
  try {
    const [businessRes, reviewsRes] = await Promise.all([
      deps.fetch(`${base}?locale=en_US`, init),
      deps.fetch(`${base}/reviews?locale=en_US&sort_by=yelp_sort`, init).catch(() => null),
    ]);
    if (!businessRes.ok) {
      deps.log.warn('Yelp business details failed', { status: businessRes.status });
      return null;
    }
    const business: unknown = await businessRes.json();
    // Review excerpts need Yelp's Enhanced or Premium plan; without them, show rating and count only.
    let reviewsBody: unknown = null;
    if (reviewsRes?.ok) reviewsBody = await reviewsRes.json().catch(() => null);
    else if (reviewsRes) deps.log.warn('Yelp reviews failed', { status: reviewsRes.status });
    return normalizeYelp(business, reviewsBody, pageUrl, now);
  } catch (error) {
    deps.log.warn('Yelp request failed', { error: error instanceof Error ? error.message : String(error) });
    return null;
  }
}

export async function yelpReviewsSource(deps: Deps): Promise<ReviewSource> {
  const { yelpApiKey: key, yelpBusinessId: businessId } = deps.config;
  const pageUrl = yelpPageUrl(businessId);
  if (!key) return unavailable(pageUrl);
  const now = deps.now();
  const expired = new Date(now.getTime() - YELP_MAX_AGE_MS);
  try {
    // Never keep Yelp content past 24 hours, whoever asks first.
    await deps.db.query('DELETE FROM yelp_cache WHERE fetched_at <= $1', [expired]);
    const { rows } = await deps.db.query<{ payload: ReviewSource; fetched_at: Date }>(
      'SELECT payload, fetched_at FROM yelp_cache WHERE business_id = $1',
      [businessId],
    );
    const cached = rows[0];
    const age = cached ? now.getTime() - cached.fetched_at.getTime() : Infinity;
    if (cached && age >= 0 && age < YELP_REFRESH_MS) return cached.payload;

    const fresh = await fetchYelp(deps, key, businessId, pageUrl, now);
    if (fresh) {
      await deps.db.query(
        `INSERT INTO yelp_cache (business_id, payload, fetched_at) VALUES ($1, $2, $3)
         ON CONFLICT (business_id) DO UPDATE SET payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at`,
        [businessId, JSON.stringify(fresh), now],
      );
      return fresh;
    }
    // Yelp is down: a copy younger than 24 hours is still allowed.
    if (cached && age >= 0 && age < YELP_MAX_AGE_MS) return cached.payload;
    return unavailable(pageUrl);
  } catch (error) {
    deps.log.warn('Yelp cache failed', { error: error instanceof Error ? error.message : String(error) });
    return unavailable(pageUrl);
  }
}

export async function getReviews({ deps }: Context): Promise<Response> {
  const [google, yelp] = await Promise.all([googleReviews(deps), yelpReviewsSource(deps)]);
  return json({ google, yelp });
}
