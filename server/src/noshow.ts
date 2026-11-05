import { z } from 'zod';
import { requireOwner } from './auth.js';
import { resolveTarget, targetOfferings, type Target } from './booking.js';
import type { Offering } from './catalog.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { LATE_CANCEL_GRACE_MINUTES, MAX_LATE_CANCEL_WINDOW_MINUTES, MIN_LATE_CANCEL_WINDOW_MINUTES, money, windowLabel } from './feecase.js';
import { json, readJsonObject } from './http.js';
import type { Context } from './router.js';
import { shopAccount } from './stripeaccount.js';
import { parse, shortId } from './validation.js';

// No-show protection: the owner's settings, the fee rule, the policy clients
// agree to and the warning they see while booking. Everything about how much a
// no-show or a late cancellation costs is decided here, in one place (which
// booking can be charged is in feecase.ts); the Kit mirrors the rule only for the
// owner app's preview, and its tests check it against
// test/fixtures/no-show-rule.json, which this server's tests write.

export type FeeMode = 'percent' | 'flat';

export interface NoShowSettings {
  /**
   * Whether online bookings need a card (only while Stripe is set up, too). Off until the
   * owner turns it on: setting STRIPE_SECRET_KEY alone never changes how clients book.
   */
  enabled: boolean;
  feeMode: FeeMode;
  /** Used in percent mode: 1–100 % of the booked service's price. */
  percent: number;
  /** Used in flat mode: 50¢ to $500. */
  flatCents: number;
  /**
   * Whether a client who cancels less than `lateCancelWindowMinutes` before the start may be
   * charged the same fee as a no-show. Off: cancelling in the app before the start is free.
   */
  lateCancelEnabled: boolean;
  /** How long before the start cancelling stops being free: 30 minutes to 48 hours. */
  lateCancelWindowMinutes: number;
}

/**
 * Before the owner saves anything: protection off; once it's on, the full service price (100%;
 * $20 ready for flat mode) for a no-show or a cancellation less than 1 hour before the start.
 * Off by default because the shop may set a test key to try Tap to Pay while real clients
 * book: Stripe's test-mode card page turns real cards down, so they couldn't book online at
 * all. The owner turns it on when the apps with the card screen are out.
 */
export const DEFAULT_NO_SHOW_SETTINGS: NoShowSettings = {
  enabled: false,
  feeMode: 'percent',
  percent: 100,
  flatCents: 2000,
  lateCancelEnabled: true,
  lateCancelWindowMinutes: 60,
};

/** Stripe's smallest US card charge. A fee below it means the booking isn't protected. */
export const MIN_NO_SHOW_FEE_CENTS = 50;
export const MIN_PERCENT = 1;
export const MAX_PERCENT = 100;
export const MIN_FLAT_CENTS = 50;
export const MAX_FLAT_CENTS = 50_000;

const SETTINGS_KEY = 'no_show';

export { money };

/**
 * The no-show fee for one menu item, in cents, or null when no fee applies: items
 * included with a cut, free items, and fees under 50¢. Percent mode rounds half
 * up to the cent; flat mode is the flat amount. Either way the fee is never more
 * than the booked service's price (a $20 flat fee on a $5 service is $5): the
 * agreed estimate of the shop's loss can't be more than what the time would have
 * earned. (Whether protection is on, and whether Stripe is set up, is decided by
 * the caller.)
 */
export function noShowFeeCents(item: Pick<Offering, 'priceCents' | 'priceKind'>, settings: NoShowSettings): number | null {
  if (item.priceKind === 'includedWithCut' || item.priceCents <= 0) return null;
  const fee =
    settings.feeMode === 'flat' ? Math.min(settings.flatCents, item.priceCents) : Math.floor((item.priceCents * settings.percent + 50) / 100);
  return fee >= MIN_NO_SHOW_FEE_CENTS ? fee : null;
}

/** "$20" or "$17.50–$22.50". */
export function feeRangeLabel(minCents: number, maxCents: number): string {
  return minCents === maxCents ? money(minCents) : `${money(minCents)}–${money(maxCents)}`;
}

/**
 * The policy clients agree to before booking (also shown on Stripe's card page), with the fee
 * for this booking. It's stored with the booking as the client's consent, so it says exactly
 * when the card may be charged.
 */
export function policyText(minCents: number, maxCents: number, settings: NoShowSettings): string {
  const share = settings.feeMode === 'percent' ? ` (${settings.percent}% of the service)` : '';
  const fee = `${feeRangeLabel(minCents, maxCents)}${share}`;
  if (settings.lateCancelEnabled) {
    const window = windowLabel(settings.lateCancelWindowMinutes);
    return (
      `No payment now. If you cancel less than ${window} before your appointment, or don't come, Izzy Clipz may charge ${fee} to this card. ` +
      `Cancelling in the app more than ${window} before is free.`
    );
  }
  return `No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge ${fee} to this card. Cancelling in the app before your appointment is free.`;
}

