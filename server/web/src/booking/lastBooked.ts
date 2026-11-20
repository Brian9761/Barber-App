import { listedAppointment, loadAppointments, readJSON, removeKey, writeJSON, type ListedAppointment } from '../lib/storage';

// The booking just made, for "You're booked" (and that page reloaded). Never in the browser's
// history, which "Forget me" can't clear: the confirmation shows the appointment from the list this
// browser keeps (lib/storage.ts, which "Forget me" clears), found by the id kept here for the tab.
// Only when this browser couldn't keep the appointment is it held in this page's memory instead,
// without the client's own details, until the page closes or "Forget me".

const LAST_BOOKED_KEY = 'izzy.lastBooked.v1';

/** The last booking's id, should this tab's storage not keep it; and the booking, should this browser not have kept it. */
let inThisPage: { id: string; notKept: ListedAppointment | null } | null = null;

/**
 * The booking just made (`appointmentId`), for its confirmation. `notKept` is the appointment when
 * this browser couldn't keep it (its list of appointments wouldn't save): the confirmation shows it
 * from this page's memory, once, and says to write it down.
 */
export function rememberLastBooked(appointmentId: string, notKept: ListedAppointment | null = null): void {
  writeJSON('session', LAST_BOOKED_KEY, appointmentId);
  inThisPage = { id: appointmentId, notKept: notKept ? listedAppointment(notKept) : null };
}

export function lastBookedId(): string | null {
  const id = readJSON('session', LAST_BOOKED_KEY);
  return typeof id === 'string' ? id : (inThisPage?.id ?? null);
}

/**
 * What "You're booked" shows: the last booking as this browser keeps it (`saved`), or, when it
 * couldn't keep it, as this page holds it (not `saved`); null once it's gone ("Forget me", the tab
 * closed, or it was removed from the list since).
 */
export function lastBooked(): { appointment: ListedAppointment; saved: boolean } | null {
  const id = lastBookedId();
  if (!id) return null;
  const kept = loadAppointments().find((s) => s.id === id)?.appointment;
  if (kept) return { appointment: kept, saved: true };
  if (inThisPage?.id === id && inThisPage.notKept) return { appointment: inThisPage.notKept, saved: false };
  return null;
}

export function forgetLastBooked(): void {
  removeKey('session', LAST_BOOKED_KEY);
  inThisPage = null;
}
