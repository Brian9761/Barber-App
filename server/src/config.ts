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
  /** Used only when STRIPE_CONNECT is off: in connect mode each connected account gets its own location. */
  stripeTerminalLocationId: string | undefined;
  stripeWebhookSecret: string | undefined;
  /**
   * STRIPE_CONNECT=on: the key is the app developer's Connect platform, and the shop connects its
   * own Stripe account from Settings. Off (unset): the key is the shop's own account, as before.
   */
  stripeConnect: boolean;
  /** The signing secret of the platform's Connect webhook endpoint (events on connected accounts). */
  stripeConnectWebhookSecret: string | undefined;
  /**
   * The API's own public address, e.g. https://izzy-clipz-api.vercel.app, for the
   * https pages Stripe Checkout returns to. Unset: the address the request came in on.
   * Required in connect mode, for the pages Stripe's onboarding returns to.
   */
  publicBaseUrl: string | undefined;
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

/**
 * STRIPE_CONNECT: "on" turns connect mode on. Unset or empty, or a word for off ("off", "false",
 * "0", "no", "none", "disabled", "direct"), leaves it off. Any other value counts as on: a typo
 * must never treat the developer's platform key as the shop's own (the shop's card payments
 * would land in the developer's account), while connect mode only waits until the shop connects.
 */
export function connectSwitch(raw: string | undefined): boolean {
  if (raw === undefined) return false;
  return !['off', 'false', '0', 'no', 'none', 'disabled', 'direct'].includes(raw.toLowerCase());
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
    stripeConnect: connectSwitch(value(env, 'STRIPE_CONNECT')),
    stripeConnectWebhookSecret: value(env, 'STRIPE_CONNECT_WEBHOOK_SECRET'),
    publicBaseUrl: value(env, 'PUBLIC_BASE_URL'),
  };
}
