import { readJSON, removeKey, writeJSON } from '../lib/storage';

// The booking just made, for "You're booked" after a reload of that page.

const LAST_BOOKED_KEY = 'izzy.lastBooked.v1';

export function rememberLastBooked(appointmentId: string): void {
  writeJSON('session', LAST_BOOKED_KEY, appointmentId);
}

export function lastBookedId(): string | null {
  const id = readJSON('session', LAST_BOOKED_KEY);
  return typeof id === 'string' ? id : null;
}

export function forgetLastBooked(): void {
  removeKey('session', LAST_BOOKED_KEY);
}
