import { afterEach, describe, expect, it, vi } from 'vitest';
import { displayMode, installOffer, USER_AGENTS } from '../test/pwa';
import { countVisit, dismissHint, hintDismissed, INSTALL_HINT_KEY, showInstallHint, type HintFacts } from './installHint';
import { forgetInstallPrompt, listenForInstallPrompt, promptInstall } from './installPrompt';
import { openOtherSitesOutside } from './externalLinks';
import { detectPlatform, deviceWord, isStandalone, markStandalone } from './platform';

// What the Get the app page and the install hint decide from: the device and browser, whether
// the site is already open as the app, and the browser's own offer to install it.

afterEach(() => {
  forgetInstallPrompt();
});

describe('the device and browser', () => {
  it('knows iPhones, iPads, Android phones and computers, and the browser on each', () => {
    expect(detectPlatform(USER_AGENTS.iphoneSafari)).toEqual({ device: 'iphone', browser: 'safari', windows: false });
    expect(detectPlatform(USER_AGENTS.iphoneChrome)).toEqual({ device: 'iphone', browser: 'chrome', windows: false });
    expect(detectPlatform(USER_AGENTS.iphoneInstagram)).toEqual({ device: 'iphone', browser: 'inApp', windows: false });
    expect(detectPlatform(USER_AGENTS.androidChrome)).toEqual({ device: 'android', browser: 'chrome', windows: false });
    expect(detectPlatform(USER_AGENTS.androidSamsung)).toEqual({ device: 'android', browser: 'samsung', windows: false });
    expect(detectPlatform(USER_AGENTS.androidFirefox)).toEqual({ device: 'android', browser: 'firefox', windows: false });
    expect(detectPlatform(USER_AGENTS.windowsEdge)).toEqual({ device: 'computer', browser: 'edge', windows: true });
    expect(detectPlatform(USER_AGENTS.macChrome)).toEqual({ device: 'computer', browser: 'chrome', windows: false });
    expect(detectPlatform(USER_AGENTS.windowsFirefox)).toEqual({ device: 'computer', browser: 'firefox', windows: true });
    expect(detectPlatform(USER_AGENTS.macFirefox)).toEqual({ device: 'computer', browser: 'firefox', windows: false });
    expect(detectPlatform(USER_AGENTS.linuxFirefox)).toEqual({ device: 'computer', browser: 'firefox', windows: false });
  });

  it('tells an iPad, which says it’s a Mac, by its touch screen', () => {
    expect(detectPlatform(USER_AGENTS.ipadSafari, 5)).toEqual({ device: 'iphone', browser: 'safari', windows: false });
    expect(detectPlatform(USER_AGENTS.ipadSafari, 0)).toEqual({ device: 'computer', browser: 'safari', windows: false });
  });

  it('names the device in a sentence: this phone, this iPad, this tablet, this computer', () => {
    expect(deviceWord(USER_AGENTS.iphoneSafari)).toBe('phone');
    expect(deviceWord(USER_AGENTS.iphoneInstagram)).toBe('phone');
    expect(deviceWord(USER_AGENTS.androidChrome)).toBe('phone');
    expect(deviceWord(USER_AGENTS.androidFirefox)).toBe('phone');
    expect(deviceWord(USER_AGENTS.ipadSafari, 5)).toBe('iPad');
    expect(deviceWord(USER_AGENTS.androidTablet)).toBe('tablet');
    expect(deviceWord(USER_AGENTS.ipadSafari, 0)).toBe('computer');
    expect(deviceWord(USER_AGENTS.windowsEdge)).toBe('computer');
    expect(deviceWord(USER_AGENTS.macChrome)).toBe('computer');
  });
});

describe('open as the app', () => {
  it('is known from the display mode, or from Safari’s own flag on iPhones', () => {
    displayMode(false);
    expect(isStandalone()).toBe(false);
    displayMode(true);
    expect(isStandalone()).toBe(true);
    // Safari on an iPhone, opened from the Home Screen.
    const iphoneApp = { navigator: { standalone: true }, matchMedia: () => ({ matches: false }) } as unknown as Window;
    expect(isStandalone(iphoneApp)).toBe(true);
  });

  it('marks the page for the styles that only apply in the app', () => {
    displayMode(true);
    const root = document.createElement('html');
    markStandalone(root);
    expect(root.classList.contains('is-standalone')).toBe(true);
  });

  it('is never assumed where the browser can’t tell', () => {
    vi.stubGlobal('matchMedia', undefined);
    expect(isStandalone()).toBe(false);
  });
});

