// Settings → No-show protection, with the owner app's rules and words
// (IzzyClipzBusiness/Stores/NoShowSettingsStore.swift and the Kit's NoShowRule, which
// mirror server/src/noshow.ts): on or off, the fee (a share of the service or a flat
// amount), late cancellations and their window, an example, the notice and policy clients
// see, and Stripe's costs. Changes stay on screen until Save, which sends only what changed.

import type { Catalog } from '../../api/types';
import { money, windowLabel } from '../../lib/format';
import type { NoShowSettings, StripeConnection } from '../types';
import { editableMoney, parseMoney } from './money';

export const PERCENT_MIN = 1;
export const PERCENT_MAX = 100;
/** The stepper's range and step for "% of the service". */
export const STEPPER_MIN = 10;
export const PERCENT_STEP = 5;
export const FLAT_MIN = 50;
export const FLAT_MAX = 50_000;
export const WINDOW_MIN = 30;
export const WINDOW_MAX = 2_880;
/** Stripe's smallest US card charge: a smaller fee means no fee. */
export const MIN_FEE_CENTS = 50;
export const WINDOW_CHOICES = [30, 60, 120, 180, 240, 360, 720, 1_440, 2_880];

export const DEFAULT_SETTINGS: NoShowSettings = {
  enabled: false,
  feeMode: 'percent',
  percent: 100,
  flatCents: 2000,
  lateCancelEnabled: true,
  lateCancelWindowMinutes: 60,
};

/** The screen's fields as they're edited. */
export interface NoShowDraft {
  enabled: boolean;
  feeMode: 'percent' | 'flat';
  percent: number;
  /** The flat fee as typed: "20", "17.50". */
  flatText: string;
  lateCancelEnabled: boolean;
  lateCancelWindowMinutes: number;
}

export function draftFrom(settings: NoShowSettings): NoShowDraft {
  return {
    enabled: settings.enabled,
    feeMode: settings.feeMode,
    percent: settings.percent,
    flatText: editableMoney(settings.flatCents),
    lateCancelEnabled: settings.lateCancelEnabled,
    lateCancelWindowMinutes: settings.lateCancelWindowMinutes,
  };
}

/** What the server would turn down, in its words; null when it can be saved. A flat amount only counts in flat mode. */
export function draftProblem(draft: NoShowDraft): string | null {
  if (!Number.isInteger(draft.percent) || draft.percent < PERCENT_MIN || draft.percent > PERCENT_MAX) return 'Pick a percentage from 1% to 100%.';
  if (draft.feeMode === 'flat') {
    const cents = parseMoney(draft.flatText);
    if (cents === null) return 'Enter the flat fee in dollars, like 20 or 17.50.';
    if (cents < FLAT_MIN || cents > FLAT_MAX) return `Pick a flat fee from ${money(FLAT_MIN)} to ${money(FLAT_MAX)}.`;
  }
  if (draft.lateCancelWindowMinutes < WINDOW_MIN || draft.lateCancelWindowMinutes > WINDOW_MAX)
    return 'Pick a late-cancellation window from 30 minutes to 48 hours.';
  return null;
}

/** The settings the draft makes over what's saved, or null while there's a problem. */
export function draftSettings(draft: NoShowDraft, saved: NoShowSettings): NoShowSettings | null {
  if (draftProblem(draft)) return null;
  const flat = parseMoney(draft.flatText);
  return {
    enabled: draft.enabled,
    feeMode: draft.feeMode,
    percent: draft.percent,
    flatCents: flat !== null && flat >= FLAT_MIN && flat <= FLAT_MAX ? flat : saved.flatCents,
    lateCancelEnabled: draft.lateCancelEnabled,
    lateCancelWindowMinutes: draft.lateCancelWindowMinutes,
  };
}

/** Only the fields the owner changed, for PATCH /api/owner/no-show-settings; empty when nothing changed. */
export function draftChanges(draft: NoShowDraft, saved: NoShowSettings): Partial<NoShowSettings> {
  const next = draftSettings(draft, saved);
  if (!next) return {};
  const changes: Partial<NoShowSettings> = {};
  for (const key of Object.keys(next) as (keyof NoShowSettings)[]) {
    if (next[key] !== saved[key]) (changes as Record<string, unknown>)[key] = next[key];
  }
  return changes;
}

