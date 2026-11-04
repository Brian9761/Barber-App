// What every end-to-end test shares: no console errors (checked after each
// test), an address and a phone number of its own (the server limits bookings
// per network and per number), axe-core, screenshots that also check the page
// fits the screen, and the switches serve.ts offers under /__e2e/.

import { createHash, randomBytes } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import AxeBuilder from '@axe-core/playwright';
import { test as base, expect, type APIRequestContext, type Locator, type Page, type TestInfo } from '@playwright/test';

export { expect };

/** Where the screenshots go: E2E_SHOTS_DIR, or test-results/shots. */
export const SHOTS_DIR = resolve(process.env.E2E_SHOTS_DIR || join('test-results', 'shots'));

/** What the browser logs as errors, less the lines a test expects (its own line for a 409 the page handles, say). */
export class ConsoleWatch {
  readonly errors: string[] = [];
  private readonly allowed: RegExp[] = [];

  constructor(page: Page) {
    page.on('console', (message) => {
      if (message.type() === 'error') this.errors.push(message.text());
    });
    page.on('pageerror', (error) => this.errors.push(`Uncaught: ${error.message}`));
  }

  /** An error this test expects, like the browser's line for a 409 the page handles. */
  allow(pattern: RegExp): void {
    this.allowed.push(pattern);
  }

  unexpected(): string[] {
    return this.errors.filter((text) => !this.allowed.some((pattern) => pattern.test(text)));
  }
}

function hashNumber(text: string, modulo: number): number {
  return createHash('sha256').update(text).digest().readUInt32BE(0) % modulo;
}

function testKey(testInfo: TestInfo): string {
  return `${testInfo.project.name}|${testInfo.titlePath.join('|')}|${testInfo.retry}|${process.pid}`;
}

interface Fixtures {
  /** The browser's console, checked for errors after the test. */
  browserConsole: ConsoleWatch;
  /** A US mobile number no other test uses. */
  phone: string;
}

export const test = base.extend<Fixtures>({
  // Each test books from an address of its own: the server allows 5 bookings an hour per network.
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use, testInfo) => {
    const n = hashNumber(testKey(testInfo), 250 * 250);
    await use({ ...extraHTTPHeaders, 'x-real-ip': `10.${Math.floor(n / 250) + 1}.${(n % 250) + 1}.7` });
  },
  browserConsole: [
    async ({ page }, use) => {
      const watch = new ConsoleWatch(page);
      await use(watch);
      expect(watch.unexpected(), 'nothing is logged as an error in the browser').toEqual([]);
    },
    { auto: true },
  ],
  phone: async ({}, use, testInfo) => {
    const n = hashNumber(testKey(testInfo), 9000) + 1000;
    await use(`(760) 555-${n}`);
  },
});

/**
 * Fails on any serious or critical accessibility problem axe-core finds on the page as it is now.
 * The nav's "Izzy Clipz" wordmark is left out: it's the shop's logotype (aria-hidden; the link is
 * named "Izzy Clipz home"), which WCAG 1.4.3 exempts from contrast, in the app's own red for ink
 * (Theme.hotRed). axe measures it against whatever happens to be scrolled under the see-through nav.
 */
export async function expectAccessible(page: Page, what: string): Promise<void> {
  const results = await new AxeBuilder({ page }).exclude('.wordmark').analyze();
  const serious = results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.help} at ${v.nodes.map((n) => n.target.join(' ')).slice(0, 4).join(' | ')}`);
  expect(serious, `axe-core on ${what}`).toEqual([]);
}

/** Loads every photo now (they're lazy below the fold) and waits for them and the fonts. */
export async function settle(page: Page): Promise<void> {
  await page.evaluate(async () => {
    const images = Array.from(document.images);
    for (const image of images) image.loading = 'eager';
    // decode() waits until each photo has loaded and can be painted.
    await Promise.all(images.map((image) => image.decode().catch(() => undefined)));
    await document.fonts.ready;
  });
}

/** Nothing sticks out sideways: the page never scrolls left and right. */
export async function expectFits(page: Page, what: string): Promise<void> {
  const overflow = await page.evaluate(() => {
    const width = document.documentElement.clientWidth;
    // Inside a box that clips or scrolls (a photo, say), sticking out of that box is fine.
    const clipped = (element: Element): boolean => {
      for (let parent = element.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
        if (getComputedStyle(parent).overflowX !== 'visible') return true;
      }
      return false;
    };
    const wider = Array.from(document.querySelectorAll('body *'))
      .filter((element) => element.getBoundingClientRect().right > width + 0.5)
      .filter((element) => !element.closest('.visually-hidden, .skip-link') && !clipped(element))
      .slice(0, 5)
      .map((element) => `${element.tagName.toLowerCase()}.${element.className}`);
    // On a phone, words never touch the screen's edges: the page keeps its side margins.
    const margin = width < 600 ? 12 : 0;
    const tight = Array.from(document.querySelectorAll('main *'))
      .filter((element) => Array.from(element.childNodes).some((node) => node.nodeType === Node.TEXT_NODE && node.textContent?.trim()))
      .filter((element) => !element.closest('.visually-hidden, [aria-hidden="true"]') && !clipped(element))
      .filter((element) => {
        const box = element.getBoundingClientRect();
        return box.width > 0 && box.height > 0 && (box.left < margin || box.right > width - margin);
      })
      .slice(0, 5)
      .map((element) => `${element.tagName.toLowerCase()}.${element.className}: ${element.textContent?.trim().slice(0, 40)}`);
    return { scrollWidth: document.documentElement.scrollWidth, width, wider, tight };
  });
  expect(overflow.wider, `${what}: nothing wider than the screen`).toEqual([]);
  expect(overflow.scrollWidth, `${what}: no sideways scrolling`).toBeLessThanOrEqual(overflow.width);
  expect(overflow.tight, `${what}: text keeps clear of the screen's edges`).toEqual([]);
}

