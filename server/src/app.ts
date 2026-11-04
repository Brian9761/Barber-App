import { cancelAppointment, getAppointment, getAvailability, getOwnerAvailability, listOwnerAppointments, patchOwnerAppointment, postAppointment, postOwnerAppointment } from './appointments.js';
import { cardCheckoutCancel, cardCheckoutReturn, createCardCheckout, saveCard } from './cards.js';
import {
  createComputerCode,
  createComputerSession,
  listComputerSessions,
  revokeAllComputerSessions,
  revokeComputerSession,
  revokeCurrentComputerSession,
} from './computers.js';
import { dailyCron } from './cron.js';
import type { Deps } from './deps.js';
import { json } from './http.js';
import { completePayment, connectionToken, createPayment, listPayments, ownerMe, stripeWebhook } from './payments.js';
import { getNoShowPolicy, getNoShowSettings, patchNoShowSettings } from './noshow.js';
import { chargeNoShowFee } from './noshowfee.js';
import { createProduct, deleteProduct, listOwnerProducts, listPublicProducts, updateProduct, uploadProductPhoto } from './products.js';
import { getReviews } from './reviews.js';
import { Router } from './router.js';
import { deleteStripeConnect, getOwnerStripe, postStripeConnect, stripeConnectRefresh, stripeConnectReturn } from './stripeconnect.js';
import { deleteTimeOff, listTimeOff, postTimeOff } from './timeoff.js';
import { VERSION } from './version.js';

/** The routes of API v1 (the contract is summarized in README.md). */
export function createRouter(): Router {
  return (
    new Router()
      // Public
      .on('GET', '/api/health', async () => json({ ok: true, version: VERSION }))
      .on('GET', '/api/availability', getAvailability)
      .on('POST', '/api/appointments', postAppointment)
      .on('GET', '/api/appointments/:id', getAppointment)
      .on('POST', '/api/appointments/:id/cancel', cancelAppointment)
      .on('GET', '/api/reviews', getReviews)
      .on('GET', '/api/products', listPublicProducts)
      // No-show protection (a card on file)
      .on('GET', '/api/no-show-policy', getNoShowPolicy)
      .on('POST', '/api/cards/checkout', createCardCheckout)
      .on('GET', '/api/cards/return', cardCheckoutReturn)
      .on('GET', '/api/cards/cancel', cardCheckoutCancel)
      .on('POST', '/api/cards', saveCard)
      // Signing in on a computer with a code from the Business app
      .on('POST', '/api/computer-sessions', createComputerSession)
      // Stripe's way back after connecting the shop's own account (a browser lands here)
      .on('GET', '/api/stripe/connect/return', stripeConnectReturn)
      .on('GET', '/api/stripe/connect/refresh', stripeConnectRefresh)
      // Owner (Authorization: Bearer OWNER_KEY, or a computer's session token except where marked)
      .on('GET', '/api/owner/me', ownerMe)
      .on('GET', '/api/owner/availability', getOwnerAvailability)
      .on('GET', '/api/owner/appointments', listOwnerAppointments)
      .on('POST', '/api/owner/appointments', postOwnerAppointment)
      .on('PATCH', '/api/owner/appointments/:id', patchOwnerAppointment)
      .on('POST', '/api/owner/appointments/:id/no-show-fee', chargeNoShowFee)
      .on('GET', '/api/owner/no-show-settings', getNoShowSettings)
      .on('PATCH', '/api/owner/no-show-settings', patchNoShowSettings)
      .on('GET', '/api/owner/time-off', listTimeOff)
      .on('POST', '/api/owner/time-off', postTimeOff)
      .on('DELETE', '/api/owner/time-off/:id', deleteTimeOff)
      .on('GET', '/api/owner/products', listOwnerProducts)
      .on('POST', '/api/owner/products', createProduct)
      .on('PATCH', '/api/owner/products/:id', updateProduct)
      .on('DELETE', '/api/owner/products/:id', deleteProduct)
      .on('POST', '/api/owner/products/:id/photo', uploadProductPhoto)
      .on('POST', '/api/owner/terminal/connection-token', connectionToken) // the owner key only
      .on('POST', '/api/owner/payments', createPayment) // the owner key only
      .on('GET', '/api/owner/payments', listPayments)
      .on('POST', '/api/owner/payments/:id/complete', completePayment)
      // The shop's own Stripe account (STRIPE_CONNECT=on)
      .on('GET', '/api/owner/stripe', getOwnerStripe)
      .on('POST', '/api/owner/stripe/connect', postStripeConnect)
      .on('DELETE', '/api/owner/stripe/connect', deleteStripeConnect) // the owner key only
      // Computers signed in to the website's Business area
      .on('POST', '/api/owner/computer-codes', createComputerCode) // the owner key only
      .on('GET', '/api/owner/computer-sessions', listComputerSessions)
      .on('DELETE', '/api/owner/computer-sessions', revokeAllComputerSessions)
      .on('DELETE', '/api/owner/computer-sessions/current', revokeCurrentComputerSession)
      .on('DELETE', '/api/owner/computer-sessions/:id', revokeComputerSession)
      // Machines
      .on('POST', '/api/stripe/webhook', stripeWebhook)
      .on('GET', '/api/cron/daily', dailyCron)
  );
}

export interface App {
  fetch(request: Request): Promise<Response>;
}

export function createApp(deps: Deps): App {
  const router = createRouter();
  return { fetch: (request) => router.handle(request, deps) };
}
