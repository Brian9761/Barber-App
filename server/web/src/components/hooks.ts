import { useEffect, useState, type RefObject } from 'react';

/** Longer than a timer can wait (about 24.8 days): such a moment is caught by the minute's refresh later. */
const LONGEST_WAIT_MS = 2 ** 31 - 1;

/**
 * The time now, refreshed every minute, so "Open today until 7 PM" changes at 7; and, given
 * `changesAt` (a moment in ms), again just past that moment, when what the page says turns on it
 * exactly: once a picked time is inside its free-cancellation cutoff, the booking steps say so
 * then, not up to a minute later.
 */
export function useNow(intervalMs = 60_000, changesAt: number | null = null): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  useEffect(() => {
    if (changesAt === null || !Number.isFinite(changesAt) || now.getTime() > changesAt) return;
    const wait = changesAt - Date.now() + 1;
    if (wait > LONGEST_WAIT_MS) return;
    const id = window.setTimeout(() => setNow(new Date()), Math.max(0, wait));
    return () => window.clearTimeout(id);
  }, [changesAt, now]);
  return now;
}

/** True once the element is near the screen (or right away where browsers can't tell). */
export function useNearScreen(ref: RefObject<Element | null>, margin = '300px'): boolean {
  const [near, setNear] = useState(() => typeof IntersectionObserver === 'undefined');
  useEffect(() => {
    const element = ref.current;
    if (near || !element || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setNear(true);
          observer.disconnect();
        }
      },
      { rootMargin: margin },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref, margin, near]);
  return near;
}
