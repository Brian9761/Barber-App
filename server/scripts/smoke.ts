// npm run smoke -- https://izzy-clipz-api.vercel.app
//
// End-to-end check against a running API (production after a deploy, or
// `npm run dev`): health, then a real booking far in the future that's seen
// leaving availability, retried safely with the same token, cancelled with its
// manage token, and seen coming back.
// With SMOKE_OWNER_KEY it also checks the owner API sees the booking, and cleans
// up through it if the customer cancel fails.
//
// It books the last start time of a weekday near the end of the booking window
// under the name "Smoke test" and a 555-01xx number (reserved for fiction), then
// cancels it straight away.

import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';

// Real environment variables win over .env.local.
if (existsSync('.env.local')) process.loadEnvFile('.env.local');

const base = (process.argv[2] ?? process.env.SMOKE_BASE_URL ?? 'http://localhost:3000').replace(/\/+$/, '');
const ownerKey = process.env.SMOKE_OWNER_KEY;
const OFFERING = process.env.SMOKE_OFFERING_ID ?? 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';

async function call(method: string, path: string, init: { body?: unknown; headers?: Record<string, string> } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { accept: 'application/json', ...(init.body ? { 'content-type': 'application/json' } : {}), ...init.headers },
    ...(init.body ? { body: JSON.stringify(init.body) } : {}),
  });
  const text = await response.text();
  let body: any = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: response.status, body };
}

function check(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
  console.log(`ok  ${message}`);
}

const owner = ownerKey ? { authorization: `Bearer ${ownerKey}` } : undefined;
let booked: { id: string; token: string } | undefined;

try {
  const health = await call('GET', '/api/health');
  check(health.status === 200 && health.body?.ok === true, `health ${JSON.stringify(health.body)}`);

  if (owner) {
    const me = await call('GET', '/api/owner/me', { headers: owner });
    check(me.status === 200, `owner key accepted (stripe: ${JSON.stringify(me.body?.stripe)})`);
  }

  // The latest days of the booking window, last slot first.
  const availabilityPath = (from: string) => `/api/availability?offeringId=${encodeURIComponent(OFFERING)}&from=${from}&days=7`;
  const probe = await call('GET', availabilityPath(new Date(Date.now() + 52 * 86_400_000).toISOString().slice(0, 10)));
  check(probe.status === 200, 'availability answers');
  const day = [...probe.body.days].reverse().find((d: { slots: unknown[] }) => d.slots.length > 0);
  check(day, `found an open day near the end of the window (${day?.date})`);
  const slot = day.slots[day.slots.length - 1].start as string;

  // Booked like the app does it: with a manage token of its own, so a retry is safe.
  const token = randomBytes(32).toString('base64url');
  const request = {
    body: { offeringId: OFFERING, start: slot, customer: { name: 'Smoke test', phone: '(442) 555-0199' }, note: 'Automated check, cancelled right away.' },
    headers: { 'x-manage-token': token },
  };
  const created = await call('POST', '/api/appointments', request);
  check(created.status === 201, `booked ${slot} (${created.status} ${created.body?.error?.code ?? ''})`);
  booked = { id: created.body.appointment.id, token: created.body.manageToken };
  check(booked.token === token, 'the booking uses the token the client sent');

  const retried = await call('POST', '/api/appointments', request);
  check(
    retried.status === 200 && retried.body.appointment.id === booked.id && retried.body.manageToken === token,
    `a retry with the same token gets the same booking (${retried.status} ${retried.body?.error?.code ?? ''})`,
  );

  const after = await call('GET', availabilityPath(day.date));
  const stillListed = after.body.days[0].slots.some((s: { start: string }) => s.start === slot);
  check(!stillListed, 'the slot left availability');

  const read = await call('GET', `/api/appointments/${booked.id}`, { headers: { 'x-manage-token': booked.token } });
  check(read.status === 200 && read.body.appointment.status === 'booked', 'read it back with the manage token');

  if (owner) {
    const list = await call('GET', `/api/owner/appointments?date=${day.date}`, { headers: owner });
    check(list.body.appointments.some((a: { id: string }) => a.id === booked!.id), 'the owner schedule shows it');
  }

  const cancelled = await call('POST', `/api/appointments/${booked.id}/cancel`, { headers: { 'x-manage-token': booked.token } });
  check(cancelled.status === 200 && cancelled.body.appointment.status === 'cancelled', 'cancelled it');
  booked = undefined;

  const back = await call('GET', availabilityPath(day.date));
  check(back.body.days[0].slots.some((s: { start: string }) => s.start === slot), 'the slot is back');
  console.log('Smoke test passed.');
} catch (error) {
  console.error(`FAILED against ${base}: ${error instanceof Error ? error.message : error}`);
  if (booked && owner) {
    const cleanup = await call('PATCH', `/api/owner/appointments/${booked.id}`, { headers: owner, body: { status: 'cancelled' } });
    console.error(`cleanup: cancelled through the owner API (${cleanup.status})`);
  } else if (booked) {
    console.error(`Left a booking behind: ${booked.id}. Cancel it in the Business app.`);
  }
  process.exitCode = 1;
}
