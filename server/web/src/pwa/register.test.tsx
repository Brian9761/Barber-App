import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import offlineHtml from '../../public/offline.html?raw';
import { FALLBACK_SHOP } from '../data/fallback';
import { renderApp, mockApi, reviewsUnavailable } from '../test/api';
import { checkForUpdatesWhenShown, registerServiceWorker } from './register';
import { UpdateBar } from './UpdateBar';
import { offerUpdate } from './updates';

// A new version never reloads the page by itself: it waits until someone taps Reload on the
// quiet bar. Offline, the site says so and gives the number to book by phone.

class FakeWorker extends EventTarget {
  state = 'installing';
  readonly postMessage = vi.fn();
  install(): void {
    this.state = 'installed';
    this.dispatchEvent(new Event('statechange'));
  }
}

class FakeRegistration extends EventTarget {
  waiting: FakeWorker | null = null;
  installing: FakeWorker | null = null;
  readonly update = vi.fn(() => Promise.resolve());
  /** The browser found a new version and is installing it. */
  found(): FakeWorker {
    const worker = new FakeWorker();
    this.installing = worker;
    this.dispatchEvent(new Event('updatefound'));
    return worker;
  }
}

class FakeContainer extends EventTarget {
  controller: object | null;
  readonly registration = new FakeRegistration();
  readonly register = vi.fn(() => Promise.resolve(this.registration));
  constructor(inUse: boolean) {
    super();
    this.controller = inUse ? {} : null;
  }
  takeOver(): void {
    this.controller = {};
    this.dispatchEvent(new Event('controllerchange'));
  }
}

async function registered(inUse: boolean) {
  const container = new FakeContainer(inUse);
  const reload = vi.fn();
  render(<UpdateBar />);
  await act(() => registerServiceWorker(container as unknown as ServiceWorkerContainer, reload));
  return { container, reload, registration: container.registration };
}

afterEach(() => {
  act(() => offerUpdate(null));
  vi.useRealTimers();
});

describe('a new version', () => {
  it('is installed for next time on a first visit, without a word', async () => {
    const { container, reload, registration } = await registered(false);
    expect(container.register).toHaveBeenCalledWith('/sw.js', { scope: '/' });
    act(() => registration.found().install());
    act(() => container.takeOver());
    expect(screen.getByTestId('update-bar').textContent).toBe('');
    expect(reload).not.toHaveBeenCalled();
  });

  it('shows "A new version is ready · Reload" once it has installed, and reloads only when tapped', async () => {
    const { container, reload, registration } = await registered(true);
    const worker = registration.found();
    expect(screen.getByTestId('update-bar').textContent).toBe('');
    act(() => worker.install());
    const bar = screen.getByTestId('update-bar');
    expect(bar.getAttribute('aria-live')).toBe('polite');
    expect(bar.textContent).toBe('A new version is ready · Reload');
    expect(reload).not.toHaveBeenCalled();
    expect(worker.postMessage).not.toHaveBeenCalled();

    await userEvent.click(screen.getByRole('button', { name: 'Reload' }));
    expect(worker.postMessage).toHaveBeenCalledWith({ type: 'SKIP_WAITING' });
    expect(screen.getByRole('button', { name: 'Reloading…' })).toHaveProperty('disabled', true);
    act(() => container.takeOver());
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('is offered when it was already waiting as the page opened', async () => {
    const container = new FakeContainer(true);
    const waiting = new FakeWorker();
    container.registration.waiting = waiting;
    render(<UpdateBar />);
    await act(() => registerServiceWorker(container as unknown as ServiceWorkerContainer, vi.fn()));
    await userEvent.click(screen.getByRole('button', { name: 'Reload' }));
    expect(waiting.postMessage).toHaveBeenCalledWith({ type: 'SKIP_WAITING' });
  });

  it('opened in another tab, is offered here too, still without reloading by itself', async () => {
    const { container, reload } = await registered(true);
    act(() => container.takeOver());
    expect(reload).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: 'Reload' }));
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('reloads anyway if the new version doesn’t take over within a few seconds', async () => {
    const { reload, registration } = await registered(true);
    act(() => registration.found().install());
    vi.useFakeTimers();
    act(() => screen.getByRole('button', { name: 'Reload' }).click());
    expect(reload).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(4000));
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('is looked for again whenever the app comes back on screen', () => {
    const registration = { update: vi.fn(() => Promise.resolve()) };
    checkForUpdatesWhenShown(registration as unknown as ServiceWorkerRegistration);
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    expect(registration.update).toHaveBeenCalledTimes(1);
  });

  it('leaves the site working where there’s no service worker', async () => {
    expect(await registerServiceWorker(undefined)).toBeNull();
    const container = new FakeContainer(false);
    container.register.mockImplementation(() => Promise.reject(new Error('blocked')));
    expect(await registerServiceWorker(container as unknown as ServiceWorkerContainer)).toBeNull();
  });
});

describe('offline', () => {
  it('says so under the nav, with the number to book by phone, and goes when the connection is back', async () => {
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    const onLine = vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    renderApp('/');
    const notice = screen.getByTestId('offline-notice');
    expect(notice.getAttribute('aria-live')).toBe('polite');
    expect(notice.textContent).toBe('');
    onLine.mockReturnValue(false);
    act(() => {
      window.dispatchEvent(new Event('offline'));
    });
    expect(notice.textContent).toBe("You're offline. To book, call the shop: (442) 341-3053");
    expect(notice.querySelector('a')?.getAttribute('href')).toBe('tel:+14423413053');
    onLine.mockReturnValue(true);
    act(() => {
      window.dispatchEvent(new Event('online'));
    });
    expect(notice.textContent).toBe('');
  });

  it('has a page of its own for pages the app doesn’t keep, with the shop’s number to call', () => {
    const page = new DOMParser().parseFromString(offlineHtml, 'text/html');
    expect(page.querySelector('h1')?.textContent).toBe("You're offline.");
    expect(page.querySelector('.lead')?.textContent).toBe(`To book, call the shop: ${FALLBACK_SHOP.phone.display}`);
    const calls = [...page.querySelectorAll('a[href^="tel:"]')].map((a) => a.getAttribute('href'));
    expect(calls).toEqual([`tel:${FALLBACK_SHOP.phone.e164}`, `tel:${FALLBACK_SHOP.phone.e164}`]);
    // A way on: try again, or the home page, which opens offline.
    expect(page.querySelector('a[href=""]')?.textContent).toBe('Try again');
    expect(page.querySelector('a[href="/"]')).not.toBeNull();
    // The shop's Privacy Policy, which opens offline too (src/sw/routes.ts).
    expect(page.querySelector('a[href="/privacy"]')?.textContent).toBe('Privacy Policy');
    // Nothing from the network: everything it needs is in the page, or kept with it.
    expect(offlineHtml).not.toMatch(/https?:\/\//);
    expect([...page.querySelectorAll('[src]')].map((e) => e.getAttribute('src'))).toEqual(['/icon-192.png']);
  });
});
