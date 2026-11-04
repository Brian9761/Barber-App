import { render } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { vi } from 'vitest';
import appointmentFixture from '../../../test/fixtures/contract/appointment.json';
import availabilityFixture from '../../../test/fixtures/contract/availability.json';
import catalogFixture from '../../../test/fixtures/contract/catalog.json';
import notRequiredFixture from '../../../test/fixtures/contract/no-show-policy-not-required.json';
import reviewsFixture from '../../../test/fixtures/contract/reviews.json';
import reviewsUnavailableFixture from '../../../test/fixtures/contract/reviews-unavailable.json';
import type { Appointment, Availability, Catalog, NoShowPolicy, Reviews } from '../api/types';
import { App, ROUTER_FUTURE } from '../App';
import { CatalogProvider } from '../data/catalog';

// The server's own contract fixtures (server/test/fixtures/contract), so the site is
// tested against exactly what the API answers.

export const catalog = catalogFixture as unknown as Catalog;
export const availability = availabilityFixture as unknown as Availability;
export const reviews = reviewsFixture as unknown as Reviews;
export const reviewsUnavailable = reviewsUnavailableFixture as unknown as Reviews;
export const policyNotRequired = notRequiredFixture as unknown as NoShowPolicy;
/** Flowxbori's 45-minute haircut at 10 AM on Tuesday, November 3, 2026, with a Visa on file. */
export const fixtureAppointment = appointmentFixture.appointment as unknown as Appointment;

export const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';

/** The policy for a $35 item with protection on, in the server's words. */
export const policy35: NoShowPolicy = {
  required: true,
  minFeeCents: 3500,
  maxFeeCents: 3500,
  policyText:
    "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $35 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free.",
  lateCancelWindowMinutes: 60,
  warning: {
    title: 'Full Service Cancellation & No-Show Fee',
    message:
      'Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($35). Cancelling in the app more than 1 hour before is free.',
  },
};

export interface ApiCall {
  method: string;
  path: string;
  search: string;
  headers: Record<string, string>;
  body: unknown;
}

type Reply = { status?: number; body?: unknown } | 'offline';
type Route = [match: string, reply: Reply | ((call: ApiCall) => Reply)];

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

export function apiError(code: string, message: string, status: number): Reply {
  return { status, body: { error: { code, message } } };
}

/**
 * Answers fetch from a list of routes ("GET /api/catalog", "POST /api/appointments"),
 * first match wins; a route can answer once (`once: true` via `queue`). Records every call.
 */
export function mockApi(routes: Route[]) {
  const calls: ApiCall[] = [];
  const queue = [...routes];
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, 'http://localhost');
    const headers: Record<string, string> = {};
    new Headers(init?.headers).forEach((value, key) => (headers[key] = value));
    const method = init?.method ?? 'GET';
    const call: ApiCall = {
      method,
      path: url.pathname,
      search: url.search,
      headers,
      body: typeof init?.body === 'string' ? JSON.parse(init.body) : undefined,
    };
    calls.push(call);
    const index = queue.findIndex(([match]) => {
      const [m, p] = match.split(' ');
      return m === method && (p === url.pathname || (p?.endsWith('*') && url.pathname.startsWith(p.slice(0, -1))));
    });
    if (index === -1) throw new Error(`No mock for ${method} ${url.pathname}`);
    const [, handler] = queue[index]!;
    const reply = typeof handler === 'function' ? handler(call) : handler;
    if (reply === 'offline') throw new TypeError('Failed to fetch');
    return json(reply.body ?? {}, reply.status ?? 200);
  });
  vi.stubGlobal('fetch', fetchMock);
  return {
    calls,
    /** Answers the next matching call differently, once (ahead of the other routes). */
    once(match: string, reply: Reply | ((call: ApiCall) => Reply)) {
      const route: Route = [
        match,
        (call) => {
          queue.splice(queue.indexOf(route), 1);
          return typeof reply === 'function' ? reply(call) : reply;
        },
      ];
      queue.unshift(route);
    },
  };
}

/** The whole site at `path`, with the catalog already loaded. */
export function renderApp(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]} future={ROUTER_FUTURE}>
      <CatalogProvider initial={catalog}>
        <App />
      </CatalogProvider>
    </MemoryRouter>,
  );
}
