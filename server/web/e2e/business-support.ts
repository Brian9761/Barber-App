// What Izzy Clipz Business's end-to-end tests share: the owner key the test server was
// started with (e2e/serve.ts), the owner API with that key (as the iPhone app calls it),
// signing in on the website with a code from it, and the Business pages' own checks.

import type { APIRequestContext, Page, TestInfo } from '@playwright/test';
import { expect, isPhone } from './support.js';

/** The owner key e2e/serve.ts opens the owner routes with. */
export const OWNER_KEY = process.env.E2E_OWNER_KEY || 'e2e-owner-key-for-local-tests-only';

const KEY_HEADERS = { Authorization: `Bearer ${OWNER_KEY}` };

/** The owner API with the key, as the Business app on the iPhone calls it. */
export async function ownerCall<T>(request: APIRequestContext, method: 'GET' | 'POST' | 'PATCH' | 'DELETE', path: string, data?: unknown): Promise<T> {
  const response = await request.fetch(path, { method, headers: KEY_HEADERS, ...(data !== undefined ? { data } : {}) });
  const text = await response.text();
  expect(response.ok(), `${method} ${path}: ${response.status()} ${text}`).toBe(true);
  return (text ? JSON.parse(text) : undefined) as T;
}

/** A new sign-in code, as Settings → Use on a computer gets one in the app. */
export async function newCode(request: APIRequestContext): Promise<string> {
  return (await ownerCall<{ code: string }>(request, 'POST', '/api/owner/computer-codes')).code;
}

/** Signs this computer in on /business with a code from the app, typed as people do ("483 920"). */
export async function signInWithCode(page: Page, request: APIRequestContext): Promise<void> {
  const code = await newCode(request);
  await page.goto('/business');
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  await page.getByLabel('6-digit code').fill(`${code.slice(0, 3)} ${code.slice(3)}`);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page).toHaveURL(/\/business\/today$/);
  await expect(page.getByTestId('today-page')).toBeVisible();
}

/** The local nav's link to a page (on a phone, the tabs across the top). */
export function navLink(page: Page, name: 'Today' | 'Analytics' | 'Products' | 'Settings') {
  return page.getByRole('navigation', { name: 'Izzy Clipz Business' }).getByRole('link', { name, exact: true });
}

/** Sign out: in the local nav on a computer, in the black bar on a phone. */
export function signOutButton(page: Page, testInfo: TestInfo) {
  return isPhone(testInfo)
    ? page.locator('.biz-globalbar').getByRole('button', { name: 'Sign out' })
    : page.getByRole('navigation', { name: 'Izzy Clipz Business' }).getByRole('button', { name: 'Sign out' });
}

/** A tiny PNG (an 8×8 photo, red and blue), for the product photo: the page makes a JPEG of it. */
export const PHOTO_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAIklEQVR4nGO8LiLDAAMe1nvgbCYGHIB0CUZ5/xtUMgqnBAA2TAObCafr/gAAAABJRU5ErkJggg==',
  'base64',
);

/** Chrome's own reading of the Business manifest: it parses cleanly, and nothing stands in the way of installing it. */
export async function expectBusinessInstallable(page: Page, request: APIRequestContext): Promise<void> {
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/business/manifest.webmanifest');
  await expect(page.locator('link[rel="apple-touch-icon"]')).toHaveAttribute('href', '/business/apple-touch-icon.png');
  await expect(page.locator('meta[name="apple-mobile-web-app-title"]')).toHaveAttribute('content', 'IC Business');
  const response = await request.get('/business/manifest.webmanifest');
  expect(response.headers()['content-type']).toBe('application/manifest+json');
  const manifest = (await response.json()) as { icons: { src: string; sizes: string; purpose: string }[] } & Record<string, unknown>;
  expect(manifest).toMatchObject({
    id: '/business/',
    name: 'Izzy Clipz Business',
    short_name: 'IC Business',
    start_url: '/business/today?source=app',
    scope: '/business/',
    display: 'standalone',
  });
  // Every icon, the iPhone's included, is a PNG of the size it says.
  const icons = [...manifest.icons, { src: '/business/apple-touch-icon.png', sizes: '180x180' }];
  for (const icon of icons) {
    const png = await request.get(icon.src);
    expect(png.status(), icon.src).toBe(200);
    expect(png.headers()['content-type'], icon.src).toBe('image/png');
    const body = await png.body();
    expect(`${body.readUInt32BE(16)}x${body.readUInt32BE(20)}`, icon.src).toBe(icon.sizes);
  }
  await page.waitForFunction(() => Boolean(navigator.serviceWorker?.controller), null, { timeout: 30_000 });
  const cdp = await page.context().newCDPSession(page);
  const read = await cdp.send('Page.getAppManifest');
  expect(read.url).toBe(new URL('/business/manifest.webmanifest', page.url()).href);
  expect(read.errors).toEqual([]);
  expect((await cdp.send('Page.getInstallabilityErrors')).installabilityErrors).toEqual([]);
}
