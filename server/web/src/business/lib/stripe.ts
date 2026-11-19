// "Card payments (Stripe)" in Settings, in the owner app's words: the status, the main
// button, and the line after coming back from Stripe.

import { cardBrandName, cardLabel } from '../../lib/format';
import type { StripeCardToDelete, StripeConnection } from '../types';

export type StripeTone = 'good' | 'waiting' | 'problem' | 'neutral';

export interface StripeView {
  /** "Connected", "Not connected", "Finish setting up"… */
  label: string;
  tone: StripeTone;
  /** "Connect Stripe" or "Finish setting up", or null when there's nothing to do here. */
  action: string | null;
}

/** The status row and main button for a connection (the owner app's Settings → Card payments (Stripe)). */
export function stripeView(connection: Pick<StripeConnection, 'status'>): StripeView {
  switch (connection.status) {
    case 'active':
      return { label: 'Connected', tone: 'good', action: null };
    case 'notConnected':
      return { label: 'Not connected', tone: 'neutral', action: 'Connect Stripe' };
    case 'needsInfo':
      return { label: 'Finish setting up', tone: 'waiting', action: 'Finish setting up' };
    case 'pending':
      return { label: 'Stripe is checking your details', tone: 'waiting', action: null };
    case 'restricted':
      return { label: 'Paused by Stripe', tone: 'problem', action: 'Finish setting up' };
    case 'direct':
      return { label: "Uses the server's Stripe key", tone: 'good', action: null };
    case 'off':
      return { label: 'Not set up on the server', tone: 'neutral', action: null };
    default:
      return { label: 'Stripe', tone: 'neutral', action: null };
  }
}

/**
 * The line after coming back from Stripe (`/business/settings?stripe=<status>`), each naming the
 * button the status below offers, if any (the app's: "You're connected…", "Stripe still needs a
 * few details: tap Finish setting up.").
 */
export function stripeReturnLine(status: string): { text: string; good: boolean } {
  switch (status) {
    case 'active':
      return { text: "You're connected. You can take card payments now.", good: true };
    case 'pending':
      return { text: 'Stripe is checking your details. This usually takes a few minutes.', good: true };
    case 'needsInfo':
      return { text: 'Stripe still needs a few details: click Finish setting up.', good: false };
    case 'restricted':
      return { text: 'Stripe paused card payments: click Finish setting up to fix it.', good: false };
    case 'notConnected':
      return { text: "Stripe wasn't connected. Click Connect Stripe to try again.", good: false };
    case 'direct':
      return { text: "Card payments use this server's own Stripe key, so there's nothing to connect.", good: true };
    case 'off':
      return { text: "Stripe isn't set up on the server, so it can't be connected yet.", good: false };
    default:
      return { text: 'Back from Stripe. The status below says where things stand.', good: false };
  }
}

/** Whether Stripe takes card payments for the shop now (connected, or the server's own key). */
export function cardsReady(connection: Pick<StripeConnection, 'status'> | null): boolean {
  return connection?.status === 'active' || connection?.status === 'direct';
}

// "Cards to delete in Stripe": saved cards (and unfinished card pages) on a Stripe account the server
// can't use any more, which the shop deletes there itself, in the owner app's words.

export const CARDS_TO_DELETE_TITLE = 'Cards to delete in Stripe';
export const CARDS_TO_DELETE_INSTRUCTIONS =
  "The server can't reach these in Stripe any more, because the shop changed how it connects to Stripe. Delete these in your old Stripe account: Customers, then search for the customer id. Then click Deleted in Stripe.";
export const DELETED_IN_STRIPE = 'Deleted in Stripe';
export const CARD_PAGE_TITLE = "A card page that wasn't finished";
export const OFF_THE_LIST = "It's off the list. Thanks for deleting it in Stripe.";

export interface CardToDeleteView {
  /** "Visa •••• 4242", or "A card page that wasn't finished". */
  title: string;
  /** The title as a screen reader says it: "Visa ending in 4242". */
  spokenTitle: string;
  /** "Expires 12/30"; null for a card page. */
  expiry: string | null;
  /** "Customer: cus_123": what to search for in Stripe. */
  customer: string;
  /** "Stripe account: acct_123", or "Stripe account: the shop's own Stripe key", with " (test mode)". */
  account: string;
  /** What "It's deleted" asks first. */
  confirm: string;
}

export function cardToDeleteView(item: StripeCardToDelete): CardToDeleteView {
  const card = item.card;
  return {
    title: card ? cardLabel(card) : CARD_PAGE_TITLE,
    spokenTitle: card ? `${cardBrandName(card.brand)} ending in ${card.last4}` : CARD_PAGE_TITLE,
    expiry: card ? `Expires ${card.expMonth}/${String(card.expYear % 100).padStart(2, '0')}` : null,
    customer: `Customer: ${item.customerId}`,
    account: `Stripe account: ${item.stripeAccountId ?? "the shop's own Stripe key"}${item.livemode ? '' : ' (test mode)'}`,
    confirm: `Only click It's deleted once customer ${item.customerId} is deleted in your old Stripe account. It then comes off this list, and the customer id is forgotten here.`,
  };
}
