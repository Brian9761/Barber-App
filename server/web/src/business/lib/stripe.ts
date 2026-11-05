// "Card payments (Stripe)" in Settings, in the owner app's words: the status, the main
// button, and the line after coming back from Stripe.

import type { StripeConnection } from '../types';

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
