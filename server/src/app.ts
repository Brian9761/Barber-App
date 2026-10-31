import { cancelAppointment, getAppointment, getAvailability, listOwnerAppointments, patchOwnerAppointment, postAppointment, postOwnerAppointment } from './appointments.js';
import type { Deps } from './deps.js';
import { json } from './http.js';
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
      // Owner (Authorization: Bearer OWNER_KEY)
      .on('GET', '/api/owner/appointments', listOwnerAppointments)
      .on('POST', '/api/owner/appointments', postOwnerAppointment)
      .on('PATCH', '/api/owner/appointments/:id', patchOwnerAppointment)
      .on('GET', '/api/owner/time-off', listTimeOff)
      .on('POST', '/api/owner/time-off', postTimeOff)
      .on('DELETE', '/api/owner/time-off/:id', deleteTimeOff)
  );
}

export interface App {
  fetch(request: Request): Promise<Response>;
}

export function createApp(deps: Deps): App {
  const router = createRouter();
  return { fetch: (request) => router.handle(request, deps) };
}
