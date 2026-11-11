// The booking flow, the app's five steps: a service, a barber (or "Any barber"),
// a day and time, the client's details, and a review. A pure state machine:
// what's been picked, which steps can be shown, and what each choice resets.
// The booking in progress is kept in this tab's sessionStorage, so a reload or
// a trip to Stripe's card page and back picks up where the client left off.

import type { BookingTarget } from '../api/types';
import { readJSON, removeKey, writeJSON } from '../lib/storage';
import { isToken } from '../lib/tokens';

export const STEPS = ['service', 'barber', 'time', 'details', 'review'] as const;
export type Step = (typeof STEPS)[number];

export const STEP_PATHS: Record<Step, string> = {
  service: '/book',
  barber: '/book/barber',
  time: '/book/time',
  details: '/book/details',
  review: '/book/review',
};

/** "Any barber" (whoever is free first), or one barber's own menu item. */
export type Choice = { kind: 'any' } | { kind: 'offering'; offeringId: string };

export interface Details {
  name: string;
  phone: string;
  email: string;
  note: string;
  remember: boolean;
}

export interface BookingDraft {
  serviceId: string | null;
  /** A barber picked first ("Book with Carlos"): the menu shows their services. */
  barberId: string | null;
  choice: Choice | null;
  /** The slot's start, exactly as the server listed it. */
  start: string | null;
  details: Details | null;
  /** Why the client is back on the times, e.g. "Someone just booked 2:30 PM. Pick another time." */
  notice: string | null;
  /** The manage token made for this exact booking, so trying it again can't book twice. */
  pending: { key: string; token: string } | null;
}

export const EMPTY_DRAFT: BookingDraft = {
  serviceId: null,
  barberId: null,
  choice: null,
  start: null,
  details: null,
  notice: null,
  pending: null,
};

/** Nothing picked or typed yet (or any more, once booked). */
export function isEmptyDraft(draft: BookingDraft): boolean {
  return Object.values(draft).every((value) => value === null);
}

export function stepNumber(step: Step): number {
  return STEPS.indexOf(step) + 1;
}

export function previousStep(step: Step): Step | null {
  return STEPS[STEPS.indexOf(step) - 1] ?? null;
}

export function nextStep(step: Step): Step | null {
  return STEPS[STEPS.indexOf(step) + 1] ?? null;
}

/** Whether a step's own choice has been made. */
export function isComplete(step: Step, draft: BookingDraft): boolean {
  switch (step) {
    case 'service':
      return draft.serviceId !== null;
    case 'barber':
      return draft.choice !== null;
    case 'time':
      return draft.start !== null;
    case 'details':
      return draft.details !== null;
    case 'review':
      return false;
  }
}

/** A step can be shown once every step before it is done. */
export function canVisit(step: Step, draft: BookingDraft): boolean {
  return STEPS.slice(0, STEPS.indexOf(step)).every((s) => isComplete(s, draft));
}

/** Where the client has got to: the first step not done yet. */
export function firstOpenStep(draft: BookingDraft): Step {
  return STEPS.find((s) => !isComplete(s, draft)) ?? 'review';
}

/** The barber of a menu item: offering ids are "<barber id>/<menu item id>". */
export function barberOfOffering(offeringId: string): string {
  return offeringId.split('/')[0] ?? '';
}

export function sameChoice(a: Choice | null, b: Choice | null): boolean {
  if (!a || !b) return a === b;
  if (a.kind === 'any' || b.kind === 'any') return a.kind === b.kind;
  return a.offeringId === b.offeringId;
}

/** What the server books. */
export function targetOf(draft: Pick<BookingDraft, 'serviceId' | 'choice'>): BookingTarget | null {
  if (!draft.choice) return null;
  if (draft.choice.kind === 'offering') return { offeringId: draft.choice.offeringId };
  return draft.serviceId ? { serviceId: draft.serviceId, barberId: 'any' } : null;
}

/**
 * What tells a retry of a booking from a new one: exactly what the server compares
 * when the same manage token comes back (the target asked for the same way, the
 * start and the number in E.164; not the name, email or note), like the app's
 * `NewAppointment.retryKey`.
 */
export function retryKey(target: BookingTarget, start: string, phoneE164: string): string {
  const fields = 'offeringId' in target ? `offeringId=${target.offeringId}` : `serviceId=${target.serviceId}&barberId=any`;
  return `${fields}|${start}|${phoneE164}`;
}

