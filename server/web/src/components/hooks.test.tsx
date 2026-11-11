import { act, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cutoffOf } from '../lib/lateCancel';
import { policy35 } from '../test/api';
import { useNow } from './hooks';

// The time the booking steps go by: every minute, and right past the moment a picked time's free
// cancellation ends, so "free until 9 AM" doesn't stay up to a minute after 9.

const START = '2026-11-03T18:00:00Z'; // 10 AM in the shop; with a 1-hour cutoff, free until 9 AM

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date', 'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval'] });
  vi.setSystemTime(new Date('2026-11-03T16:59:30Z')); // 8:59:30
});

afterEach(() => {
  vi.useRealTimers();
});

describe('the time now', () => {
  it('moves on right past the cutoff, not at the next minute', () => {
    const cutoff = cutoffOf(policy35, START)!;
    expect(new Date(cutoff).toISOString()).toBe('2026-11-03T17:00:00.000Z');
    const { result } = renderHook(() => useNow(60_000, cutoff));
    expect(result.current.toISOString()).toBe('2026-11-03T16:59:30.000Z');
    // Exactly at 9 it's still free (like the server), so nothing changes yet…
    act(() => void vi.advanceTimersByTime(30_000));
    expect(result.current.toISOString()).toBe('2026-11-03T16:59:30.000Z');
    // …and a millisecond later the page goes by the new time.
    act(() => void vi.advanceTimersByTime(1));
    expect(result.current.getTime()).toBeGreaterThan(cutoff);
  });

  it('still moves on every minute, and waits for no moment that has passed or is weeks away', () => {
    const { result: passed } = renderHook(() => useNow(60_000, Date.parse('2026-11-03T16:00:00Z')));
    const { result: far } = renderHook(() => useNow(60_000, Date.parse('2026-12-31T16:00:00Z')));
    act(() => void vi.advanceTimersByTime(1));
    expect(passed.current.toISOString()).toBe('2026-11-03T16:59:30.000Z');
    expect(far.current.toISOString()).toBe('2026-11-03T16:59:30.000Z');
    act(() => void vi.advanceTimersByTime(60_000));
    expect(passed.current.toISOString()).toBe('2026-11-03T17:00:30.000Z');
    expect(far.current.toISOString()).toBe('2026-11-03T17:00:30.000Z');
  });

  it('has no cutoff when cancelling is free until the start', () => {
    expect(cutoffOf({ ...policy35, lateCancelWindowMinutes: null }, START)).toBeNull();
    expect(cutoffOf({ ...policy35, required: false }, START)).toBeNull();
  });
});