/** The notice clients see on "Pick a day and time" and on Review: a title and one or two sentences. */
export interface FeeWarning {
  title: string;
  message: string;
}

/**
 * "Full Service Cancellation & No-Show Fee": "Cancelling less than 1 hour before your
 * appointment, or not showing up, may be charged the full service price ($40). Cancelling in the
 * app more than 1 hour before is free." The title says "Full Service" only when the fee is
 * 100% of the service; with late cancellations off, it's only about no-shows. "May be charged",
 * like the agreed policy's "may charge": the shop decides each time.
 */
export function feeWarning(minCents: number, maxCents: number, settings: NoShowSettings): FeeWarning {
  const fee = feeRangeLabel(minCents, maxCents);
  const fullPrice = settings.feeMode === 'percent' && settings.percent === 100;
  const amount = fullPrice
    ? `the full service price (${fee})`
    : settings.feeMode === 'percent'
      ? `${fee} (${settings.percent}% of the service)`
      : fee;
  if (settings.lateCancelEnabled) {
    const window = windowLabel(settings.lateCancelWindowMinutes);
    return {
      title: fullPrice ? 'Full Service Cancellation & No-Show Fee' : 'Late Cancellation & No-Show Fee',
      message: `Cancelling less than ${window} before your appointment, or not showing up, may be charged ${amount}. Cancelling in the app more than ${window} before is free.`,
    };
  }
  return {
    title: 'No-Show Fee',
    message: `Not showing up may be charged ${amount}. Cancelling in the app before your appointment is free.`,
  };
}

/**
 * The line the apps and the website add under the warning for a time that's already inside the
 * late-cancellation window when it's picked (bookings open 30 minutes ahead, and the window can be
 * longer): "This time is less than 1 hour away, so cancelling it more than 15 minutes after
 * booking may be charged $35." Cancelling within 15 minutes of booking is free (the grace period,
 * feecase.ts). The server doesn't show it itself: it's written to test/fixtures/no-show-rule.json,
 * so the Kit and the website word it exactly the same.
 */
export function lateCancelNotice(windowMinutes: number, feeLabel: string): string {
  return (
    `This time is less than ${windowLabel(windowMinutes)} away, so cancelling it more than ` +
    `${LATE_CANCEL_GRACE_MINUTES} minutes after booking may be charged ${feeLabel}.`
  );
}

export interface NoShowPolicy {
  /** A card is needed to book this. */
  required: boolean;
  minFeeCents: number | null;
  maxFeeCents: number | null;
  /** What the client agrees to; the booking sends it back exactly (field noShowPolicy). */
  policyText: string | null;
  /** Cancelling less than this many minutes before the start may be charged; null: cancelling is free. */
  lateCancelWindowMinutes: number | null;
  /** The notice to show while picking a time and on Review. */
  warning: FeeWarning | null;
}

const NOT_REQUIRED: NoShowPolicy = {
  required: false,
  minFeeCents: null,
  maxFeeCents: null,
  policyText: null,
  lateCancelWindowMinutes: null,
  warning: null,
};

export interface TargetProtection {
  policy: NoShowPolicy;
  /** The fee for each offering the booking may get, by offering id (null: no fee for that one). */
  fees: Map<string, number | null>;
}

/**
 * Whether a booking for `target` needs a card, and for how much. "Any barber"
 * may land with any of its barbers, so the policy shows the range of their fees.
 */
export function protectionFor(target: Target, settings: NoShowSettings, stripeConfigured: boolean): TargetProtection {
  const fees = new Map<string, number | null>();
  const active = stripeConfigured && settings.enabled;
  for (const offering of targetOfferings(target)) fees.set(offering.id, active ? noShowFeeCents(offering, settings) : null);
  const charged = [...fees.values()].filter((fee): fee is number => fee !== null);
  if (charged.length === 0) return { policy: { ...NOT_REQUIRED }, fees };
  const min = Math.min(...charged);
  const max = Math.max(...charged);
  return {
    policy: {
      required: true,
      minFeeCents: min,
      maxFeeCents: max,
      policyText: policyText(min, max, settings),
      lateCancelWindowMinutes: settings.lateCancelEnabled ? settings.lateCancelWindowMinutes : null,
      warning: feeWarning(min, max, settings),
    },
    fees,
  };
}

// Settings storage: one JSON object under settings.key = 'no_show', merged over the defaults.

const WINDOW_MESSAGE = `Pick a late-cancellation window from ${windowLabel(MIN_LATE_CANCEL_WINDOW_MINUTES)} to ${windowLabel(MAX_LATE_CANCEL_WINDOW_MINUTES)}.`;