export type BookingAction =
  /** A new booking, maybe with a service or barber picked on another page (/book?service=… or ?barber=…). */
  | { type: 'begin'; serviceId?: string | null; barberId?: string | null }
  /** Step 1. `choice` too when the barber was picked first and has one version of the service. */
  | { type: 'chooseService'; serviceId: string; choice?: Choice }
  | { type: 'chooseBarber'; choice: Choice }
  | { type: 'chooseTime'; start: string }
  | { type: 'saveDetails'; details: Details }
  /** The picked time was taken (or can't be booked any more): back to the times, saying so. */
  | { type: 'timeGone'; message: string }
  | { type: 'clearNotice' }
  /** Not with the barber picked first after all: every service, every barber. */
  | { type: 'clearBarber' }
  /** The token for this booking, made the first time it's sent. */
  | { type: 'pending'; key: string; token: string }
  /** "Not you? Forget me on this computer": no details typed for this booking any more. */
  | { type: 'forgetDetails' }
  /** The draft kept in this tab, after a reload or the trip to Stripe's card page. */
  | { type: 'restore'; draft: BookingDraft }
  /** Booked: the next booking starts fresh. */
  | { type: 'booked' };

export function bookingReducer(draft: BookingDraft, action: BookingAction): BookingDraft {
  switch (action.type) {
    case 'begin':
      // A new booking starts with nothing typed, like the app: the details step fills in the
      // name and number this computer remembers (when the client asked), never a note, and
      // nothing at all from someone who didn't ask to be remembered.
      return { ...EMPTY_DRAFT, serviceId: action.serviceId ?? null, barberId: action.barberId ?? null };
    case 'chooseService': {
      const changed = action.serviceId !== draft.serviceId;
      const choice = action.choice ?? (changed ? null : draft.choice);
      const keepsTime = !changed && sameChoice(choice, draft.choice);
      return {
        ...draft,
        serviceId: action.serviceId,
        choice,
        start: keepsTime ? draft.start : null,
        notice: keepsTime ? draft.notice : null,
        pending: keepsTime ? draft.pending : null,
      };
    }
    case 'chooseBarber': {
      if (sameChoice(action.choice, draft.choice)) return draft;
      return { ...draft, choice: action.choice, start: null, notice: null, pending: null };
    }
    case 'chooseTime':
      return { ...draft, start: action.start, notice: null };
    case 'saveDetails':
      return { ...draft, details: action.details };
    case 'timeGone':
      return { ...draft, start: null, notice: action.message, pending: null };
    case 'clearNotice':
      return draft.notice === null ? draft : { ...draft, notice: null };
    case 'clearBarber':
      return { ...draft, barberId: null };
    case 'pending':
      return { ...draft, pending: { key: action.key, token: action.token } };
    case 'forgetDetails':
      return draft.details === null ? draft : { ...draft, details: null };
    case 'restore':
      return action.draft;
    case 'booked':
      // The details go too: "Book another" fills in only what "Remember me" kept.
      return EMPTY_DRAFT;
  }
}

// ---------------------------------------------------------------- Persistence

export const DRAFT_KEY = 'izzy.booking.v1';

function isChoice(value: unknown): value is Choice {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return v.kind === 'any' || (v.kind === 'offering' && typeof v.offeringId === 'string');
}

function isDetails(value: unknown): value is Details {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.name === 'string' &&
    typeof v.phone === 'string' &&
    typeof v.email === 'string' &&
    typeof v.note === 'string' &&
    typeof v.remember === 'boolean'
  );
}

const nullOr = <T>(value: unknown, check: (v: unknown) => v is T): value is T | null => value === null || check(value);
const isString = (v: unknown): v is string => typeof v === 'string';

/** Reads a stored draft, or null when there's none (or it isn't one). */
export function parseDraft(value: unknown): BookingDraft | null {
  if (typeof value !== 'object' || value === null) return null;
  const v = value as Record<string, unknown>;
  const pending = v.pending as Record<string, unknown> | null | undefined;
  const pendingOk = pending === null || (typeof pending === 'object' && pending !== undefined && isString(pending.key) && isToken(pending.token));
  if (
    !nullOr(v.serviceId, isString) ||
    !nullOr(v.barberId, isString) ||
    !nullOr(v.choice, isChoice) ||
    !nullOr(v.start, isString) ||
    !nullOr(v.details, isDetails) ||
    !nullOr(v.notice, isString) ||
    !pendingOk
  ) {
    return null;
  }
  return {
    serviceId: v.serviceId,
    barberId: v.barberId,
    choice: v.choice,
    start: v.start,
    details: v.details,
    notice: v.notice,
    pending: pending ? { key: pending.key as string, token: pending.token as string } : null,
  };
}

export function loadDraft(): BookingDraft | null {
  return parseDraft(readJSON('session', DRAFT_KEY));
}

/** False when this browser can't keep it (storage off or full). */
export function saveDraft(draft: BookingDraft): boolean {
  return writeJSON('session', DRAFT_KEY, draft);
}

export function clearDraft(): void {
  removeKey('session', DRAFT_KEY);
}
