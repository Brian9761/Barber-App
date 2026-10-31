import { cancelAppointment, getAppointment, getAvailability, getOwnerAvailability, listOwnerAppointments, patchOwnerAppointment, postAppointment, postOwnerAppointment } from './appointments.js';
import { dailyCron } from './cron.js';
import type { Deps } from './deps.js';
import { json } from './http.js';
import { completePayment, connectionToken, createPayment, listPayments, ownerMe, stripeWebhook } from './payments.js';
import { createProduct, deleteProduct, listOwnerProducts, listPublicProducts, updateProduct, uploadProductPhoto } from './products.js';
import { getReviews } from './reviews.js';
import { Router } from './router.js';
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
      // Owner (Authorization: Bearer OWNER_KEY)
      .on('GET', '/api/owner/me', ownerMe)
      .on('GET', '/api/owner/availability', getOwnerAvailability)
      .on('GET', '/api/owner/appointments', listOwnerAppointments)
      .on('POST', '/api/owner/appointments', postOwnerAppointment)
      .on('PATCH', '/api/owner/appointments/:id', patchOwnerAppointment)
      .on('GET', '/api/owner/time-off', listTimeOff)
      .on('POST', '/api/owner/time-off', postTimeOff)
      .on('DELETE', '/api/owner/time-off/:id', deleteTimeOff)
      .on('GET', '/api/owner/products', listOwnerProducts)
      .on('POST', '/api/owner/products', createProduct)
      .on('PATCH', '/api/owner/products/:id', updateProduct)
      .on('DELETE', '/api/owner/products/:id', deleteProduct)
      .on('POST', '/api/owner/products/:id/photo', uploadProductPhoto)
      .on('POST', '/api/owner/terminal/connection-token', connectionToken)
      .on('POST', '/api/owner/payments', createPayment)
      .on('GET', '/api/owner/payments', listPayments)
      .on('POST', '/api/owner/payments/:id/complete', completePayment)
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
