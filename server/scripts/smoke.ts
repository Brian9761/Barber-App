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
//
// No-show protection: when the usual item needs a card on file (Stripe set up,
// protection on), it checks the warning clients see ("Full Service Cancellation
// & No-Show Fee") and that booking it without a card is turned down
// (card_required), then books an item with no fee instead (an add-on that's
// included with a cut), since a card can only be saved on Stripe's own page.
// With SMOKE_OWNER_KEY it also prints the no-show settings.
//
// The website: the catalog it reads (/api/catalog, with the shop's details),
// its pages (/ and a deep link such as /book/time answer with index.html) and a
// real 404 for a missing file under /assets/. SMOKE_WEBSITE=off skips the pages,
// for `npm run dev`, which serves only the API.

import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';

// Real environment variables win over .env.local.
if (existsSync('.env.local')) process.loadEnvFile('.env.local');

const base = (process.argv[2] ?? process.env.SMOKE_BASE_URL ?? 'http://localhost:3000').replace(/\/+$/, '');
const ownerKey = process.env.SMOKE_OWNER_KEY;
const OFFERING = process.env.SMOKE_OFFERING_ID ?? 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
/** No fee, so no card needed, whatever the no-show settings. */
const NO_CARD_OFFERING = process.env.SMOKE_NO_CARD_OFFERING_ID ?? 'carlos-rafael/0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb';

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

  const catalog = await call('GET', '/api/catalog');
  check(
    catalog.status === 200 && typeof catalog.body?.shop?.phone?.e164 === 'string' && Array.isArray(catalog.body?.services),
    `the website's catalog answers with the shop's details (${catalog.status} ${catalog.body?.error?.code ?? ''})`,
  );
  if (process.env.SMOKE_WEBSITE !== 'off') {
    for (const path of ['/', '/book/time']) {
      const page = await fetch(`${base}${path}`);
      const html = await page.text();
      check(
        page.status === 200 && (page.headers.get('content-type') ?? '').includes('text/html') && html.includes('id="root"'),
        `the website answers ${path} with its page (${page.status} ${page.headers.get('content-type') ?? ''})`,
      );
    }
    const missing = await fetch(`${base}/assets/izzy-smoke-missing.js`);
    check(missing.status === 404, `a missing website file is a 404, not the page (${missing.status})`);
  }

  if (owner) {
    const me = await call('GET', '/api/owner/me', { headers: owner });
    check(me.status === 200, `owner key accepted (stripe: ${JSON.stringify(me.body?.stripe)})`);
    const settings = await call('GET', '/api/owner/no-show-settings', { headers: owner });
    check(settings.status === 200 && typeof settings.body?.noShowSettings?.enabled === 'boolean', `no-show settings ${JSON.stringify(settings.body?.noShowSettings)}`);
  }

  // The latest days of the booking window, last slot first.
  const policyOf = async (offeringId: string) => {
    const res = await call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(offeringId)}`);
    check(res.status === 200, `no-show policy for ${offeringId} answers (card needed: ${res.body?.required})`);
    if (res.body?.required) {
      const { policyText, warning, lateCancelWindowMinutes } = res.body;
      check(typeof policyText === 'string' && policyText.length > 0, `the policy to agree to: ${policyText}`);
      check(typeof warning?.title === 'string' && typeof warning?.message === 'string', `the warning: ${warning?.title}: ${warning?.message}`);
      check(lateCancelWindowMinutes === null || Number.isInteger(lateCancelWindowMinutes), `late cancellations: ${lateCancelWindowMinutes === null ? 'free' : `${lateCancelWindowMinutes} minutes`}`);
    }
    return res.body as { required: boolean };
  };
  const lastSlot = async (offeringId: string) => {
    const from = new Date(Date.now() + 52 * 86_400_000).toISOString().slice(0, 10);
    const probe = await call('GET', `/api/availability?offeringId=${encodeURIComponent(offeringId)}&from=${from}&days=7`);
    check(probe.status === 200, 'availability answers');
    const open = [...probe.body.days].reverse().find((d: { slots: unknown[] }) => d.slots.length > 0);
    check(open, `found an open day near the end of the window (${open?.date})`);
    return { day: open as { date: string }, slot: open.slots[open.slots.length - 1].start as string };
  };
  const customer = { name: 'Smoke test', phone: '(442) 555-0199' };

  let offering = OFFERING;
  if ((await policyOf(OFFERING)).required) {
    const { slot: protectedSlot } = await lastSlot(OFFERING);
    const noCard = await call('POST', '/api/appointments', { body: { offeringId: OFFERING, start: protectedSlot, customer } });
    check(noCard.status === 400 && noCard.body?.error?.code === 'card_required', `booking without a card is turned down (${noCard.status} ${noCard.body?.error?.code ?? ''})`);
    offering = NO_CARD_OFFERING;
    check(!(await policyOf(offering)).required, `${offering} books without a card`);
  }
  const availabilityPath = (from: string) => `/api/availability?offeringId=${encodeURIComponent(offering)}&from=${from}&days=7`;
  const { day, slot } = await lastSlot(offering);

  // Booked like the app does it: with a manage token of its own, so a retry is safe.
  const token = randomBytes(32).toString('base64url');
  const request = {
    body: { offeringId: offering, start: slot, customer, note: 'Automated check, cancelled right away.' },
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
