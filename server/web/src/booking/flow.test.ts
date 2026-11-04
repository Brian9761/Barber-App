import { describe, expect, it } from 'vitest';
import {
  bookingReducer,
  canVisit,
  DRAFT_KEY,
  EMPTY_DRAFT,
  firstOpenStep,
  loadDraft,
  nextStep,
  parseDraft,
  previousStep,
  retryKey,
  saveDraft,
  stepNumber,
  STEP_PATHS,
  targetOf,
  type BookingAction,
  type BookingDraft,
  type Details,
} from './flow';

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const CARLOS = 'carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41';
const TOKEN = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const details: Details = { name: 'Ana Flores', phone: '(442) 555-0123', email: '', note: 'Low fade', remember: true };

const run = (...actions: BookingAction[]) => actions.reduce(bookingReducer, EMPTY_DRAFT);

/** A booking taken all the way to Review. */
const complete = (): BookingDraft =>
  run(
    { type: 'chooseService', serviceId: 'haircut' },
    { type: 'chooseBarber', choice: { kind: 'offering', offeringId: FLOW45 } },
    { type: 'chooseTime', start: '2026-11-03T18:00:00Z' },
    { type: 'saveDetails', details },
  );

describe('the five steps', () => {
  it('go forward one at a time, each needing the ones before it', () => {
    expect(firstOpenStep(EMPTY_DRAFT)).toBe('service');
    expect(canVisit('barber', EMPTY_DRAFT)).toBe(false);

    const withService = run({ type: 'chooseService', serviceId: 'haircut' });
    expect(firstOpenStep(withService)).toBe('barber');
    expect(canVisit('barber', withService)).toBe(true);
    expect(canVisit('time', withService)).toBe(false);

    const withBarber = bookingReducer(withService, { type: 'chooseBarber', choice: { kind: 'any' } });
    expect(firstOpenStep(withBarber)).toBe('time');
    const withTime = bookingReducer(withBarber, { type: 'chooseTime', start: '2026-11-03T18:00:00Z' });
    expect(firstOpenStep(withTime)).toBe('details');
    const ready = bookingReducer(withTime, { type: 'saveDetails', details });
    expect(firstOpenStep(ready)).toBe('review');
    expect(canVisit('review', ready)).toBe(true);
  });

  it('are numbered 1 to 5 with a step before and after', () => {
    expect(stepNumber('service')).toBe(1);
    expect(stepNumber('review')).toBe(5);
    expect(previousStep('service')).toBeNull();
    expect(previousStep('time')).toBe('barber');
    expect(nextStep('details')).toBe('review');
    expect(nextStep('review')).toBeNull();
    expect(Object.values(STEP_PATHS)).toEqual(['/book', '/book/barber', '/book/time', '/book/details', '/book/review']);
  });

  it('keep every choice when the client goes back, and the same choice keeps the time', () => {
    const draft = complete();
    // Back is navigation only: the draft is the same, and every step is still reachable.
    expect(canVisit('review', draft)).toBe(true);
    const sameBarber = bookingReducer(draft, { type: 'chooseBarber', choice: { kind: 'offering', offeringId: FLOW45 } });
    expect(sameBarber).toBe(draft);
    const sameService = bookingReducer(draft, { type: 'chooseService', serviceId: 'haircut' });
    expect(sameService.start).toBe('2026-11-03T18:00:00Z');
    expect(sameService.choice).toEqual({ kind: 'offering', offeringId: FLOW45 });
  });

  it('drop what no longer fits when an earlier choice changes, but keep the client’s details', () => {
    const draft = { ...complete(), pending: { key: 'k', token: TOKEN } };
    const otherBarber = bookingReducer(draft, { type: 'chooseBarber', choice: { kind: 'offering', offeringId: CARLOS } });
    expect(otherBarber).toMatchObject({ start: null, pending: null, details });
    expect(firstOpenStep(otherBarber)).toBe('time');

    const otherService = bookingReducer(draft, { type: 'chooseService', serviceId: 'vip' });
    expect(otherService).toMatchObject({ serviceId: 'vip', choice: null, start: null, details });
    expect(firstOpenStep(otherService)).toBe('barber');
  });

  it('go straight to the times when the barber was picked first', () => {
    const draft = run(
      { type: 'begin', barberId: 'carlos-rafael' },
      { type: 'chooseService', serviceId: 'haircut', choice: { kind: 'offering', offeringId: CARLOS } },
    );
    expect(draft.barberId).toBe('carlos-rafael');
    expect(firstOpenStep(draft)).toBe('time');
    expect(bookingReducer(draft, { type: 'clearBarber' }).barberId).toBeNull();
  });

  it('go back to the times with a note when the time was taken', () => {
    const draft = { ...complete(), pending: { key: 'k', token: TOKEN } };
    const gone = bookingReducer(draft, { type: 'timeGone', message: 'Someone just booked 10 AM. Pick another time.' });
    expect(gone).toMatchObject({ start: null, pending: null, notice: 'Someone just booked 10 AM. Pick another time.' });
    expect(firstOpenStep(gone)).toBe('time');
    const picked = bookingReducer(gone, { type: 'chooseTime', start: '2026-11-03T18:30:00Z' });
    expect(picked.notice).toBeNull();
  });

  it('start fresh after booking, and for a new booking, keeping the details typed', () => {
    expect(bookingReducer(complete(), { type: 'booked' })).toEqual({ ...EMPTY_DRAFT, details });
    expect(bookingReducer(complete(), { type: 'begin', serviceId: 'vip' })).toEqual({ ...EMPTY_DRAFT, details, serviceId: 'vip' });
  });
});