describe('the browser’s offer to install', () => {
  it('is kept for the page’s own button, instead of the browser’s bar, and shows its question when tapped', async () => {
    const stop = listenForInstallPrompt();
    const offer = installOffer('accepted');
    window.dispatchEvent(offer);
    expect(offer.defaultPrevented).toBe(true);
    expect(await promptInstall()).toBe('accepted');
    expect(offer.prompt).toHaveBeenCalledTimes(1);
    // Each offer can be shown once.
    expect(await promptInstall()).toBe('unavailable');
    stop();
  });

  it('says when there’s no offer, so the page shows the steps', async () => {
    expect(await promptInstall()).toBe('unavailable');
  });

  it('can be said no to', async () => {
    const stop = listenForInstallPrompt();
    window.dispatchEvent(installOffer('dismissed'));
    expect(await promptInstall()).toBe('dismissed');
    expect(hintDismissed()).toBe(false);
    stop();
  });

  it('closes the Add to Home Screen bar for good once installed, from the page’s button or the browser’s own', async () => {
    const stop = listenForInstallPrompt();
    window.dispatchEvent(installOffer('accepted'));
    expect(await promptInstall()).toBe('accepted');
    expect(hintDismissed()).toBe(true);
    expect(JSON.parse(localStorage.getItem(INSTALL_HINT_KEY)!)).toMatchObject({ dismissed: true, installed: true });

    localStorage.clear();
    window.dispatchEvent(new Event('appinstalled'));
    expect(hintDismissed()).toBe(true);
    stop();
  });
});

describe('the Add to Home Screen bar', () => {
  const phone: HintFacts = { device: 'iphone', standalone: false, dismissed: false, visits: 1, booked: false, pathname: '/' };

  it('shows on phones after the first booking, or from the second visit', () => {
    expect(showInstallHint(phone)).toBe(false);
    expect(showInstallHint({ ...phone, visits: 2 })).toBe(true);
    expect(showInstallHint({ ...phone, booked: true })).toBe(true);
    expect(showInstallHint({ ...phone, device: 'android', visits: 3 })).toBe(true);
  });

  it('never shows on computers, in the app itself, or once closed', () => {
    expect(showInstallHint({ ...phone, visits: 2, device: 'computer' })).toBe(false);
    expect(showInstallHint({ ...phone, visits: 2, standalone: true })).toBe(false);
    expect(showInstallHint({ ...phone, visits: 2, dismissed: true })).toBe(false);
  });

  it('stays out of the way on Get the app and while booking, but shows once booked', () => {
    expect(showInstallHint({ ...phone, booked: true, pathname: '/app' })).toBe(false);
    expect(showInstallHint({ ...phone, booked: true, pathname: '/book/time' })).toBe(false);
    expect(showInstallHint({ ...phone, booked: true, pathname: '/book/confirmed' })).toBe(true);
  });

  it('counts a visit once however many pages it opens, and a new tab as a new visit', () => {
    expect(countVisit()).toBe(1);
    expect(countVisit()).toBe(1);
    sessionStorage.clear(); // the tab closed
    expect(countVisit()).toBe(2);
  });

  it('stays closed once closed', () => {
    expect(hintDismissed()).toBe(false);
    dismissHint(new Date('2026-11-04T20:00:00Z'));
    expect(hintDismissed()).toBe(true);
    expect(JSON.parse(localStorage.getItem('izzy.installHint.v1')!)).toEqual({ dismissed: true, at: '2026-11-04T20:00:00.000Z' });
  });
});

describe('links to other sites, in the app', () => {
  function click(link: HTMLAnchorElement): void {
    // jsdom can't follow links: the test stops each click after the page has had its say.
    const stop = (event: Event) => event.preventDefault();
    window.addEventListener('click', stop);
    link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, button: 0 }));
    window.removeEventListener('click', stop);
  }

  function link(href: string): HTMLAnchorElement {
    const a = document.createElement('a');
    a.href = href;
    a.textContent = 'link';
    document.body.append(a);
    return a;
  }

  it('open outside the app: maps, Instagram, reviews', () => {
    const stop = openOtherSitesOutside(document, () => true);
    for (const href of ['https://maps.apple.com/?daddr=1919+Mission+Ave', 'https://www.instagram.com/izzy_clipz_barbershop_/']) {
      const a = link(href);
      click(a);
      expect(a.target, href).toBe('_blank');
      expect(a.rel, href).toBe('noopener noreferrer');
    }
    stop();
  });

  it('leave calls, the site’s own pages and the browser tab alone', () => {
    const stop = openOtherSitesOutside(document, () => true);
    for (const href of ['tel:+14423413053', `${window.location.origin}/services`]) {
      const a = link(href);
      click(a);
      expect(a.target, href).toBe('');
    }
    stop();
    const inTab = openOtherSitesOutside(document, () => false);
    const a = link('https://www.instagram.com/izzy_clipz_barbershop_/');
    click(a);
    expect(a.target).toBe('');
    inTab();
  });
});
