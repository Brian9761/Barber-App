import { useSyncExternalStore } from 'react';

// The visitor's device and browser, to show the right way to put Izzy Clipz on the
// Home Screen, and whether it's already open as an app.

/** iPhone also means iPad: the steps are the same there. */
export type Device = 'iphone' | 'android' | 'computer';

/** "inApp": a link opened inside another app (Instagram, Facebook, TikTok…), which can't install anything. */
export type Browser = 'safari' | 'chrome' | 'edge' | 'firefox' | 'samsung' | 'inApp' | 'other';

export interface Platform {
  device: Device;
  browser: Browser;
  /** A Windows computer: Firefox there can pin a site to the taskbar as an app. */
  windows: boolean;
}

const IN_APP = /FBAN|FBAV|FB_IAB|Instagram|Snapchat|musical_ly|BytedanceWebview|TikTok|Line\/|MicroMessenger/;

/** An iPad says it's a Mac, so a "Mac" with a touch screen (`maxTouchPoints` over 1) is an iPad. */
function isIPad(userAgent: string, maxTouchPoints: number): boolean {
  return /iPad/.test(userAgent) || (/Macintosh/.test(userAgent) && maxTouchPoints > 1);
}

/** The device and browser from what the browser says it is. */
export function detectPlatform(userAgent: string, maxTouchPoints = 0): Platform {
  const device: Device = /iPhone|iPod/.test(userAgent) || isIPad(userAgent, maxTouchPoints) ? 'iphone' : /Android/.test(userAgent) ? 'android' : 'computer';
  let browser: Browser = 'other';
  if (IN_APP.test(userAgent)) browser = 'inApp';
  else if (/Edg(e|A|iOS)?\//.test(userAgent)) browser = 'edge';
  else if (/SamsungBrowser\//.test(userAgent)) browser = 'samsung';
  else if (/Firefox\/|FxiOS\//.test(userAgent)) browser = 'firefox';
  else if (/OPR\/|OPiOS\/|Opera/.test(userAgent)) browser = 'other';
  else if (/CriOS\/|Chrome\/|Chromium\//.test(userAgent)) browser = 'chrome';
  else if (/Safari\//.test(userAgent) && /Version\//.test(userAgent)) browser = 'safari';
  return { device, browser, windows: device === 'computer' && /Windows NT/.test(userAgent) };
}

/** This visitor's device and browser. */
export function currentPlatform(): Platform {
  return detectPlatform(navigator.userAgent, navigator.maxTouchPoints ?? 0);
}

/** The visitor's device in a sentence: "Remember me on this phone", "This computer can forget…". */
export type DeviceWord = 'phone' | 'iPad' | 'tablet' | 'computer';

export function deviceWord(userAgent: string, maxTouchPoints = 0): DeviceWord {
  if (isIPad(userAgent, maxTouchPoints)) return 'iPad';
  if (/iPhone|iPod/.test(userAgent)) return 'phone';
  // Android phones say "Mobile"; Android tablets don't.
  if (/Android/.test(userAgent)) return /Mobile/.test(userAgent) ? 'phone' : 'tablet';
  return /Mobi/.test(userAgent) ? 'phone' : 'computer';
}

/** What to call this visitor's device: "phone", "iPad", "tablet" or "computer". */
export function thisDevice(): DeviceWord {
  return deviceWord(navigator.userAgent, navigator.maxTouchPoints ?? 0);
}

/** How the app can be open without the browser around it. */
const APP_MODES = ['standalone', 'fullscreen', 'minimal-ui', 'window-controls-overlay'] as const;

/** Whether the site is open as the app: from the Home Screen, or an installed app's own window. */
export function isStandalone(win: Window = window): boolean {
  if ((win.navigator as Navigator & { standalone?: boolean }).standalone === true) return true;
  if (typeof win.matchMedia !== 'function') return false;
  return APP_MODES.some((mode) => win.matchMedia(`(display-mode: ${mode})`).matches);
}

function subscribeToDisplayMode(listener: () => void): () => void {
  if (typeof window.matchMedia !== 'function') return () => undefined;
  const queries = APP_MODES.map((mode) => window.matchMedia(`(display-mode: ${mode})`));
  for (const query of queries) query.addEventListener?.('change', listener);
  return () => {
    for (const query of queries) query.removeEventListener?.('change', listener);
  };
}

/** Whether the site is open as the app, kept up to date (installing from Chrome moves the page into the app's window). */
export function useStandalone(): boolean {
  return useSyncExternalStore(subscribeToDisplayMode, () => isStandalone(), () => false);
}

/** Marks the page `is-standalone` while it's open as the app, for the styles that only apply then. */
export function markStandalone(root: HTMLElement = document.documentElement): () => void {
  const update = () => root.classList.toggle('is-standalone', isStandalone());
  update();
  return subscribeToDisplayMode(update);
}