describe('what the server books', () => {
  it('is the barber’s menu item, or the service with whoever is free first', () => {
    expect(targetOf(complete())).toEqual({ offeringId: FLOW45 });
    expect(targetOf(run({ type: 'chooseService', serviceId: 'haircut' }, { type: 'chooseBarber', choice: { kind: 'any' } }))).toEqual({
      serviceId: 'haircut',
      barberId: 'any',
    });
    expect(targetOf(EMPTY_DRAFT)).toBeNull();
  });

  it('is the same booking for a retry when the target, start and number are, whatever the name or note', () => {
    const key = retryKey({ offeringId: FLOW45 }, '2026-11-03T18:00:00Z', '+14425550123');
    expect(key).toBe(`offeringId=${FLOW45}|2026-11-03T18:00:00Z|+14425550123`);
    expect(retryKey({ serviceId: 'haircut', barberId: 'any' }, '2026-11-03T18:00:00Z', '+14425550123')).toBe(
      'serviceId=haircut&barberId=any|2026-11-03T18:00:00Z|+14425550123',
    );
    expect(retryKey({ offeringId: FLOW45 }, '2026-11-03T18:30:00Z', '+14425550123')).not.toBe(key);
    const withToken = bookingReducer(complete(), { type: 'pending', key, token: TOKEN });
    expect(withToken.pending).toEqual({ key, token: TOKEN });
    // A new name or note keeps the token: it's still the same booking to the server.
    expect(bookingReducer(withToken, { type: 'saveDetails', details: { ...details, name: 'Ana F.', note: '' } }).pending).toEqual({ key, token: TOKEN });
  });
});

describe('the booking kept in this tab', () => {
  it('comes back after the trip to Stripe’s card page, at Review', () => {
    const draft = { ...complete(), pending: { key: 'k', token: TOKEN } };
    // Before leaving for Stripe's page…
    saveDraft(draft);
    // …and on the way back, a new page load reads it again.
    const restored = loadDraft();
    expect(restored).toEqual(draft);
    expect(firstOpenStep(restored!)).toBe('review');
    expect(bookingReducer(EMPTY_DRAFT, { type: 'restore', draft: restored! })).toEqual(draft);
  });

  it('is ignored when it isn’t one', () => {
    sessionStorage.setItem(DRAFT_KEY, '{not json');
    expect(loadDraft()).toBeNull();
    expect(parseDraft({ ...complete(), choice: { kind: 'someone' } })).toBeNull();
    expect(parseDraft({ ...complete(), pending: { key: 'k', token: 'short' } })).toBeNull();
    expect(parseDraft({ ...complete(), details: { name: 'Ana' } })).toBeNull();
    expect(parseDraft(null)).toBeNull();
    expect(parseDraft(complete())).toEqual(complete());
  });
});
