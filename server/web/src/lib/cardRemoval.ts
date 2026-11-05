// Deleting a saved card at the shop (DELETE /api/cards), whenever this browser lets go of the
// card's key for good: "Forget me" and "Not you?", right after a booking made without
// "Remember me", and when another card (or another client's) takes its place. The key exists
// only in this browser, so once it's forgotten nobody could use the card again; the shop's
// server deletes it at Stripe now, or as soon as no booking needs it (that's its job).
//
// The key is forgotten here whatever the answer: a network problem never keeps it.

import { api, ErrorCode, isApiError } from '../api/client';
import type { CardDeletion } from '../api/types';

export type CardRemoval =
  /** The shop's answer: deleted now, or once no booking needs it. */
  | CardDeletion
  /** The shop has no card under that key (a 404): there was nothing to delete. */
  | { status: 'none' }
  /** The shop couldn't be reached, or answered with a problem: the client should call. */
  | { status: 'failed' };

/** Asks the shop to delete the card saved under `token`. Never throws; a lost connection is tried once more. */
export async function deleteSavedCard(token: string, options: { keepalive?: boolean } = {}): Promise<CardRemoval> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      return await api.deleteCard(token, options);
    } catch (error) {
      if (isApiError(error) && error.code === ErrorCode.notFound) return { status: 'none' };
      if (!(isApiError(error) && error.isOffline)) return { status: 'failed' };
    }
  }
  return { status: 'failed' };
}

/** The same, for when nobody waits on the answer: the client chose not to keep the card, or it was replaced. */
export function deleteSavedCardQuietly(token: string, options: { keepalive?: boolean } = {}): void {
  void deleteSavedCard(token, options);
}

/** While the shop is asked, or what it answered. */
export type CardRemovalState = CardRemoval | { status: 'asking' };

/**
 * "Forget me" on My appointments, about the card: the shop's own words once it answers, or to
 * call the shop when it couldn't be reached. Nothing when there was no card behind the key.
 */
export function forgetMeCardLine(removal: CardRemovalState | null, shopPhone: string): string | null {
  if (!removal) return null;
  switch (removal.status) {
    case 'asking':
      return 'Asking the shop to delete your saved card…';
    case 'deleted':
    case 'scheduled':
      return removal.message;
    case 'failed':
      return `We couldn't reach the shop to delete your saved card. To have it removed, call the shop at ${shopPhone}.`;
    default:
      return null;
  }
}

/**
 * "Not you?" on Your details, about the card. Whoever taps it may not be the client who saved the
 * card, so it says "the saved card", in plain words.
 */
export function notYouCardLine(removal: CardRemovalState | null, shopPhone: string): string | null {
  if (!removal) return null;
  switch (removal.status) {
    case 'asking':
      return 'Asking the shop to delete the saved card…';
    case 'deleted':
      return "The shop deleted the saved card too, so it can't be charged any more.";
    case 'scheduled':
      return 'The shop will delete the saved card as soon as the appointments booked with it no longer need it.';
    case 'failed':
      return `The shop couldn't be reached to delete the saved card. To have it removed, call the shop at ${shopPhone}.`;
    default:
      return null;
  }
}