export function hasChanges(draft: NoShowDraft, saved: NoShowSettings): boolean {
  if (draftProblem(draft)) return true;
  return Object.keys(draftChanges(draft, saved)).length > 0;
}

/** The stepper's +: the next step up (10, 15, … 100). */
export function increasePercent(percent: number): number {
  return Math.min(PERCENT_MAX, Math.max(STEPPER_MIN, (Math.floor(percent / PERCENT_STEP) + 1) * PERCENT_STEP));
}

/** The stepper's −: the next step down, never under 10%. */
export function decreasePercent(percent: number): number {
  return Math.max(STEPPER_MIN, Math.floor((percent - 1) / PERCENT_STEP) * PERCENT_STEP);
}

/** "100% of the service (the full price)", "50% of the service". */
export function percentLabel(percent: number): string {
  return percent === 100 ? '100% of the service (the full price)' : `${percent}% of the service`;
}

export const ON_FOOTER =
  'Clients add a card (or Apple Pay) when they book online. Nothing is charged then: you decide whether to charge a no-show or a late cancellation.';
export const OFF_FOOTER = "Off: new online bookings don't need a card. Bookings already made with a card keep their fee, and you can still charge it.";
export const FEE_FOOTER =
  'The same fee for a no-show and a late cancellation. Each booking keeps the fee and late-cancellation window it was booked with, so a change only affects new bookings.';

export function lateCancellationFooter(draft: NoShowDraft): string {
  if (!draft.lateCancelEnabled) {
    return 'Off: new bookings can be cancelled in the app for free until the start, and only no-shows can be charged. Bookings already made keep the window they were booked with.';
  }
  const window = windowLabel(draft.lateCancelWindowMinutes);
  return `A client who cancels in the app less than ${window} before the start can be charged the fee. Cancelling earlier is free, and there's never a fee when the shop cancels.`;
}

/** The windows to pick from, with the one on screen among them. */
export function windowChoices(current: number): number[] {
  return WINDOW_CHOICES.includes(current) ? WINDOW_CHOICES : [...WINDOW_CHOICES, current].sort((a, b) => a - b);
}

// --------------------------------------------------------------- The fee rule

/** The fee in cents for an item priced `priceCents`, or null: no fee for items included with a cut, free ones, or under 50¢. */
export function feeCents(priceCents: number, includedWithCut: boolean, settings: NoShowSettings): number | null {
  if (includedWithCut || priceCents <= 0) return null;
  const fee = settings.feeMode === 'flat' ? settings.flatCents : Math.floor((priceCents * settings.percent + 50) / 100);
  return fee >= MIN_FEE_CENTS ? fee : null;
}

/** "$20", or "$17.50–$22.50". */
export function feeRangeLabel(minCents: number, maxCents: number): string {
  return minCents === maxCents ? money(minCents) : `${money(minCents)}–${money(maxCents)}`;
}

/** The policy clients agree to, as the server words it. */
export function policyText(minCents: number, maxCents: number, settings: NoShowSettings): string {
  const share = settings.feeMode === 'percent' ? ` (${settings.percent}% of the service)` : '';
  const fee = feeRangeLabel(minCents, maxCents) + share;
  if (settings.lateCancelEnabled) {
    const window = windowLabel(settings.lateCancelWindowMinutes);
    return `No payment now. If you cancel less than ${window} before your appointment, or don't come, Izzy Clipz may charge ${fee} to this card. Cancelling in the app more than ${window} before is free.`;
  }
  return `No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge ${fee} to this card. Cancelling in the app before your appointment is free.`;
}

/** The notice clients see while booking, as the server words it. */
export function clientNotice(minCents: number, maxCents: number, settings: NoShowSettings): { title: string; message: string } {
  const fee = feeRangeLabel(minCents, maxCents);
  const fullPrice = settings.feeMode === 'percent' && settings.percent === 100;
  const amount = fullPrice ? `the full service price (${fee})` : settings.feeMode === 'percent' ? `${fee} (${settings.percent}% of the service)` : fee;
  if (settings.lateCancelEnabled) {
    const window = windowLabel(settings.lateCancelWindowMinutes);
    return {
      title: fullPrice ? 'Full Service Cancellation & No-Show Fee' : 'Late Cancellation & No-Show Fee',
      message: `Cancelling less than ${window} before your appointment, or not showing up, is charged ${amount}. Cancelling in the app more than ${window} before is free.`,
    };
  }
  return { title: 'No-Show Fee', message: `Not showing up is charged ${amount}. Cancelling in the app before your appointment is free.` };
}