/** A full-page screenshot, named for the screen size: "desktop-03-barbers.png". Checks the page fits, too. */
export async function screenshot(page: Page, testInfo: TestInfo, name: string, options: { fullPage?: boolean } = {}): Promise<void> {
  mkdirSync(SHOTS_DIR, { recursive: true });
  const fullPage = options.fullPage ?? true;
  await settle(page);
  await expectFits(page, name);
  // From the top, so the sticky nav and summary are where a visitor first sees them.
  const scrolled = fullPage ? await page.evaluate(() => window.scrollY) : 0;
  if (scrolled) await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: join(SHOTS_DIR, `${testInfo.project.name}-${name}.png`), fullPage, animations: 'disabled' });
  if (scrolled) await page.evaluate((y) => window.scrollTo(0, y), scrolled);
}

export function isPhone(testInfo: TestInfo): boolean {
  return testInfo.project.name === 'phone';
}

// ------------------------------------------------------------ serve.ts switches

/** Live reviews from Google and Yelp (the server's own fixtures), or none. */
export async function setLiveReviews(request: APIRequestContext, live: boolean): Promise<void> {
  const response = await request.post('/__e2e/reviews', { data: { live } });
  expect(response.ok()).toBe(true);
}

/** The shop's no-show protection (a card on file to book), with a stand-in for Stripe. */
export async function setProtection(request: APIRequestContext, on: boolean): Promise<void> {
  const response = await request.post('/__e2e/protection', { data: { on } });
  expect(response.ok()).toBe(true);
}

// --------------------------------------------------------------- Booking steps

/** "Step 2 of 5" and the step's question. */
export async function expectStep(page: Page, number: number, title: string): Promise<void> {
  await expect(page.getByTestId('step-count')).toHaveText(`Step ${number} of 5`);
  await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible();
  await expect(page.getByRole('main').getByRole('button', { name: 'Back', exact: true })).toBeVisible();
}

/** The time step's open times for the picked day. */
export function timeChips(page: Page): Locator {
  return page.locator('button.time-chip');
}

/** The time step's first open time (the first open day is picked to start with). */
export async function firstTime(page: Page): Promise<Locator> {
  const chip = timeChips(page).first();
  await expect(chip).toBeVisible();
  return chip;
}

export interface Client {
  name: string;
  phone: string;
  email?: string;
  note?: string;
}

/** The details step's fields, by their labels. */
export function detailsFields(page: Page) {
  return {
    name: page.getByRole('textbox', { name: 'Name', exact: true }),
    phone: page.getByRole('textbox', { name: 'Mobile number' }),
    email: page.getByRole('textbox', { name: /^Email/ }),
    note: page.getByRole('textbox', { name: /^Note for your barber/ }),
    remember: page.getByRole('checkbox', { name: 'Remember me on this computer' }),
  };
}

export async function fillDetails(page: Page, client: Client): Promise<void> {
  const fields = detailsFields(page);
  await fields.name.fill(client.name);
  await fields.phone.fill(client.phone);
  if (client.email !== undefined) await fields.email.fill(client.email);
  if (client.note !== undefined) await fields.note.fill(client.note);
}

/** The appointments this browser keeps (id and manage token), as My appointments reads them. */
export async function storedAppointments(page: Page): Promise<{ id: string; manageToken: string; appointment: { status: string; start: string; barberName: string } }[]> {
  return page.evaluate(() => JSON.parse(window.localStorage.getItem('izzy.appointments.v1') ?? '[]'));
}

/** Presses Tab until `target` has focus (and checks the focus ring shows), like someone without a mouse. */
export async function tabTo(page: Page, target: Locator, maxPresses = 80): Promise<void> {
  await expect(target).toBeVisible();
  for (let i = 0; i < maxPresses; i += 1) {
    if (await target.evaluate((element) => element === document.activeElement)) {
      await expect(target, 'the focus ring shows').toHaveCSS('outline-style', 'solid');
      return;
    }
    await page.keyboard.press('Tab');
  }
  throw new Error(`Tab never reached ${String(target)}`);
}

/** A manage token like the apps and the site make: 32 random bytes in base64url. */
export function manageToken(): string {
  return randomBytes(32).toString('base64url');
}

/** An .ics file's lines as written before folding at 75 octets. */
export function unfoldIcs(text: string): string {
  return text.replace(/\r\n[ \t]/g, '');
}

/** "20261105T183000Z", as the .ics file writes a time. */
export function icsTime(iso: string): string {
  return new Date(iso).toISOString().replace(/\.\d{3}Z$/, 'Z').replace(/[-:]/g, '');
}
