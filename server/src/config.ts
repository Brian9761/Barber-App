/** Settings read from the environment. Empty values count as unset. */
export interface Config {
  ownerKey: string | undefined;
  cronSecret: string | undefined;
  googlePlacesApiKey: string | undefined;
  googlePlaceId: string;
  googleDailyLimit: number;
  yelpApiKey: string | undefined;
  yelpBusinessId: string;
  stripeSecretKey: string | undefined;
  stripeTerminalLocationId: string | undefined;
  stripeWebhookSecret: string | undefined;
}

export const DEFAULT_GOOGLE_PLACE_ID = 'ChIJGz5HChRv3IARYJJy_6jyRm8';
export const DEFAULT_YELP_BUSINESS_ID = 'izzy-clipz-barbershop-oceanside';
export const DEFAULT_GOOGLE_DAILY_LIMIT = 30;
/** Owner keys shorter than this are treated as unset, so owner endpoints stay closed. */
export const MIN_OWNER_KEY_LENGTH = 32;

type Env = Record<string, string | undefined>;

function value(env: Env, name: string): string | undefined {
  const raw = env[name]?.trim();
  return raw ? raw : undefined;
}

function nonNegativeInt(raw: string | undefined, fallback: number): number {
  if (raw === undefined || !/^\d+$/.test(raw)) return fallback;
  const n = Number(raw);
  return Number.isSafeInteger(n) ? n : fallback;
}

export function configFromEnv(env: Env = process.env): Config {
  return {
    ownerKey: value(env, 'OWNER_KEY'),
    cronSecret: value(env, 'CRON_SECRET'),
    googlePlacesApiKey: value(env, 'GOOGLE_PLACES_API_KEY'),
    googlePlaceId: value(env, 'GOOGLE_PLACE_ID') ?? DEFAULT_GOOGLE_PLACE_ID,
    googleDailyLimit: nonNegativeInt(value(env, 'GOOGLE_DAILY_LIMIT'), DEFAULT_GOOGLE_DAILY_LIMIT),
    yelpApiKey: value(env, 'YELP_API_KEY'),
    yelpBusinessId: value(env, 'YELP_BUSINESS_ID') ?? DEFAULT_YELP_BUSINESS_ID,
    stripeSecretKey: value(env, 'STRIPE_SECRET_KEY'),
    stripeTerminalLocationId: value(env, 'STRIPE_TERMINAL_LOCATION_ID'),
    stripeWebhookSecret: value(env, 'STRIPE_WEBHOOK_SECRET'),
  };
}
