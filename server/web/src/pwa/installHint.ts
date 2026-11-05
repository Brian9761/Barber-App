import { readJSON, removeKey, writeJSON } from '../lib/storage';
import type { Device } from './platform';

// The small bar on phones: "Add Izzy Clipz to your Home Screen · How". It appears after the
// first booking, or from the second visit; never in the app itself; and once someone closes
// it, it stays closed (this browser remembers).

export const INSTALL_HINT_KEY = 'izzy.installHint.v1';
/** How many visits this browser has made. */
export const VISITS_KEY = 'izzy.visits.v1';
/** This tab's visit is counted (a visit lasts until the tab closes). */
const VISIT_COUNTED_KEY = 'izzy.visitCounted.v1';

/** Counts this visit, once however many pages it opens, and says how many there have been. */
export function countVisit(): number {
  const stored = readJSON('local', VISITS_KEY);
  const before = typeof stored === 'number' && Number.isInteger(stored) && stored > 0 ? stored : 0;
  if (readJSON('session', VISIT_COUNTED_KEY) === true) return before;
  // Without this tab's storage every page would count as a visit, so nothing is counted then.
  if (!writeJSON('session', VISIT_COUNTED_KEY, true)) return before;
  writeJSON('local', VISITS_KEY, before + 1);
  return before + 1;
}

export function hintDismissed(): boolean {
  const stored = readJSON('local', INSTALL_HINT_KEY);
  return typeof stored === 'object' && stored !== null && (stored as { dismissed?: unknown }).dismissed === true;
}

export function dismissHint(now: Date = new Date()): void {
  writeJSON('local', INSTALL_HINT_KEY, { dismissed: true, at: now.toISOString() });
}

/** The browser installed it (Chrome or Edge said so): the bar has done its job, for good. */
export function hintInstalled(now: Date = new Date()): void {
  writeJSON('local', INSTALL_HINT_KEY, { dismissed: true, installed: true, at: now.toISOString() });
}

export interface HintFacts {
  device: Device;
  standalone: boolean;
  dismissed: boolean;
  visits: number;
  /** Something was booked on this browser. */
  booked: boolean;
  pathname: string;
}

/**
 * On phones only, never in the app itself or once closed; after the first booking or from the
 * second visit. Not on Get the app (it's all about that), and not in the middle of booking
 * (once booked, "You're booked" is a good moment).
 */
export function showInstallHint(facts: HintFacts): boolean {
  if (facts.device === 'computer' || facts.standalone || facts.dismissed) return false;
  if (facts.pathname === '/app' || (facts.pathname.startsWith('/book') && facts.pathname !== '/book/confirmed')) return false;
  return facts.booked || facts.visits >= 2;
}

/** The demo's "Forget me": the bar's count of visits and whether it was closed go too (lib/storage.ts keeps the rest). */
export function forgetInstallHint(): void {
  removeKey('local', INSTALL_HINT_KEY);
  removeKey('local', VISITS_KEY);
  removeKey('session', VISIT_COUNTED_KEY);
}
