// What this computer is called in the app's list of computers signed in: "Chrome on Mac",
// "Edge on Windows", "Safari on iPad", from what the browser says it is.

import { detectPlatform } from '../../pwa/platform';

const BROWSER_NAMES = {
  safari: 'Safari',
  chrome: 'Chrome',
  edge: 'Edge',
  firefox: 'Firefox',
  samsung: 'Samsung Internet',
  inApp: 'A browser',
  other: 'A browser',
} as const;

function system(userAgent: string, maxTouchPoints: number): string | null {
  if (/iPad/.test(userAgent) || (/Macintosh/.test(userAgent) && maxTouchPoints > 1)) return 'iPad';
  if (/iPhone|iPod/.test(userAgent)) return 'iPhone';
  if (/Android/.test(userAgent)) return /Mobile/.test(userAgent) ? 'Android phone' : 'Android tablet';
  if (/CrOS/.test(userAgent)) return 'Chromebook';
  if (/Windows/.test(userAgent)) return 'Windows';
  if (/Macintosh|Mac OS X/.test(userAgent)) return 'Mac';
  if (/Linux/.test(userAgent)) return 'Linux';
  return null;
}

export function computerName(userAgent: string, maxTouchPoints = 0): string {
  const browser = BROWSER_NAMES[detectPlatform(userAgent, maxTouchPoints).browser];
  const on = system(userAgent, maxTouchPoints);
  if (!on) return browser === 'A browser' ? 'Computer' : browser;
  return `${browser} on ${on}`;
}

export function thisComputerName(): string {
  return computerName(navigator.userAgent, navigator.maxTouchPoints ?? 0);
}