/** "A" or "An", as "$8", "$11", "$18" and "$80" are said. */
export function article(dollars: number): string {
  const vowel = dollars === 8 || dollars === 11 || dollars === 18 || (dollars >= 80 && dollars <= 89) || (dollars >= 800 && dollars <= 899);
  return vowel ? 'An' : 'A';
}

/** The example items: the first barber's haircut, and the cheapest item with a price. */
export function exampleItems(catalog: Catalog): { name: string; priceCents: number }[] {
  const nameOf = (id: string) => catalog.services.find((s) => s.id === id)?.name ?? id;
  const items: { name: string; priceCents: number }[] = [];
  const haircut = catalog.offerings.find((o) => o.serviceId === 'haircut' && o.priceKind === 'fixed' && o.priceCents > 0);
  if (haircut) items.push({ name: nameOf(haircut.serviceId), priceCents: haircut.priceCents });
  const priced = catalog.offerings.filter((o) => o.priceKind === 'fixed' && o.priceCents > 0);
  const cheapest = priced.reduce<(typeof priced)[number] | null>((low, o) => (low === null || o.priceCents < low.priceCents ? o : low), null);
  if (cheapest && !items.some((i) => i.priceCents === cheapest.priceCents)) items.push({ name: nameOf(cheapest.serviceId), priceCents: cheapest.priceCents });
  return items;
}

/** "A $40 haircut: $40", "A $16 seniors haircut: $16". */
export function examples(settings: NoShowSettings | null, catalog: Catalog): string[] {
  if (!settings) return [];
  return exampleItems(catalog).map((item) => {
    const fee = feeCents(item.priceCents, false, settings);
    return `${article(Math.floor(item.priceCents / 100))} ${money(item.priceCents)} ${item.name.toLowerCase()}: ${fee !== null ? money(fee) : 'no fee (it would be under $0.50)'}`;
  });
}

/** The example haircut's fee, if it has one. */
export function exampleFee(settings: NoShowSettings | null, catalog: Catalog): number | null {
  const item = exampleItems(catalog)[0];
  if (!settings || !item) return null;
  return feeCents(item.priceCents, false, settings);
}

/** What Stripe keeps of a fee: its online card rate in the US, 2.9% + 30¢. */
export function stripeCostCents(fee: number): number {
  return Math.floor((fee * 29 + 500) / 1000) + 30;
}

export function costsText(fee: number | null): string {
  let rate = "Each fee is a card payment at Stripe's online rate, 2.9% + 30¢ in the US";
  if (fee !== null) rate += ` (about ${money(stripeCostCents(fee))} of a ${money(fee)} fee)`;
  return `${rate}. If a client disputes a fee, Stripe charges $15, and $15 more if you fight it, which comes back if you win. Refunds are made in the Stripe Dashboard, and Stripe keeps its fee on a refund.`;
}

/** "Off: clients book online without a card", or "On: the full service price for no-shows and cancellations less than 1 hour before". */
export function summary(settings: NoShowSettings): string {
  if (!settings.enabled) return 'Off: clients book online without a card';
  const fee =
    settings.feeMode === 'percent'
      ? settings.percent === 100
        ? 'the full service price'
        : `${settings.percent}% of the service`
      : `${money(settings.flatCents)} flat`;
  const cases = settings.lateCancelEnabled ? `no-shows and cancellations less than ${windowLabel(settings.lateCancelWindowMinutes)} before` : 'no-shows';
  return `On: ${fee} for ${cases}`;
}

/** What Stripe's set-up means for clients, when it changes things: no card is asked for without Stripe, and test keys turn real cards down. */
export function stripeNote(connection: StripeConnection | null, enabled: boolean): string | null {
  if (!connection) return null;
  const ready = connection.status === 'active' || connection.status === 'direct';
  if (!ready) {
    return connection.mode === 'connect'
      ? "Stripe isn't connected yet, so clients aren't asked for a card, even with this on. Connect Stripe above first."
      : "Stripe isn't set up on the server yet, so clients aren't asked for a card, even with this on.";
  }
  if (connection.livemode === false && enabled) {
    return "Stripe is in test mode: its card page turns real cards down, so clients couldn't book online. Turn this on once Stripe is live.";
  }
  return null;
}
