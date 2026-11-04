import { z } from 'zod';
import { requireOwner } from './auth.js';
import { resolveTarget, targetOfferings, type Target } from './booking.js';
import type { Offering } from './catalog.js';
import type { Queryable } from './db.js';
import type { Config } from './config.js';
import { json, readJsonObject } from './http.js';
import type { Context } from './router.js';
import { parse, shortId } from './validation.js';

// No-show protection: the owner's settings, the fee rule and the policy clients
// agree to. Everything about how much a no-show costs is decided here, in one
// place; the Kit mirrors the rule only for the owner app's preview, and its tests
// check it against test/fixtures/no-show-rule.json, which this server's tests write.

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
}

/**
 * Before the owner saves anything: protection off, and 50% of the service ($20 ready for flat
 * mode) once it's on. Off by default because the shop may set a test key to try Tap to Pay
 * while real clients book: Stripe's test-mode card page turns real cards down, so they
 * couldn't book online at all. The owner turns it on when the app with the card screen is out.
 */
export const DEFAULT_NO_SHOW_SETTINGS: NoShowSettings = { enabled: false, feeMode: 'percent', percent: 50, flatCents: 2000 };

/** Stripe's smallest US card charge. A fee below it means the booking isn't protected. */
export const MIN_NO_SHOW_FEE_CENTS = 50;
export const MIN_PERCENT = 1;
export const MAX_PERCENT = 100;
export const MIN_FLAT_CENTS = 50;
export const MAX_FLAT_CENTS = 50_000;

const SETTINGS_KEY = 'no_show';

/** "$20", "$17.50": like the Kit's `Price.currencyString`. */
export function money(cents: number): string {
  const dollars = Math.floor(cents / 100);
  const rest = cents % 100;
  return rest === 0 ? `$${dollars}` : `$${dollars}.${String(rest).padStart(2, '0')}`;
}

/**
 * The no-show fee for one menu item, in cents, or null when no fee applies: items
 * included with a cut, free items, and fees under 50¢. Percent mode rounds half
 * up to the cent; flat mode is the flat amount. (Whether protection is on, and
 * whether Stripe is set up, is decided by the caller.)
 */
export function noShowFeeCents(item: Pick<Offering, 'priceCents' | 'priceKind'>, settings: NoShowSettings): number | null {
  if (item.priceKind === 'includedWithCut' || item.priceCents <= 0) return null;
  const fee = settings.feeMode === 'flat' ? settings.flatCents : Math.floor((item.priceCents * settings.percent + 50) / 100);
  return fee >= MIN_NO_SHOW_FEE_CENTS ? fee : null;
}

/** "$20" or "$17.50–$22.50". */
export function feeRangeLabel(minCents: number, maxCents: number): string {
  return minCents === maxCents ? money(minCents) : `${money(minCents)}–${money(maxCents)}`;
}

/** The policy clients see before booking (and on Stripe's card page), with the fee for this booking. */
export function policyText(minCents: number, maxCents: number, settings: NoShowSettings): string {
  const share = settings.feeMode === 'percent' ? ` (${settings.percent}% of the service)` : '';
  return (
    `No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge ${feeRangeLabel(minCents, maxCents)}${share} to this card. ` +
    'Cancelling in the app before your appointment is free.'
  );
}

export interface NoShowPolicy {
  /** A card is needed to book this. */
  required: boolean;
  minFeeCents: number | null;
  maxFeeCents: number | null;
  policyText: string | null;
}

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
  if (charged.length === 0) {
    return { policy: { required: false, minFeeCents: null, maxFeeCents: null, policyText: null }, fees };
  }
  const min = Math.min(...charged);
  const max = Math.max(...charged);
  return { policy: { required: true, minFeeCents: min, maxFeeCents: max, policyText: policyText(min, max, settings) }, fees };
}

// Settings storage: one JSON object under settings.key = 'no_show', merged over the defaults.

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

/** Whether Stripe is set up, so a card could be saved and charged. */
export function stripeConfigured(config: Config): boolean {
  return Boolean(config.stripeSecretKey);
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
  if (!stripeConfigured(ctx.deps.config)) return json(protectionFor(target, DEFAULT_NO_SHOW_SETTINGS, false).policy);
  const settings = await loadNoShowSettings(ctx.deps.db);
  return json(protectionFor(target, settings, true).policy);
}

// GET /api/owner/no-show-settings and PATCH /api/owner/no-show-settings (partial)

export async function getNoShowSettings(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  return json({ noShowSettings: await loadNoShowSettings(ctx.deps.db) });
}

const settingsPatch = settingsShape.partial().strict();

export async function patchNoShowSettings(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
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
