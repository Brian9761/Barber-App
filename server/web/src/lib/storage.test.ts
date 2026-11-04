import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Appointment } from '../api/types';
import { fixtureAppointment } from '../test/api';
import {
  APPOINTMENTS_KEY,
  CARRY_COOKIE,
  carriedAppointments,
  carryAppointments,
  DEMO_APPOINTMENTS_KEY,
  DEMO_STORE_KEY,
  dropCarried,
  forgetAppointments,
  forgetDemoLeftovers,
  loadAppointments,
  removeAppointment,
  saveAppointment,
} from './storage';
import { newToken } from './tokens';

// What this browser keeps of the appointments booked in it, and what it carries (in a cookie,
// the only thing an iPhone copies) into the app added to the Home Screen.

const NOW = new Date('2026-11-02T17:00:00Z');
const DAY = 86_400_000;

function appointment(id: string, end = '2026-11-03T18:45:00Z'): Appointment {
  return { ...fixtureAppointment, id, end };
}

const cookieValue = () =>
  document.cookie
    .split(/;\s*/)
    .find((pair) => pair.startsWith(`${CARRY_COOKIE}=`))
    ?.slice(CARRY_COOKIE.length + 1);

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('carried into the app on the Home Screen', () => {
  it('keeps each booking’s id and manage token in a cookie, and nothing else of it', () => {
    const token = newToken();
    const booked: Appointment = { ...fixtureAppointment, note: 'Low fade' };
    saveAppointment(booked, token, NOW);
    expect(carriedAppointments(NOW)).toEqual([{ id: fixtureAppointment.id, manageToken: token, until: Date.parse(fixtureAppointment.end) + 30 * DAY }]);
    const value = cookieValue()!;
    expect(value.startsWith(`${fixtureAppointment.id}.${token}.`)).toBe(true);
    for (const detail of ['Haircut', 'Flowxbori', 'Low fade', fixtureAppointment.customer.name]) expect(value, detail).not.toContain(detail);
  });

  it('is what an app with only the cookies brings in: localStorage gone, the cookie still there', () => {
    const token = newToken();
    saveAppointment(fixtureAppointment, token, NOW);
    localStorage.clear(); // a Home Screen app's own website data: only the cookies were copied
    expect(loadAppointments(NOW)).toEqual([]);
    expect(carriedAppointments(NOW).map((c) => c.manageToken)).toEqual([token]);
  });

  it('carries the appointments listed here with the ones already carried, latest first, ten at most', () => {
    const tokens = Array.from({ length: 12 }, () => newToken());
    tokens.forEach((token, i) => saveAppointment(appointment(`appt-${i}`, new Date(Date.parse('2026-11-03T18:45:00Z') + i * DAY).toISOString()), token, NOW));
    const carried = carriedAppointments(NOW);
    expect(carried).toHaveLength(10);
    expect(carried[0]!.id).toBe('appt-11');
    expect(carried.at(-1)!.id).toBe('appt-2');

    // One booked before there was a cookie: carried when the site next opens.
    document.cookie = `${CARRY_COOKIE}=; Path=/; Max-Age=0`;
    expect(carriedAppointments(NOW)).toEqual([]);
    carryAppointments(loadAppointments(NOW), NOW);
    expect(carriedAppointments(NOW)).toHaveLength(10);
  });

  it('lets one go 30 days after the appointment ends, like the list', () => {
    saveAppointment(fixtureAppointment, newToken(), NOW);
    const end = Date.parse(fixtureAppointment.end);
    expect(carriedAppointments(new Date(end + 30 * DAY - 1000))).toHaveLength(1);
    expect(carriedAppointments(new Date(end + 30 * DAY + 1000))).toEqual([]);
  });

  it('stops carrying one removed from the list, one the shop doesn’t know, and all of them with “Forget me”', () => {
    saveAppointment(appointment('appt-a'), newToken(), NOW);
    saveAppointment(appointment('appt-b'), newToken(), NOW);
    saveAppointment(appointment('appt-c'), newToken(), NOW);
    removeAppointment('appt-a', NOW);
    dropCarried('appt-b', NOW);
    expect(carriedAppointments(NOW).map((c) => c.id)).toEqual(['appt-c']);
    forgetAppointments();
    expect(carriedAppointments(NOW)).toEqual([]);
    expect(cookieValue()).toBeUndefined();
  });

  it('ignores a cookie that isn’t its own shape', () => {
    document.cookie = `${CARRY_COOKIE}=not.a.token~${'x'.repeat(10)}; Path=/`;
    expect(carriedAppointments(NOW)).toEqual([]);
  });
});

describe('the demo', () => {
  it('lists its bookings under a key of its own, and carries none of them', () => {
    vi.stubEnv('VITE_DEMO_MODE', '1');
    saveAppointment(fixtureAppointment, newToken(), NOW);
    expect(localStorage.getItem(APPOINTMENTS_KEY)).toBeNull();
    expect(localStorage.getItem(DEMO_APPOINTMENTS_KEY)).not.toBeNull();
    expect(cookieValue()).toBeUndefined();
    expect(carriedAppointments(NOW)).toEqual([]);
  });

  it('leaves nothing behind for the real site, should it open where the demo was', () => {
    vi.stubEnv('VITE_DEMO_MODE', '1');
    saveAppointment(fixtureAppointment, newToken(), NOW);
    localStorage.setItem(DEMO_STORE_KEY, JSON.stringify({ version: 2, bookings: [] }));
    vi.unstubAllEnvs();
    // The real site sees none of the demo's bookings, and forgets them when it starts (main.tsx).
    expect(loadAppointments(NOW)).toEqual([]);
    forgetDemoLeftovers();
    expect(localStorage.getItem(DEMO_APPOINTMENTS_KEY)).toBeNull();
    expect(localStorage.getItem(DEMO_STORE_KEY)).toBeNull();
  });
});