const settingsShape = z.object({
  enabled: z.boolean({ error: 'enabled must be true or false.' }),
  feeMode: z.enum(['percent', 'flat'], { error: 'feeMode must be percent or flat.' }),
  percent: z
    .number({ error: `Pick a percentage from ${MIN_PERCENT}% to ${MAX_PERCENT}%.` })
    .int({ error: `Pick a whole percentage from ${MIN_PERCENT}% to ${MAX_PERCENT}%.` })
    .min(MIN_PERCENT, { error: `Pick a percentage from ${MIN_PERCENT}% to ${MAX_PERCENT}%.` })
    .max(MAX_PERCENT, { error: `Pick a percentage from ${MIN_PERCENT}% to ${MAX_PERCENT}%.` }),
  flatCents: z
    .number({ error: `Pick a flat fee from ${money(MIN_FLAT_CENTS)} to ${money(MAX_FLAT_CENTS)}.` })
    .int({ error: 'The flat fee must be a whole number of cents.' })
    .min(MIN_FLAT_CENTS, { error: `Pick a flat fee from ${money(MIN_FLAT_CENTS)} to ${money(MAX_FLAT_CENTS)}.` })
    .max(MAX_FLAT_CENTS, { error: `Pick a flat fee from ${money(MIN_FLAT_CENTS)} to ${money(MAX_FLAT_CENTS)}.` }),
  lateCancelEnabled: z.boolean({ error: 'lateCancelEnabled must be true or false.' }),
  lateCancelWindowMinutes: z
    .number({ error: WINDOW_MESSAGE })
    .int({ error: 'The late-cancellation window must be a whole number of minutes.' })
    .min(MIN_LATE_CANCEL_WINDOW_MINUTES, { error: WINDOW_MESSAGE })
    .max(MAX_LATE_CANCEL_WINDOW_MINUTES, { error: WINDOW_MESSAGE }),
});

export async function loadNoShowSettings(db: Queryable): Promise<NoShowSettings> {
  const { rows } = await db.query<{ value: Record<string, unknown> }>('SELECT value FROM settings WHERE key = $1', [SETTINGS_KEY]);
  const stored = rows[0]?.value ?? {};
  // Each stored field is used only if it's still valid; anything else falls back to its default.
  const settings: NoShowSettings = { ...DEFAULT_NO_SHOW_SETTINGS };
  for (const key of Object.keys(settingsShape.shape) as (keyof NoShowSettings)[]) {
    const field = settingsShape.shape[key].safeParse(stored[key]);
    if (field.success) (settings as unknown as Record<string, unknown>)[key] = field.data;
  }
  return settings;
}

/**
 * Whether a card could be saved and charged: Stripe is set up (the server's own key, or in
 * connect mode a connected account that can take card payments). Until then no booking needs a card.
 */
export async function stripeReady(deps: Pick<Deps, 'config' | 'db'>): Promise<boolean> {
  return (await shopAccount(deps)) !== null;
}

// GET /api/no-show-policy?offeringId=… | serviceId=…&barberId=any

const targetQuery = z.object({
  offeringId: shortId.optional(),
  serviceId: shortId.optional(),
  barberId: shortId.optional(),
});

export async function getNoShowPolicy(ctx: Context): Promise<Response> {
  const query = parse(targetQuery, Object.fromEntries(ctx.url.searchParams));
  const target = resolveTarget(ctx.deps.catalog, query);
  if (!(await stripeReady(ctx.deps))) return json(NOT_REQUIRED);
  const settings = await loadNoShowSettings(ctx.deps.db);
  return json(protectionFor(target, settings, true).policy);
}

// GET /api/owner/no-show-settings and PATCH /api/owner/no-show-settings (partial)

export async function getNoShowSettings(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  return json({ noShowSettings: await loadNoShowSettings(ctx.deps.db) });
}

const settingsPatch = settingsShape.partial().strict();

export async function patchNoShowSettings(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const patch = parse(settingsPatch, await readJsonObject(ctx.request));
  const changes = Object.fromEntries(Object.entries(patch).filter(([, v]) => v !== undefined));
  if (Object.keys(changes).length > 0) {
    // Merged in one statement, so two changes at once (say, the fee and the switch) both stick.
    await ctx.deps.db.query(
      `INSERT INTO settings (key, value, updated_at) VALUES ($1, $2::jsonb, $3)
       ON CONFLICT (key) DO UPDATE SET value = settings.value || EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
      [SETTINGS_KEY, JSON.stringify(changes), ctx.deps.now()],
    );
  }
  return json({ noShowSettings: await loadNoShowSettings(ctx.deps.db) });
}
