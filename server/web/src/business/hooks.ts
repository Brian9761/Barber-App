// What Izzy Clipz Business's pages share: their titles, the page's own manifest and
// icons (also when it's reached from the site without a page load), the clock, whether
// the page is on screen, and loading that keeps what's shown while it refreshes.

import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { errorMessage } from '../api/errors';
import { isDemo } from '../demo/mode';

export const APP_NAME = 'Izzy Clipz Business';

/** Each page's own <title> ("Today · Izzy Clipz Business") and description. */
export function useBusinessTitle(title: string | null, description?: string): void {
  useEffect(() => {
    document.title = title ? `${title} · ${APP_NAME}` : APP_NAME;
    if (description) document.head.querySelector('meta[name="description"]')?.setAttribute('content', description);
  }, [title, description]);
}

/**
 * The page links Izzy Clipz Business's own manifest and icons, so it installs (or goes on a
 * Home Screen) as Izzy Clipz Business, and asks search engines not to list it. business/index.html
 * already has them; reached from the site's pages without a page load, they're put in place here,
 * and the site's come back when it's left.
 */
export function useBusinessHead(): void {
  useEffect(() => {
    const undo: (() => void)[] = [];
    const set = (selector: string, attribute: string, value: string, create: () => HTMLElement) => {
      let element = document.head.querySelector<HTMLElement>(selector);
      if (!element) {
        element = create();
        document.head.append(element);
        const added = element;
        undo.push(() => added.remove());
      } else {
        const before = element.getAttribute(attribute);
        const changed = element;
        undo.push(() => (before === null ? changed.removeAttribute(attribute) : changed.setAttribute(attribute, before)));
      }
      element.setAttribute(attribute, value);
    };
    const link = (rel: string) => () => Object.assign(document.createElement('link'), { rel });
    const meta = (name: string) => () => {
      const element = document.createElement('meta');
      element.setAttribute('name', name);
      return element;
    };
    set('link[rel="manifest"]', 'href', '/business/manifest.webmanifest', link('manifest'));
    set('link[rel="apple-touch-icon"]', 'href', '/business/apple-touch-icon.png', link('apple-touch-icon'));
    set('meta[name="apple-mobile-web-app-title"]', 'content', 'IC Business', meta('apple-mobile-web-app-title'));
    set('meta[name="robots"]', 'content', 'noindex', meta('robots'));
    return () => {
      for (const step of undo.reverse()) step();
    };
  }, []);
}

/** The time now, refreshed every `intervalMs` (a minute), so "Mark no-show" shows once an appointment starts. */
export function useClock(intervalMs = 30_000): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}

function subscribeVisibility(listener: () => void): () => void {
  document.addEventListener('visibilitychange', listener);
  return () => document.removeEventListener('visibilitychange', listener);
}

/** Whether the page is on screen (not a hidden tab or a minimized window). */
export function usePageVisible(): boolean {
  return useSyncExternalStore(
    subscribeVisibility,
    () => document.visibilityState !== 'hidden',
    () => true,
  );
}

export type LoadState<T> =
  | { status: 'loading'; data: T | null; error: null }
  | { status: 'ready'; data: T; error: null }
  | { status: 'error'; data: T | null; error: string };

/**
 * Loads `load(signal)` for `key`, and again on `reload()` or every `refreshMs` while the page is
 * on screen. A refresh never stacks on one still running, and what's shown stays while it runs;
 * a new `key` (another day, another period) starts from nothing. A refresh that fails keeps the
 * data and says so (`error`).
 */
export function useLoad<T>(key: string, load: (signal: AbortSignal) => Promise<T>, options: { refreshMs?: number } = {}) {
  const [state, setState] = useState<{ key: string; value: LoadState<T> }>({ key, value: { status: 'loading', data: null, error: null } });
  const loadRef = useRef(load);
  loadRef.current = load;
  const running = useRef<{ key: string; controller: AbortController } | null>(null);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const visible = usePageVisible();

  const run = useCallback(
    (fresh: boolean) => {
      if (running.current && running.current.key === key && !fresh) return;
      running.current?.controller.abort();
      const controller = new AbortController();
      running.current = { key, controller };
      setState((previous) => {
        const keep = previous.key === key ? previous.value.data : null;
        return { key, value: { status: 'loading', data: keep, error: null } };
      });
      loadRef
        .current(controller.signal)
        .then((data) => {
          if (controller.signal.aborted) return;
          setState({ key, value: { status: 'ready', data, error: null } });
          setUpdatedAt(new Date());
        })
        .catch((error: unknown) => {
          if (controller.signal.aborted || (error instanceof DOMException && error.name === 'AbortError')) return;
          setState((previous) => ({
            key,
            value: { status: 'error', data: previous.key === key ? previous.value.data : null, error: errorMessage(error) },
          }));
        })
        .finally(() => {
          if (running.current?.controller === controller) running.current = null;
        });
    },
    [key],
  );

  useEffect(() => {
    run(true);
    return () => {
      running.current?.controller.abort();
      running.current = null;
    };
  }, [run]);

  const refreshMs = options.refreshMs;
  useEffect(() => {
    if (!refreshMs || !visible) return;
    const id = window.setInterval(() => run(false), refreshMs);
    return () => window.clearInterval(id);
  }, [refreshMs, visible, run]);

  // Back on screen after a while: fresh numbers right away.
  const wasVisible = useRef(visible);
  useEffect(() => {
    if (visible && !wasVisible.current && refreshMs) run(false);
    wasVisible.current = visible;
  }, [visible, refreshMs, run]);

  /** Loads again now (after a change): a refresh still running is dropped, so its older answer can't win. */
  const reload = useCallback(() => run(true), [run]);
  /** Shows `data` right away (what a change answered with), until the next load. */
  const replace = useCallback((data: T) => setState({ key, value: { status: 'ready', data, error: null } }), [key]);

  const value: LoadState<T> = state.key === key ? state.value : { status: 'loading', data: null, error: null };
  return { ...value, updatedAt, reload, replace };
}

/** "Demo version: sample data, nothing is sent anywhere." */
export const DEMO_LINE = 'Demo version: sample data, nothing is sent anywhere.';

export function demo(): boolean {
  return isDemo();
}
