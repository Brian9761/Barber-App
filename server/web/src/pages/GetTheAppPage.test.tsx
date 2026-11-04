import { act, fireEvent, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { saveAppointment } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { forgetInstallPrompt, listenForInstallPrompt } from '../pwa/installPrompt';
import { fixtureAppointment, mockApi, renderApp, reviewsUnavailable } from '../test/api';
import { displayMode, installOffer, USER_AGENTS } from '../test/pwa';

// "Get the app": the steps for the visitor's own device, the others one tap away, the
// browser's own Install button where it has one, a QR code on computers, and "You're using
// the app" once it's on the Home Screen.

/** What the browser says it is, and how many fingers its screen takes (jsdom has no touch screen). */
function on(userAgent: string, maxTouchPoints = 0) {
  vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(userAgent);
  Object.defineProperty(navigator, 'maxTouchPoints', { configurable: true, get: () => maxTouchPoints });
}

const stepsText = (device: string) => screen.getByTestId(`${device}-steps`).textContent ?? '';

afterEach(() => {
  forgetInstallPrompt();
  delete (navigator as { maxTouchPoints?: number }).maxTouchPoints;
  delete (navigator as { clipboard?: unknown }).clipboard;
});

describe('Get the app', () => {
  it('opens on an iPhone’s steps on an iPhone: Safari, Share, Add to Home Screen, Add', () => {
    on(USER_AGENTS.iphoneSafari);
    renderApp('/app');
    expect(screen.getByRole('heading', { level: 1, name: 'Get the app.' })).toBeTruthy();
    expect(screen.getByRole('radio', { name: 'iPhone' })).toHaveProperty('checked', true);
    const steps = within(screen.getByTestId('iphone-steps'));
    expect(steps.getAllByRole('listitem').map((li) => li.querySelector('.install-step__text')?.textContent)).toEqual([
      'Open this page in Safari.',
      'Tap the Share button.',
      'Scroll down and tap Add to Home Screen.',
      'Tap Add.',
    ]);
    expect(stepsText('iphone')).toContain("Don't see it? Tap ⋯ first, then Share.");
    // Pictures of what to tap, which the words already say.
    expect(screen.getByTestId('iphone-steps').querySelectorAll('svg.drawing[aria-hidden="true"]')).toHaveLength(3);
    expect(screen.queryByTestId('phone-code')).toBeNull();
    expect(screen.queryByTestId('install-now')).toBeNull();
  });

  it('has the other devices one tap away', async () => {
    on(USER_AGENTS.iphoneSafari);
    renderApp('/app');
    await userEvent.click(screen.getByRole('radio', { name: 'Android' }));
    expect(stepsText('android')).toContain('Tap Install app.');
    expect(screen.queryByTestId('iphone-steps')).toBeNull();
    await userEvent.click(screen.getByRole('radio', { name: 'Computer' }));
    expect(stepsText('computer')).toContain('Click the install button at the right end of the address bar.');
  });

  it('asks to open the page in Safari first from inside Instagram, and can copy the link', async () => {
    on(USER_AGENTS.iphoneInstagram);
    const writeText = vi.fn(() => Promise.resolve());
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
    renderApp('/app');
    const notice = screen.getByTestId('open-in-safari');
    expect(notice.textContent).toContain('Open this page in Safari first');
    fireEvent.click(within(notice).getByRole('button', { name: 'Copy the link' }));
    expect(await within(notice).findByText('Copied. Open Safari and paste it in the address bar.')).toBeTruthy();
    expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/app`);
  });

  it('asks to open the page in Chrome first from inside another app on Android', () => {
    on('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36 Instagram 380.0.0.29.88 Android');
    renderApp('/app');
    expect(screen.getByRole('radio', { name: 'Android' })).toHaveProperty('checked', true);
    expect(screen.getByTestId('open-in-chrome').textContent).toContain('Open this page in Chrome first');
    expect(within(screen.getByTestId('open-in-chrome')).getByRole('button', { name: 'Copy the link' })).toBeTruthy();
  });

  it('on Android, installs with the browser’s own question when it offers one, with Chrome’s menu as the other way', async () => {
    on(USER_AGENTS.androidChrome);
    const stop = listenForInstallPrompt();
    renderApp('/app');
    expect(screen.queryByTestId('install-now')).toBeNull();
    expect(screen.getByRole('heading', { level: 2, name: 'On an Android phone' })).toBeTruthy();

    const offer = installOffer('accepted');
    act(() => {
      window.dispatchEvent(offer);
    });
    expect(screen.getByRole('heading', { level: 2, name: 'Or use Chrome’s menu' })).toBeTruthy();
    await userEvent.click(within(screen.getByTestId('install-now')).getByRole('button', { name: 'Install Izzy Clipz' }));
    expect(offer.prompt).toHaveBeenCalledTimes(1);
    expect((await screen.findByTestId('installed')).textContent).toBe('Izzy Clipz is installed.Find it on your Home Screen.');
    expect(screen.queryByTestId('install-now')).toBeNull();
    stop();
  });

  it('says it’s fine to say no, and keeps the steps', async () => {
    on(USER_AGENTS.windowsEdge);
    const stop = listenForInstallPrompt();
    renderApp('/app');
    act(() => {
      window.dispatchEvent(installOffer('dismissed'));
    });
    await userEvent.click(screen.getByRole('button', { name: 'Install Izzy Clipz' }));
    expect(await screen.findByText('No problem. You can install it any time with the steps below.')).toBeTruthy();
    expect(stepsText('computer')).toContain('Click Install.');
    stop();
  });

  it('only offers the browser’s Install button in this device’s own steps', async () => {
    on(USER_AGENTS.androidChrome);
    const stop = listenForInstallPrompt();
    renderApp('/app');
    act(() => {
      window.dispatchEvent(installOffer('accepted'));
    });
    expect(screen.getByTestId('install-now')).toBeTruthy();
    await userEvent.click(screen.getByRole('radio', { name: 'iPhone' }));
    expect(screen.queryByTestId('install-now')).toBeNull();
    stop();
  });

  it('on a computer, shows a QR code that opens this page on a phone, at this site’s own address', () => {
    on(USER_AGENTS.macChrome);
    renderApp('/app');
    expect(screen.getByRole('radio', { name: 'Computer' })).toHaveProperty('checked', true);
    const code = screen.getByTestId('phone-code');
    const address = `${window.location.origin}/app`;
    const qr = within(code).getByRole('img', { name: `QR code that opens ${address.replace(/^https?:\/\//, '')} on your phone` });
    expect(qr.getAttribute('data-qr-text')).toBe(address);
    expect(qr.querySelector('path')?.getAttribute('d')).toMatch(/^M\d+ \d+h1v1h-1z/);
    expect(screen.getByTestId('phone-code-url').textContent).toBe(address.replace(/^https?:\/\//, ''));
  });

  it('suggests Chrome or Edge in a browser that can’t install, and Add to Dock in Safari on a Mac', () => {
    on(USER_AGENTS.windowsFirefox);
    const { unmount } = renderApp('/app');
    expect(screen.getByTestId('use-chrome-or-edge').textContent).toBe("This browser can't install apps. Use Chrome or Edge, like this:");
    unmount();
    on(USER_AGENTS.ipadSafari, 0);
    renderApp('/app');
    expect(screen.getByTestId('use-chrome-or-edge').textContent).toContain('choose File, then Add to Dock');
  });

  it('says "You’re using the app" when it’s open as the app, without the steps', () => {
    on(USER_AGENTS.iphoneSafari);
    displayMode(true);
    renderApp('/app');
    expect(screen.getByTestId('using-the-app').textContent).toContain("You're using the app.");
    expect(screen.queryByRole('radio')).toBeNull();
    expect(screen.queryByTestId('iphone-steps')).toBeNull();
  });
});

describe('in the nav and footer', () => {
  it('is "Get the app" in both, and leaves the nav once it’s the app', () => {
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    const { unmount } = renderApp('/visit');
    expect(within(screen.getByRole('navigation', { name: 'Izzy Clipz' })).getByRole('link', { name: 'Get the app' }).getAttribute('href')).toBe('/app');
    expect(within(screen.getByRole('navigation', { name: 'Site directory' })).getByRole('link', { name: 'Get the app' }).getAttribute('href')).toBe('/app');
    unmount();
    displayMode(true);
    renderApp('/visit');
    expect(within(screen.getByRole('navigation', { name: 'Izzy Clipz' })).queryByRole('link', { name: 'Get the app' })).toBeNull();
  });
});

describe('the Add to Home Screen bar', () => {
  it('shows on a phone’s second visit, links to the steps, and stays gone once closed', async () => {
    on(USER_AGENTS.androidChrome);
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    localStorage.setItem('izzy.visits.v1', '1');
    const { unmount } = renderApp('/visit');
    const hint = screen.getByTestId('install-hint');
    expect(hint.textContent).toBe('Add Izzy Clipz to your Home Screen · How');
    expect(within(hint).getByRole('link', { name: 'How to add Izzy Clipz to your Home Screen' }).getAttribute('href')).toBe('/app');
    await userEvent.click(within(hint).getByRole('button', { name: 'Hide this' }));
    expect(screen.queryByTestId('install-hint')).toBeNull();
    unmount();
    sessionStorage.clear(); // another visit
    renderApp('/visit');
    expect(screen.queryByTestId('install-hint')).toBeNull();
  });

  it('shows after the first booking, not on the first visit before it', () => {
    on(USER_AGENTS.iphoneSafari);
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    const { unmount } = renderApp('/visit');
    expect(screen.queryByTestId('install-hint')).toBeNull();
    unmount();
    saveAppointment(fixtureAppointment, newToken());
    renderApp('/visit');
    expect(screen.getByTestId('install-hint')).toBeTruthy();
  });

  it('never shows on a computer or in the app', () => {
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    localStorage.setItem('izzy.visits.v1', '5');
    on(USER_AGENTS.macChrome);
    const { unmount } = renderApp('/visit');
    expect(screen.queryByTestId('install-hint')).toBeNull();
    unmount();
    on(USER_AGENTS.iphoneSafari);
    displayMode(true);
    renderApp('/visit');
    expect(screen.queryByTestId('install-hint')).toBeNull();
  });
});
