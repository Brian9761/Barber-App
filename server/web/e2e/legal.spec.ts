import { mkdirSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import type { Locator, Page, TestInfo } from '@playwright/test';
import { navLink, signInWithCode } from './business-support.js';
import {
  controlledByWorker,
  detailsFields,
  expect,
  expectAccessible,
  expectFits,
  expectStep,
  fillDetails,
  firstTime,
  isDemo,
  isPhone,
  POLICY_STORAGE,
  settle,
  setLiveReviews,
  setProtection,
  SHOTS_DIR,
  siteTookOver,
  tabTo,
  test,
  watchOtherSites,
} from './support.js';

// The shop's four legal documents as pages (drafts until the shop publishes them), and what
// they say the website does, on the real site (playwright.config.ts) and the demo
// (playwright.demo.config.ts), at a computer's size and a phone's: every page's footer links
// them; Izzy Clipz Business does too, with its own skip link, titles and focus; booking says
// what it agrees to, the fee notice links its policy, and Your details says where the details
// go; Reviews shows Google's and only links to Yelp; Visit shows only the accessibility lines the
// owner confirmed, then asks people to call about getting in; and the browser keeps only what the
// Privacy Policy lists.
// Screenshots go to E2E_LEGAL_SHOTS_DIR (or with the others), named "<run>-legal-…".

const LEGAL_SHOTS = resolve(process.env.E2E_LEGAL_SHOTS_DIR || SHOTS_DIR);
/** axe-core's own script (the one @axe-core/playwright runs), for pages whose own scripts are off. */
const AXE_SOURCE = readFileSync(createRequire(import.meta.url).resolve('axe-core/axe.min.js'), 'utf8');
const YELP = 'https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside';

/** What the screen shows now, as a visitor sees it. */
async function view(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  mkdirSync(LEGAL_SHOTS, { recursive: true });
  await settle(page);
  await page.mouse.move(0, 0);
  await page.screenshot({ path: join(LEGAL_SHOTS, `${testInfo.project.name}-${name}.png`), animations: 'disabled' });
}

/** The whole page, from the top (and it fits the screen's width). */
async function whole(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  mkdirSync(LEGAL_SHOTS, { recursive: true });
  await settle(page);
  await expectFits(page, name);
  await page.mouse.move(0, 0);
  const scrolled = await page.evaluate(() => window.scrollY);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: join(LEGAL_SHOTS, `${testInfo.project.name}-${name}.png`), fullPage: true, animations: 'disabled' });
  await page.evaluate((y) => window.scrollTo(0, y), scrolled);
}

/** `element` at the top of the screen, below the nav. */
async function scrollToTop(element: Locator): Promise<void> {
  await element.evaluate((node) => node.scrollIntoView({ block: 'start' }));
}

/** The footer's policies, "Refunds" with them, in order. */
const FOOTER_POLICIES = ['Privacy Policy', 'Terms of Service', 'Cancellation & No-Show Policy', 'Refunds', 'Accessibility'];

/**
 * The footer's policies (the refund policy with them), who runs the shop and the copyright, at the
 * booking pages' size (17px, --text-body), never smaller (OWNER-CHECKLIST §3 item 20: "in text no
 * smaller than the booking text"), in the site's footer and in a policy's plain HTML alike.
 */
async function expectFooterAtBookingSize(page: Page, what: string): Promise<void> {
  const sizes = await page.getByRole('contentinfo').evaluate((footer) => {
    const size = (element: Element) => getComputedStyle(element).fontSize;
    const copyright = Array.from(footer.querySelectorAll('p')).find((p) => p.textContent?.startsWith('Copyright ©'));
    return {
      policies: Array.from(footer.querySelectorAll('nav[aria-label="Legal"] a')).map((a) => [a.textContent, size(a)]),
      operator: Array.from(footer.querySelectorAll('[data-testid="footer-operator"] p')).map(size),
      copyright: copyright ? size(copyright) : null,
    };
  });
  expect(sizes.policies, `${what}: the policies`).toEqual(FOOTER_POLICIES.map((name) => [name, '17px']));
  expect(sizes.operator.length, `${what}: who runs the shop`).toBeGreaterThan(0);
  expect(sizes.operator, `${what}: who runs the shop`).toEqual(sizes.operator.map(() => '17px'));
  expect(sizes.copyright, `${what}: the copyright`).toBe('17px');
}

const DOCS = [
  { path: '/privacy', heading: 'Privacy Policy', title: 'Privacy Policy', shot: '01-privacy', part: (page: Page) => page.getByRole('table').nth(1) },
  { path: '/terms', heading: 'Terms of Service', title: 'Terms of Service', shot: '02-terms', part: (page: Page) => page.getByRole('heading', { level: 2, name: '4. Prices and paying' }) },
  {
    path: '/cancellation-policy',
    heading: 'Cancellation & No-Show Policy',
    title: 'Cancellation & No-Show Policy',
    shot: '03-cancellation-policy',
    part: (page: Page) => page.getByRole('heading', { level: 2, name: 'Bookings with a card on file' }),
  },
  {
    path: '/accessibility',
    heading: 'Accessibility Statement',
    title: 'Accessibility',
    shot: '04-accessibility',
    part: (page: Page) => page.getByRole('heading', { level: 2, name: 'Other ways to book and get help' }),
  },
] as const;

const DRAFT = 'Draft: not in effect yet.';
const DRAFT_LINE = 'The shop will publish this when online booking opens.';
const DEMO_LINE = 'This is the demo version of the website.';

for (const doc of DOCS) {
  test(`${doc.path}: a draft that says so, with its sections, no placeholder showing, and nothing in the way`, async ({ page }, testInfo) => {
    const otherSites = watchOtherSites(page, testInfo);
    await page.goto(doc.path);
    // Its plain HTML first (tools/prerender.ts), then the site's own page in its place once the script runs.
    await siteTookOver(page);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(doc.heading);
    await expect(page.locator('h1')).toHaveCount(1);
    await expect(page).toHaveTitle(`${doc.title} · Izzy Clipz Barbershop`);
    const draft = page.getByTestId('legal-draft');
    await expect(draft).toContainText(DRAFT);
    await expect(draft).toContainText(DRAFT_LINE);
    if (isDemo(testInfo)) await expect(draft).toContainText(DEMO_LINE);
    else await expect(draft).not.toContainText('demo');
    await expect(page.getByTestId('legal-dates')).toContainText('Effective date: Not in effect yet');
    await expect(page.getByTestId('legal-dates')).toContainText('Last updated: Not in effect yet');
    // Every placeholder is a note of what the shop will add: no raw "[TO FILL IN", no checklist, no Markdown.
    const words = await page.getByTestId('legal-page').innerText();
    expect(words).not.toContain('TO FILL IN');
    expect(words).not.toContain('OWNER-CHECKLIST');
    expect(words).not.toMatch(/\*\*|\]\(|\|---|^#/m);
    await expect(page.locator('mark.legal__placeholder').first()).toHaveText(/^To be added by the shop: /);
    await view(page, testInfo, `legal-${doc.shot}-top`);

    // "On this page": every section, a link to each. Opened at its address, it starts as its plain HTML
    // had it, a tap away, at both sizes, so nothing moves when the site takes over (a policy opened in
    // the site has it open on a computer: the takeover test below).
    const contents = page.getByRole('navigation', { name: 'On this page' });
    const details = contents.locator('details');
    await expect(details).not.toHaveAttribute('open');
    await contents.locator('summary').click();
    await expect(details).toHaveAttribute('open', '');
    const sections = page.getByTestId('legal-page').locator('h2');
    await expect(contents.getByRole('link')).toHaveCount(await sections.count());
    await expect(contents.getByRole('link').first()).toHaveText('The short version');

    await expectAccessible(page, doc.path);
    await expectFits(page, doc.path);
    await scrollToTop(doc.part(page));
    await view(page, testInfo, `legal-${doc.shot}-part`);
    expect(otherSites, `${doc.path} loads nothing from another site`).toEqual([]);
  });
}

test('the footer of every page links the four, Privacy first, and each opens with the focus on its words', async ({ page }, testInfo) => {
  await page.goto('/');
  const legal = page.getByRole('contentinfo').getByRole('navigation', { name: 'Legal' });
  // The refund policy ("Refunds", the Terms' refunds) next to the Cancellation & No-Show Policy (OWNER-CHECKLIST §3 item 20).
  await expect(legal.getByRole('link')).toHaveText(['Privacy Policy', 'Terms of Service', 'Cancellation & No-Show Policy', 'Refunds', 'Accessibility']);
  await expect(legal.getByRole('link', { name: 'Refunds' })).toHaveAttribute('href', '/terms#refunds');
  // Who runs the shop and where (OWNER-CHECKLIST §3 item 20), no smaller than the booking pages' words.
  // The LLC's name and the shop's email aren't given yet: only what exists, the shop and its address.
  const operator = page.getByRole('contentinfo').getByTestId('footer-operator');
  await expect(operator).toHaveText('Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.');
  await expect(page.getByRole('contentinfo')).not.toContainText(/operated by|To be added|To get this information by email/);
  await expect(page.getByRole('contentinfo')).toContainText(/Copyright © \d{4} Izzy Clipz Barbershop\. All rights reserved\./);
  expect(await operator.locator('p').first().evaluate((line) => getComputedStyle(line).fontSize)).toBe('17px');
  // So are the policies, "Refunds" with them, and the copyright.
  await expectFooterAtBookingSize(page, 'Home');
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await view(page, testInfo, 'legal-05-footer');

  // "Refunds" opens the Terms at the refund policy, in view below the nav.
  await legal.getByRole('link', { name: 'Refunds' }).click();
  await expect(page).toHaveURL(/\/terms#refunds$/);
  const refunds = page.locator('#refunds');
  await expect(refunds).toContainText(/^Refunds\. /);
  await expect(refunds).toBeFocused();
  await expect(refunds).toBeInViewport();
  const navBottomAtRefunds = await page.locator('nav.globalnav').evaluate((nav) => nav.getBoundingClientRect().bottom);
  expect((await refunds.boundingBox())!.y, 'the refund policy starts below the nav').toBeGreaterThanOrEqual(navBottomAtRefunds);
  await view(page, testInfo, 'legal-05b-terms-refunds');
  await page.goto('/');

  await legal.getByRole('link', { name: 'Privacy Policy' }).click();
  await expect(page).toHaveURL(/\/privacy$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Privacy Policy' })).toBeVisible();
  // As on every change of page: screen readers and the keyboard start at the page's content.
  await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe('main');

  // A section from "On this page", in view below the nav, where the reading goes on.
  const contents = page.getByRole('navigation', { name: 'On this page' });
  if (isPhone(testInfo)) await contents.locator('summary').click();
  await contents.getByRole('link', { name: 'Cookies and storage on your device' }).click();
  await expect(page).toHaveURL(/#cookies-and-storage-on-your-device$/);
  const heading = page.getByRole('heading', { level: 2, name: 'Cookies and storage on your device' });
  await expect(heading).toBeFocused();
  await expect(heading).toBeInViewport();
  const navBottom = await page.locator('nav.globalnav').evaluate((nav) => nav.getBoundingClientRect().bottom);
  expect((await heading.boundingBox())!.y, 'the section starts below the nav').toBeGreaterThanOrEqual(navBottom);

  // A link to another document opens its page here.
  await page.getByTestId('legal-page').getByRole('link', { name: 'Cancellation & No-Show Policy' }).first().click();
  await expect(page).toHaveURL(/\/cancellation-policy$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Cancellation & No-Show Policy' })).toBeVisible();
});

test('at 320 pixels wide, the footer’s policies, who runs the shop and the copyright fit, tidily, at the booking pages’ size', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 320, height: 640 });
  await page.goto('/');
  await expect(page.getByRole('contentinfo').getByTestId('footer-operator')).toBeVisible();
  await expectFooterAtBookingSize(page, 'Home at 320 pixels');
  await expectFits(page, 'Home at 320 pixels');
  const footer = await page.getByRole('contentinfo').evaluate((element) => {
    const width = document.documentElement.clientWidth;
    const box = (node: Element) => node.getBoundingClientRect();
    const links = Array.from(element.querySelectorAll('nav[aria-label="Legal"] a'));
    const lineHeight = links[0] ? parseFloat(getComputedStyle(links[0]).lineHeight) : 0;
    const lines = [
      ...links,
      ...Array.from(element.querySelectorAll('[data-testid="footer-operator"] p')),
      ...Array.from(element.querySelectorAll('p')).filter((p) => p.textContent?.startsWith('Copyright ©')),
    ];
    return {
      width,
      // Each policy on a line of its own making: never broken over two lines.
      broken: links.filter((a) => box(a).height > lineHeight * 1.5).map((a) => a.textContent),
      // Inside the page's side margins (16 pixels at this width).
      outside: lines.filter((line) => box(line).left < 15.5 || box(line).right > width - 15.5).map((line) => line.textContent?.slice(0, 30)),
    };
  });
  expect(footer.width).toBe(320);
  expect(footer.broken, 'no policy is broken over two lines').toEqual([]);
  expect(footer.outside, 'everything keeps the side margins').toEqual([]);
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await view(page, testInfo, 'legal-05c-footer-320');
});

test('the footer’s “Izzy Clipz Business” opens it as a page of its own, with the focus on its content, as on every change of page', async ({ page }) => {
  await page.goto('/');
  const link = page.getByRole('contentinfo').getByRole('link', { name: 'Izzy Clipz Business' });
  await expect(link).toHaveAttribute('href', '/business/');
  await link.click();
  await expect(page).toHaveURL(/\/business\/$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/business/manifest.webmanifest');
  await expect(page.locator('main.biz-main')).toBeFocused();
  // Opened at its address instead (a bookmark, an address typed in), the browser starts at the top: "Skip to main content" first.
  await page.goto('/business/');
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused();
});

test('the legal pages open offline once the app is kept on this device', async ({ page, context }) => {
  await page.goto('/');
  await controlledByWorker(page);
  await context.setOffline(true);
  try {
    for (const doc of DOCS) {
      await page.goto(doc.path);
      await expect(page.getByRole('heading', { level: 1, name: doc.heading })).toBeVisible();
    }
  } finally {
    await context.setOffline(false);
  }
});

test('online, a legal page comes from the network first, so a version the shop publishes shows at once', async ({ page, context }) => {
  await page.goto('/');
  await controlledByWorker(page);
  // Stands in for a newer deploy: the server's /terms is a new page. The worker asks the network
  // for it (its own fetch, which the browser context sees) instead of opening the copy it keeps.
  const published = '<!doctype html><html lang="en"><head><title>Terms of Service</title></head><body><main><h1>The Terms as the shop just published them</h1></main></body></html>';
  let askedByWorker = false;
  await context.route(/\/terms$/, (route) => {
    askedByWorker ||= route.request().serviceWorker() !== null;
    return route.fulfill({ status: 200, contentType: 'text/html', body: published });
  });
  try {
    await page.goto('/terms');
    await expect(page.getByRole('heading', { level: 1, name: 'The Terms as the shop just published them' })).toBeVisible();
    // It was the worker that asked the network: the page didn't just skip it.
    expect(askedByWorker).toBe(true);
  } finally {
    await context.unroute(/\/terms$/);
  }
  // The other pages still open from the copy the app keeps.
  await page.goto('/visit');
  await expect(page.getByRole('heading', { level: 1, name: 'Visit the shop' })).toBeVisible();
});

test.describe('without the app kept on this device', () => {
  // No service worker: the legal pages' own script is downloaded when one is opened.
  test.use({ serviceWorkers: 'block' });

  test('a legal page whose script doesn’t download says so under the nav, with Try again, instead of a blank screen', async ({
    page,
    browserConsole,
  }, testInfo) => {
    browserConsole.allow(/Failed to load resource|dynamically imported module|Importing a module script failed/);
    const script = /\/assets\/LegalPage-[^/]+\.js$/;
    await page.route(script, (route) => route.fulfill({ status: 404, contentType: 'text/plain', body: 'Not found' }));
    await page.goto('/services');
    await page.getByRole('contentinfo').getByRole('link', { name: 'Privacy Policy' }).click();
    await expect(page.getByRole('heading', { level: 1, name: "This page didn't load." })).toBeVisible();
    await expect(page.getByText('Check your connection and try again.')).toBeVisible();
    // The rest of the site is still there.
    await expect(page.getByRole('navigation', { name: 'Izzy Clipz' })).toBeVisible();
    await expect(page.getByRole('contentinfo').getByRole('navigation', { name: 'Legal' })).toBeVisible();
    await expectAccessible(page, 'a page whose script didn’t download');
    await view(page, testInfo, 'legal-12-page-did-not-load');
    // Once it can be downloaded, Try again opens the page.
    await page.unroute(script);
    await page.getByRole('button', { name: 'Try again' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Privacy Policy' })).toBeVisible();
  });
});

test('booking says what it agrees to right above Book appointment, the fee notice links its policy, and Your details says where the details go', async ({
  page,
  phone,
  request,
}, testInfo) => {
  const demo = isDemo(testInfo);
  // On the real site, with the shop's no-show protection on: the fee notice shows (the demo never asks for a card).
  if (!demo) await setProtection(request, true);
  try {
    if (demo) {
      await page.goto('/book?service=haircut');
      await page.getByTestId('any-barber').click();
      await expectStep(page, 3, 'Pick a day and time');
      await (await firstTime(page)).click();
    } else {
      await page.goto('/book?barber=carlos-rafael&service=haircut');
      await expectStep(page, 3, 'Pick a day and time');
      const notice = page.getByTestId('fee-warning');
      const read = notice.getByRole('link', { name: /^Read the Cancellation & No-Show Policy/ });
      await expect(read).toHaveAttribute('href', '/cancellation-policy');
      await expect(read).toHaveAttribute('target', '_blank');
      // Next month: outside the late-cancellation window, as most bookings are. The times shown
      // must be next month's before one is picked (today's can still be there for a moment).
      const month = page.getByTestId('calendar-month');
      const thisMonth = await month.innerText();
      await page.getByRole('button', { name: 'Next month' }).click();
      await expect(month).not.toHaveText(thisMonth);
      await expect(page.locator('.times__day')).toContainText((await month.innerText()).split(' ')[0]!);
      await (await firstTime(page)).click();
      await expect(notice).not.toContainText('away, so cancelling it');
      await scrollToTop(notice);
      await view(page, testInfo, 'legal-06a-time-fee-notice');
    }
    await page.getByRole('button', { name: 'Continue' }).click();

    await expectStep(page, 4, 'Your details');
    const privacy = page.getByTestId('details-privacy');
    if (demo) {
      await expect(privacy).toHaveText(/^Demo version: your name and number stay on this (phone|computer)\. Nothing is sent to Izzy Clipz or anywhere else\.$/);
    } else {
      await expect(privacy).toHaveText('Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy (opens in a new tab) explains.');
      await expect(privacy.getByRole('link', { name: /^Privacy Policy/ })).toHaveAttribute('href', '/privacy');
      await expect(privacy.getByRole('link', { name: /^Privacy Policy/ })).toHaveAttribute('target', '_blank');
    }
    // "Remember me" starts off: this browser doesn't know anyone yet.
    await expect(detailsFields(page).remember.or(page.getByRole('checkbox', { name: 'Remember me on this phone' }))).not.toBeChecked();
    await fillDetails(page, { name: 'Lee Legal', phone });
    await whole(page, testInfo, 'legal-07-details');
    await page.getByRole('button', { name: 'Continue' }).click();

    await expectStep(page, 5, 'Review and book');
    const consent = page.getByTestId('book-consent');
    await expect(consent).toHaveText('By booking, you agree to our Terms of Service (opens in a new tab) and Cancellation & No-Show Policy (opens in a new tab).');
    // Right above the button, with or without a card on file (measured once the booking rules have loaded).
    await expect(page.getByTestId('book-note')).not.toHaveText('');
    const above = await consent.evaluate((line) => {
      const button = line.nextElementSibling;
      return { next: button?.getAttribute('data-testid'), gap: button ? button.getBoundingClientRect().top - line.getBoundingClientRect().bottom : -1 };
    });
    expect(above.next).toBe('book-button');
    expect(above.gap, 'the line ends above the button').toBeGreaterThanOrEqual(0);
    // Who runs the shop and where, and "Refunds" next to the Cancellation & No-Show Policy, before any
    // card is saved, under the button and its note, no smaller than the booking's own words
    // (OWNER-CHECKLIST §3 item 20). The LLC's name and the shop's email aren't given yet: only what
    // exists, the shop and its address.
    const operator = page.getByTestId('book-operator');
    await expect(operator.locator('p').first()).toHaveText('Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.');
    await expect(operator).not.toContainText(/operated by|To be added|email us/);
    const policies = page.getByTestId('book-operator-policies');
    await expect(policies.getByRole('link', { name: /^Cancellation & No-Show Policy/ })).toHaveAttribute('href', '/cancellation-policy');
    await expect(policies.getByRole('link', { name: /^Refunds/ })).toHaveAttribute('href', '/terms#refunds');
    await expect(policies.getByRole('link', { name: /^Refunds/ })).toHaveAttribute('target', '_blank');
    const sizes = await operator.evaluate((lines) => ({
      lines: parseFloat(getComputedStyle(lines.querySelector('p')!).fontSize),
      consent: parseFloat(getComputedStyle(document.querySelector('[data-testid="book-consent"]')!).fontSize),
    }));
    expect(sizes.lines).toBeGreaterThanOrEqual(sizes.consent);
    if (!demo) await expect(page.getByTestId('fee-warning').getByRole('link', { name: /^Read the Cancellation & No-Show Policy/ })).toBeVisible();
    await expectAccessible(page, 'Review and book with the consent line');
    await whole(page, testInfo, 'legal-06-review');
    if (!demo) {
      await scrollToTop(page.getByTestId('fee-warning'));
      await view(page, testInfo, 'legal-06b-review-fee-notice');
    }
    // What booking agrees to, with the button under it, as the screen shows them.
    await consent.evaluate((line) => line.scrollIntoView({ block: 'center' }));
    await view(page, testInfo, 'legal-06c-review-consent');

    // The Terms open in a new tab: the booking stays where it is.
    const [terms] = await Promise.all([page.context().waitForEvent('page'), consent.getByRole('link', { name: /^Terms of Service/ }).click()]);
    await expect(terms.getByRole('heading', { level: 1, name: 'Terms of Service' })).toBeVisible();
    await terms.close();
    await expectStep(page, 5, 'Review and book');
  } finally {
    if (!demo) await setProtection(request, false);
  }
});

test('Reviews shows Google’s reviews and only links to Yelp; Visit shows the confirmed accessibility lines and asks people to call about getting in', async ({ page, request }, testInfo) => {
  const demo = isDemo(testInfo);
  if (!demo) await setLiveReviews(request, true);
  try {
    await page.goto('/reviews');
    if (demo) {
      await expect(page.getByTestId('demo-notice')).toHaveText(
        "Demo version: these reviews are samples, not the shop's. The real site shows the shop's reviews from Google, and links to Yelp.",
      );
      await expect(page.getByTestId('sample-reviews')).toBeVisible();
    } else {
      // The server sends Yelp's reviews and rating too: none of it shows, only a plain link.
      await expect(page.getByTestId('google-reviews')).toContainText('Reviews from Google Maps');
      await expect(page.getByTestId('reviews-elsewhere').getByRole('link', { name: /Read our reviews on Yelp/ })).toHaveAttribute('href', YELP);
      await expect(page.getByText('Fixture A.')).toHaveCount(0);
      await expect(page.locator('main')).not.toContainText(/4\.5|Reviews from Yelp/);
    }
    await expect(page.locator('main a[href*="yelp.com"]')).toHaveCount(1);
    await whole(page, testInfo, 'legal-08-reviews');
  } finally {
    if (!demo) await setLiveReviews(request, false);
  }

  await page.goto('/visit');
  // The two lines the owner confirmed, one each, then always the call line (the entrance isn't
  // confirmed step-free).
  await expect(page.getByTestId('visit-accessibility-lines').getByRole('listitem')).toHaveText([
    'Room for a wheelchair inside, at the chairs and the counter',
    'Disabled parking space near the entrance',
  ]);
  const line = page.getByTestId('visit-accessibility-call');
  // No email sentence yet: the shop has no email address in the catalog (OWNER-CHECKLIST §3 item 21).
  await expect(line).toHaveText("Questions about getting in or around the shop? Call (442) 341-3053 (relay calls welcome: dial 711) and we'll help.");
  await expect(line.getByRole('link', { name: '(442) 341-3053' })).toHaveAttribute('href', 'tel:+14423413053');
  await expect(line.locator('a[href^="mailto:"]')).toHaveCount(0);
  await expect(page.locator('main')).not.toContainText(/\bADA\b|Wheelchair accessible|step-free/i);
  await expectAccessible(page, '/visit');
  await whole(page, testInfo, 'legal-09-visit');
  await scrollToTop(page.getByRole('heading', { level: 2, name: 'Good to know' }));
  await view(page, testInfo, 'legal-09b-visit-accessibility');
});

test('Izzy Clipz Business links the policies from every page, small and in a new tab, with its own skip link, titles and focus', async ({
  page,
  request,
}, testInfo) => {
  await page.goto('/business');
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  // "Skip to main content" comes first, and goes to the page's content.
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe('main');
  const legal = () => page.getByRole('contentinfo').getByRole('navigation', { name: 'Legal' });
  await expect(legal().getByRole('link')).toHaveText([/^Privacy Policy/, /^Terms of Service/, /^Cancellation & No-Show Policy/, /^Accessibility/]);
  for (const link of await legal().getByRole('link').all()) await expect(link).toHaveAttribute('target', '_blank');
  await expectAccessible(page, 'Business sign-in');
  await whole(page, testInfo, 'legal-10-business-sign-in');

  if (isDemo(testInfo)) {
    await page.getByRole('button', { name: 'Open the Business demo' }).click();
    await expect(page.getByTestId('today-page')).toBeVisible();
  } else {
    await signInWithCode(page, request);
  }
  // Every page: a title, one main heading, the focus on its content after the change, and the policies.
  for (const [name, title] of [
    ['Analytics', 'Analytics · Izzy Clipz Business'],
    ['Products', 'Products · Izzy Clipz Business'],
    ['Settings', 'Settings · Izzy Clipz Business'],
    ['Today', 'Today · Izzy Clipz Business'],
  ] as const) {
    await navLink(page, name).click();
    await expect(page).toHaveTitle(title);
    await expect(page.locator('h1')).toHaveCount(1);
    await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe('main');
    await expect(legal().getByRole('link')).toHaveCount(4);
  }
  await whole(page, testInfo, 'legal-11-business-today');

  // Its page for an address it doesn't have, too.
  await page.goto('/business/no-such-page');
  await expect(page.getByRole('heading', { level: 1, name: "This page isn't here." })).toBeVisible();
  await expect(page).toHaveTitle('Page not found · Izzy Clipz Business');
  await expect(legal().getByRole('link')).toHaveCount(4);
  await expectAccessible(page, 'Business page not found');
  await expectFits(page, 'Business page not found');
});

test('the browser keeps only what the Privacy Policy lists: one cookie on the real site and none in the demo, its storage keys, and nothing personal in the caches', async ({
  page,
  context,
  phone,
}, testInfo) => {
  const demo = isDemo(testInfo);
  const digits = phone.replace(/\D/g, '');
  await page.goto('/book?service=haircut');
  await page.getByTestId('any-barber').click();
  await (await firstTime(page)).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 4, 'Your details');
  await fillDetails(page, { name: 'Kept Person', phone, email: 'kept.person@example.com', note: 'kept note' });
  // "Remember me" is off unless this browser already remembers the client; here they turn it on.
  const remember = page.getByRole('checkbox', { name: /^Remember me on this/ });
  await expect(remember).not.toBeChecked();
  await page.locator('label.checkbox__label').click();
  await expect(remember).toBeChecked();
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByTestId('book-button').click();
  await expect(page.getByTestId('booked-title')).toHaveText(demo ? 'Demo booking made' : "You're booked");

  const kept = await page.evaluate(() => ({ local: Object.keys(localStorage), session: Object.keys(sessionStorage) }));
  const allowed = { local: [...POLICY_STORAGE.local, ...(demo ? POLICY_STORAGE.demo : [])], session: [...POLICY_STORAGE.session] };
  expect(kept.local.filter((key) => !(allowed.local as string[]).includes(key)), 'localStorage keys the policy doesn’t list').toEqual([]);
  expect(kept.session.filter((key) => !(allowed.session as string[]).includes(key)), 'sessionStorage keys the policy doesn’t list').toEqual([]);
  // Once booked, the booking in progress is gone; the list of appointments has no name, number, email or note.
  expect(kept.session).not.toContain('izzy.booking.v1');
  const listed = await page.evaluate(() => localStorage.getItem('izzy.appointments.v1') ?? localStorage.getItem('izzy.demo.appointments.v1') ?? '');
  expect(listed).not.toBe('');
  for (const detail of ['Kept Person', digits, 'kept.person', 'kept note']) expect(listed, detail).not.toContain(detail);
  // "Remember me" kept the name, number and email, and never the note.
  const remembered = await page.evaluate(() => localStorage.getItem('izzy.details.v1') ?? '');
  expect(remembered).toContain('Kept Person');
  expect(remembered).not.toContain('kept note');

  // One cookie, izzy_appointments, on the real site; none at all in the demo.
  expect((await context.cookies()).map((cookie) => cookie.name)).toEqual(demo ? [] : ['izzy_appointments']);

  // The caches: this version's files and the shop's public menu, nothing personal.
  await controlledByWorker(page);
  const caches = await page.evaluate(async () => {
    const names = await window.caches.keys();
    const urls: string[] = [];
    for (const name of names) for (const request of await (await window.caches.open(name)).keys()) urls.push(request.url);
    return { names, urls };
  });
  expect(caches.names.every((name) => /^izzy-app-[0-9a-f]+$/.test(name) || name === 'izzy-catalog-v1'), caches.names.join(', ')).toBe(true);
  expect(caches.urls.filter((url) => new URL(url).pathname.startsWith('/api/') && new URL(url).pathname !== '/api/catalog')).toEqual([]);

  // Next time, this browser remembers the client: "Remember me" starts on, with "Not you?" to forget.
  await page.goto('/book?service=haircut');
  await page.getByTestId('any-barber').click();
  await (await firstTime(page)).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expect(remember).toBeChecked();
  await page.getByRole('button', { name: /^Not you\? Forget me on this/ }).click();
  await expect(remember).not.toBeChecked();
  expect(await page.evaluate(() => localStorage.getItem('izzy.details.v1'))).toBeNull();
});

test('"Forget me" on My appointments says what it did where the focus goes, in view, from the keyboard alone', async ({ page, phone }, testInfo) => {
  const demo = isDemo(testInfo);
  // A booking, so My appointments is long and "Forget me" is far down it.
  await page.goto('/book?service=haircut');
  await page.getByTestId('any-barber').click();
  await (await firstTime(page)).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 4, 'Your details');
  await fillDetails(page, { name: 'Gone Person', phone });
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByTestId('book-button').click();
  await expect(page.getByTestId('booked-title')).toHaveText(demo ? 'Demo booking made' : "You're booked");

  await page.goto('/appointments');
  await expect(page.getByTestId('appointment-card')).toBeVisible();
  // The status region is there all along, empty, so what appears in it is read out.
  const status = page.getByTestId('forget-status');
  await expect(status).toHaveAttribute('role', 'status');
  await expect(status).toBeEmpty();
  const forget = page.getByRole('button', { name: /^Forget me on this (computer|phone)$/ });
  await tabTo(page, forget, 120);
  await page.keyboard.press('Enter');
  const dialog = page.getByTestId('forget-dialog');
  await expect(dialog.getByRole('button', { name: 'Keep everything' })).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(dialog.getByRole('button', { name: 'Forget me', exact: true })).toBeFocused();
  await page.keyboard.press('Enter');

  // The button that asked is gone: the focus goes to what happened, on screen below the nav, not to the page itself.
  await expect(page.getByTestId('forgotten-notice')).toContainText(
    demo ? "no longer keeps your details, the demo's bookings or Izzy Clipz Business's sample shop. The copies of the site's own pages stay" : 'no longer keeps your details, card or appointments',
  );
  await expect(page.getByTestId('forget-computer')).toHaveCount(0);
  await expect(status).toBeFocused();
  await expect(status, 'the focus ring shows').toHaveCSS('outline-style', 'solid');
  await expect(status).toBeInViewport({ ratio: 1 });
  const nav = (await page.getByRole('navigation', { name: 'Izzy Clipz' }).boundingBox())!;
  expect((await status.boundingBox())!.y, 'below the nav').toBeGreaterThanOrEqual(nav.y + nav.height);
  await expectAccessible(page, 'My appointments after Forget me');
  await view(page, testInfo, 'legal-13-forget-me-done');
});

/** Each document's one main heading, its <title>, and words from it (a section's heading), as the build writes its plain HTML. */
const PLAIN = [
  { path: '/privacy', heading: 'Privacy Policy', title: 'Privacy Policy', words: 'Who we share your information with' },
  { path: '/terms', heading: 'Terms of Service', title: 'Terms of Service', words: '4. Prices and paying' },
  { path: '/cancellation-policy', heading: 'Cancellation &amp; No-Show Policy', title: 'Cancellation &amp; No-Show Policy', words: 'Bookings with a card on file' },
  { path: '/accessibility', heading: 'Accessibility Statement', title: 'Accessibility', words: 'Other ways to book and get help' },
] as const;

test('the build has the four legal pages as plain HTML, with their headings and words and no placeholder as written, served at their addresses', async ({
  request,
}, testInfo) => {
  test.skip(isPhone(testInfo), 'Once is enough: the same files');
  // The build this run serves: the shop's (../public) or the demo's (dist-demo).
  const built = resolve(isDemo(testInfo) ? 'dist-demo' : '../public');
  for (const doc of PLAIN) {
    const html = readFileSync(join(built, doc.path.slice(1), 'index.html'), 'utf8');
    expect(html.match(/<h1[\s>]/g), doc.path).toHaveLength(1);
    expect(html, doc.path).toMatch(new RegExp(`<h1 [^>]*>${doc.heading}</h1>`));
    expect(html, doc.path).toContain(`<title>${doc.title} · Izzy Clipz Barbershop</title>`);
    expect(html, doc.path).toMatch(/<meta name="description" content="[^"]{40,}" \/>/);
    expect(html, doc.path).toContain(`>${doc.words}</h2>`);
    expect(html, doc.path).toContain(DRAFT);
    expect(html, doc.path).not.toContain('[TO FILL IN');
    expect(html, doc.path).not.toContain('OWNER-CHECKLIST');
    // The site's script is there to take over, and the note for browsers without it comes first.
    expect(html, doc.path).toMatch(/<script type="module" crossorigin src="\/assets\/main-[^"]+\.js"><\/script>/);
    expect(html.indexOf('data-testid="noscript"'), doc.path).toBeLessThan(html.indexOf('<div id="root">'));
    // Served at the page's address, with or without a trailing slash, with the hosting's headers.
    for (const address of [doc.path, `${doc.path}/`]) {
      const served = await request.get(address);
      expect(served.status(), address).toBe(200);
      expect(await served.text(), address).toBe(html);
      expect(served.headers()['x-content-type-options'], address).toBe('nosniff');
      if (isDemo(testInfo)) expect(served.headers()['x-robots-tag'], address).toBe('noindex');
    }
  }
  // Every other page is still the site's own page.
  expect(await (await request.get('/book/time')).text()).toContain('<div id="root"></div>');
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false, serviceWorkers: 'block' });

  /** The screen as it is (no script runs to wait for). */
  async function plainView(page: Page, testInfo: TestInfo, name: string): Promise<void> {
    mkdirSync(LEGAL_SHOTS, { recursive: true });
    await page.screenshot({ path: join(LEGAL_SHOTS, `${testInfo.project.name}-${name}.png`), animations: 'disabled' });
  }

  /** The note every page starts with: first, in its own colours, with the shop's number and the four policies. */
  async function expectNote(page: Page): Promise<Locator> {
    const note = page.getByTestId('noscript');
    await expect(note).toBeVisible();
    expect((await note.boundingBox())!.y, 'first on the page').toBe(0);
    await expect(note).toHaveCSS('background-color', 'rgb(255, 255, 255)');
    await expect(note).toHaveCSS('color', 'rgb(29, 29, 31)');
    await expect(note.getByRole('link', { name: '(442) 341-3053' })).toHaveAttribute('href', 'tel:+14423413053');
    const policies = [
      ['Privacy Policy', '/privacy'],
      ['Terms of Service', '/terms'],
      ['Cancellation & No-Show Policy', '/cancellation-policy'],
      ['Accessibility', '/accessibility'],
    ] as const;
    for (const [name, href] of policies) await expect(note.getByRole('link', { name, exact: true })).toHaveAttribute('href', href);
    // A landmark of its own, named for screen readers.
    await expect(page.getByRole('complementary', { name: 'Without JavaScript' })).toHaveAttribute('data-testid', 'noscript');
    return note;
  }

  /**
   * axe-core on a page whose own scripts are off. Nothing can run in the page's own world then (so
   * expectAccessible's AxeBuilder can't either), so it runs in a world of its own, as an extension's
   * scripts do, and as Playwright's own checks do. Timers don't fire in a page whose scripts are off,
   * so in that world axe-core's waits (setTimeout) go on at once, as promises do; and it doesn't fetch
   * the page's stylesheets again (preload), which it only needs for a rule about locked orientation.
   * axe-core takes whatever is in a <noscript> for hidden, as it is with scripts on; with them off the
   * browser shows it in place, so each <noscript> is unwrapped first: the same nodes, in the same order.
   */
  async function axeWithoutPageScripts(page: Page): Promise<{ id: string; impact: string | null; nodes: { target: string[] }[] }[]> {
    const cdp = await page.context().newCDPSession(page);
    try {
      const { frameTree } = await cdp.send('Page.getFrameTree');
      const { executionContextId } = await cdp.send('Page.createIsolatedWorld', { frameId: frameTree.frame.id, worldName: 'izzy-axe', grantUniveralAccess: true });
      const timers = 'globalThis.setTimeout = (callback, _ms, ...args) => { Promise.resolve().then(() => callback(...args)); return 0; }; globalThis.clearTimeout = () => undefined;';
      const unwrap = "for (const noscript of Array.from(document.querySelectorAll('noscript'))) noscript.replaceWith(...Array.from(noscript.childNodes));";
      await cdp.send('Runtime.evaluate', { expression: `${timers}\n${AXE_SOURCE}\n${unwrap}`, contextId: executionContextId });
      const answer = await cdp.send('Runtime.evaluate', {
        expression: 'axe.run(document, { preload: false }).then((r) => r.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.map((n) => ({ target: n.target })) })))',
        contextId: executionContextId,
        awaitPromise: true,
        returnByValue: true,
      });
      if (answer.exceptionDetails) throw new Error(`axe-core didn't run: ${answer.exceptionDetails.text}`);
      return answer.result.value as { id: string; impact: string | null; nodes: { target: string[] }[] }[];
    } finally {
      await cdp.detach();
    }
  }

  /** axe-core finds nothing outside a landmark (its "region" rule), and nothing serious or critical. */
  async function expectInLandmarks(page: Page, what: string): Promise<void> {
    const violations = await axeWithoutPageScripts(page);
    expect(
      violations
        .filter((v) => v.id === 'region' || v.impact === 'serious' || v.impact === 'critical')
        .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 4).join(' | ')}`),
      `${what}: axe-core, everything in a landmark`,
    ).toEqual([]);
  }

  test('Home starts with a note anyone can read, with the shop’s number and the four policies, which open', async ({ page }, testInfo) => {
    await page.goto('/');
    const note = await expectNote(page);
    await expect(note).toContainText(
      'This website needs JavaScript for online booking and for most of its pages. To book, call Izzy Clipz Barbershop at (442) 341-3053, or come by 1919 Mission Ave, Ste 105, Oceanside, CA 92058.',
    );
    await expect(note).toContainText('Open Monday–Saturday: 10 AM – 7 PM; Sunday: 10 AM – 6 PM.');
    await expect(note).toContainText('Our policies open without it:');
    await expect(note).toBeInViewport({ ratio: 1 });
    // Without the site there's nothing else on the page to skip to: the first Tab stop is the note's first link, the shop's number.
    await page.keyboard.press('Tab');
    await expect(note.getByRole('link', { name: '(442) 341-3053' })).toBeFocused();
    await expectInLandmarks(page, 'Home without JavaScript');
    await plainView(page, testInfo, 'legal-14-home-without-javascript');

    await note.getByRole('link', { name: 'Privacy Policy' }).click();
    await expect(page).toHaveURL(/\/privacy$/);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Privacy Policy');
  });

  test('/privacy is the policy itself, readable: its title, its draft note, its sections and its words, and the other policies a link away', async ({
    page,
  }, testInfo) => {
    await page.goto('/privacy');
    await expectNote(page);
    // "Skip to main content" is the first Tab stop, before the note's links (and only once), and goes to the policy.
    const skip = page.getByRole('link', { name: 'Skip to main content' });
    await expect(skip).toHaveCount(1);
    await page.keyboard.press('Tab');
    await expect(skip).toBeFocused();
    await expect(skip).toBeInViewport();
    await page.keyboard.press('Enter');
    await expect(page.locator('main#main')).toBeFocused();
    await expectInLandmarks(page, '/privacy without JavaScript');
    await expect(page).toHaveTitle('Privacy Policy · Izzy Clipz Barbershop');
    await expect(page.locator('meta[name="description"]')).toHaveAttribute('content', /^What Izzy Clipz Barbershop collects/);
    const heading = page.getByRole('heading', { level: 1 });
    await expect(heading).toHaveText('Privacy Policy');
    await expect(page.locator('h1')).toHaveCount(1);
    await expect(heading).toBeInViewport();
    const draft = page.getByTestId('legal-draft');
    await expect(draft).toContainText(DRAFT);
    if (isDemo(testInfo)) await expect(draft).toContainText(DEMO_LINE);
    await expect(page.getByTestId('legal-dates')).toContainText('Effective date: Not in effect yet');
    // Dark words on the page's white, at a readable measure (the legal pages' own styles).
    const intro = page.getByText('This policy explains what information Izzy Clipz Barbershop');
    await expect(intro).toBeVisible();
    await expect(intro).toHaveCSS('color', 'rgb(29, 29, 31)');
    await expect(page.getByRole('main')).toHaveCSS('background-color', 'rgb(255, 255, 255)');
    expect((await intro.boundingBox())!.width).toBeLessThanOrEqual(760);
    const section = page.getByRole('heading', { level: 2, name: 'Who we share your information with' });
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    const words = await page.getByTestId('legal-page').innerText();
    expect(words).toContain('Neon, a Databricks company, hosts our database in the United States.');
    expect(words).not.toContain('TO FILL IN');
    expect(words).not.toContain('OWNER-CHECKLIST');
    await expect(page.locator('mark.legal__placeholder').first()).toHaveText(/^To be added by the shop: /);
    // The footer gives the shop's hours (the Accessibility Statement asks people to call "during opening
    // hours") and who runs the shop, from the catalog the build serves.
    const footer = page.getByRole('contentinfo');
    await expect(footer.getByRole('list', { name: 'Hours' }).getByRole('listitem')).toHaveText(['Monday–Saturday: 10 AM – 7 PM', 'Sunday: 10 AM – 6 PM']);
    await expect(footer.getByTestId('footer-operator')).toHaveText('Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.');
    await expect(footer.getByRole('navigation', { name: 'Legal' }).getByRole('link', { name: 'Refunds' })).toHaveAttribute('href', '/terms#refunds');
    // At the booking pages' size, as in the site's own footer.
    await expectFooterAtBookingSize(page, '/privacy without JavaScript');
    // The nav is the site's: Book with its pill, and on a phone "Menu", which goes to the footer's site directory.
    const nav = page.getByRole('navigation', { name: 'Izzy Clipz' });
    await expect(nav.getByRole('link', { name: 'Book an appointment' })).toHaveAttribute('href', '/book');
    const menu = page.locator('nav.globalnav .globalnav__menu-standin');
    if (isPhone(testInfo)) {
      await expect(menu).toHaveAccessibleName("Menu: the site's pages, at the bottom of this page");
      await expect(menu).toHaveText('Menu');
      await menu.click();
      await expect(page).toHaveURL(/\/privacy#site-directory$/);
      await expect(footer.getByRole('navigation', { name: 'Site directory' })).toBeInViewport();
    } else {
      await expect(menu).toBeHidden();
    }
    await page.getByTestId('noscript').scrollIntoViewIfNeeded();
    await plainView(page, testInfo, 'legal-15-privacy-without-javascript');

    // Another policy, from the footer, opens as plain HTML too.
    await page.getByRole('contentinfo').getByRole('navigation', { name: 'Legal' }).getByRole('link', { name: 'Terms of Service' }).click();
    await expect(page).toHaveURL(/\/terms$/);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Terms of Service');
    await expect(page).toHaveTitle('Terms of Service · Izzy Clipz Barbershop');
  });

  test('printed, a policy is the policy alone, without the note for browsers without JavaScript', async ({ page }) => {
    await page.goto('/privacy');
    await expect(page.getByTestId('noscript')).toBeVisible();
    await page.emulateMedia({ media: 'print' });
    await expect(page.getByTestId('noscript')).toBeHidden();
    await expect(page.locator('nav.globalnav')).toBeHidden();
    await expect(page.getByRole('contentinfo')).toBeHidden();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Privacy Policy');
    await expect(page.getByRole('heading', { level: 1 })).toBeInViewport();
    await page.emulateMedia({ media: 'screen' });
    await expect(page.getByTestId('noscript')).toBeVisible();
  });
});

test('printed, a link in a policy to another site shows its address after it; one to the site’s own pages doesn’t', async ({ page }) => {
  await page.goto('/privacy');
  await siteTookOver(page);
  // What prints after a link: its ::after.
  const after = (link: Locator) => link.evaluate((a) => getComputedStyle(a, '::after').content);
  const stripe = page.locator('.legal__article a[href="https://stripe.com/privacy"]').first();
  const own = page.locator('.legal__article a[href^="/"]').first();
  await expect(stripe).toHaveText("Stripe's Privacy Policy");
  await expect(own).toBeVisible();
  expect(await after(stripe)).toBe('none');
  await page.emulateMedia({ media: 'print' });
  expect(await after(stripe)).toBe('" (https://stripe.com/privacy)"');
  expect(await after(own)).toBe('none');
});

test('with JavaScript, the site takes a legal page over from its plain HTML in one go: never “Loading…”, its own nav, and “On this page” as it was', async ({
  page,
}, testInfo) => {
  // Everything #root shows while the page loads, noted as it happens.
  await page.addInitScript(() => {
    const seen: string[] = [];
    (window as unknown as { izzyRootSeen: string[] }).izzyRootSeen = seen;
    new MutationObserver(() => {
      // Once the plain HTML is all there (the site's script runs only after that).
      if (document.readyState === 'loading') return;
      const root = document.getElementById('root');
      if (!root) return;
      if (root.querySelector('.legal-loading') || (root.textContent ?? '').includes('Loading…')) seen.push('loading');
      if (root.querySelectorAll('h1').length > 1) seen.push('two pages');
      if (root.querySelector('main') && root.querySelectorAll('h1').length === 0) seen.push('no page');
    }).observe(document, { childList: true, subtree: true });
  });
  await page.goto('/cancellation-policy');
  await siteTookOver(page);
  await expect(page.locator('h1')).toHaveCount(1);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Cancellation & No-Show Policy');
  expect(await page.evaluate(() => (window as unknown as { izzyRootSeen: string[] }).izzyRootSeen), 'the plain page, then the site’s, and nothing in between').toEqual([]);
  // The site's own nav: its Book link, and on a phone its menu.
  await expect(page.locator('nav.globalnav .globalnav__book')).toBeVisible();
  if (isPhone(testInfo)) await expect(page.getByRole('button', { name: 'Menu' })).toBeVisible();
  // "On this page" as the plain HTML had it (closed), on a computer too, so nothing on screen moves.
  const details = page.getByRole('navigation', { name: 'On this page' }).locator('details');
  await expect(details).not.toHaveAttribute('open');
  // A policy opened in the site itself has it as the site does: open on a computer, closed on a phone.
  await page.getByRole('contentinfo').getByRole('navigation', { name: 'Legal' }).getByRole('link', { name: 'Privacy Policy' }).click();
  await expect(page).toHaveURL(/\/privacy$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Privacy Policy');
  const opened = page.getByRole('navigation', { name: 'On this page' }).locator('details');
  if (isPhone(testInfo)) await expect(opened).not.toHaveAttribute('open');
  else await expect(opened).toHaveAttribute('open', '');
});

test.describe('on a slow connection', () => {
  // The page itself, as the network sends it (no service worker in between).
  test.use({ serviceWorkers: 'block' });

  test('a reader who started on the plain HTML keeps their place when the site takes over: the section on screen and the link the keyboard is on', async ({
    page,
  }, testInfo) => {
    // The site's script comes late, as on a slow phone connection.
    let release = () => undefined as void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    await page.route(/\/assets\/main-[^/]+\.js$/, async (route) => {
      await held;
      await route.continue();
    });
    await page.goto('/privacy', { waitUntil: 'commit' });
    const heading = () => page.getByRole('heading', { level: 2, name: 'Who we share your information with' });
    await expect(heading()).toBeVisible();
    await expect(page.locator('[data-prerendered]')).toHaveCount(1);
    // Read on to the middle of the policy, with the keyboard on a link there.
    await heading().evaluate((h) => window.scrollBy(0, h.getBoundingClientRect().top - 160));
    const link = page.locator('main a[href="https://stripe.com/privacy"]').first();
    await link.focus();
    const before = await heading().evaluate((h) => ({ top: h.getBoundingClientRect().top, scrollY: window.scrollY }));
    expect(before.scrollY).toBeGreaterThan(1000);

    release();
    await siteTookOver(page);
    const after = await heading().evaluate((h) => ({ top: h.getBoundingClientRect().top, scrollY: window.scrollY }));
    expect(Math.abs(after.top - before.top), 'the section stays where it was on the screen').toBeLessThanOrEqual(2);
    // The keyboard is still on the same link (its words and address), not back at the start of the page.
    expect(
      await page.evaluate(() => {
        const active = document.activeElement;
        return active instanceof HTMLAnchorElement ? [active.getAttribute('href'), active.closest('main') !== null] : [active?.tagName ?? null, false];
      }),
    ).toEqual(['https://stripe.com/privacy', true]);
    await view(page, testInfo, 'legal-16-slow-takeover-keeps-place');
  });

  test('the site takes the plain HTML over without moving the nav or the footer: the same bar, Book and Menu in it, and the footer’s hours and who runs the shop all along', async ({
    page,
  }, testInfo) => {
    // The site's script comes late, so the plain HTML can be measured first.
    let release = () => undefined as void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    await page.route(/\/assets\/main-[^/]+\.js$/, async (route) => {
      await held;
      await route.continue();
    });
    await page.goto('/privacy', { waitUntil: 'commit' });
    const footer = page.getByRole('contentinfo');
    await expect(page.locator('[data-prerendered]')).toHaveCount(1);
    await expect(footer.getByTestId('footer-operator')).toBeVisible();
    await page.evaluate(async () => {
      await document.fonts.ready;
    });
    // Every box in the nav: the bar, the logo, the site's pages, Book and Menu (each shown or not, as the screen's width has it).
    const navBoxes = () =>
      page.locator('nav.globalnav').evaluate((nav) =>
        [nav, ...Array.from(nav.querySelectorAll('.globalnav__logo, .globalnav__link, .globalnav__book, .globalnav__book-pill, .globalnav__menu-button, .globalnav__menu-standin'))].map((element) => {
          const box = element.getBoundingClientRect();
          const name = element.className.toString().replace('globalnav__menu-standin', 'globalnav__menu-button');
          return `${name} ${box.x.toFixed(1)},${box.y.toFixed(1)} ${box.width.toFixed(1)}x${box.height.toFixed(1)}`;
        }),
      );
    const before = await navBoxes();
    expect(before.some((box) => box.startsWith('globalnav__book ')), 'the plain HTML has Book').toBe(true);
    // From here on, the footer's height each time anything in the page changes.
    await page.evaluate(() => {
      const heights: number[] = [];
      (window as unknown as { izzyFooterHeights: number[] }).izzyFooterHeights = heights;
      const note = () => {
        const element = document.querySelector('footer.globalfooter');
        if (element) heights.push(Math.round(element.getBoundingClientRect().height * 10) / 10);
      };
      note();
      new MutationObserver(note).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
    });

    release();
    await siteTookOver(page);
    // The site's own Menu button now, and its footer with the hours and who runs the shop.
    await expect(page.locator('nav.globalnav button.globalnav__menu-button')).toHaveCount(1);
    await expect(page.locator('.globalnav__menu-standin')).toHaveCount(0);
    await expect(footer.getByTestId('footer-operator')).toBeVisible();
    await expect(footer.getByRole('list', { name: 'Hours' })).toBeVisible();
    // Whatever the site asks for on the way (were it the catalog) has come.
    await page.waitForLoadState('networkidle');
    expect(await navBoxes(), 'the nav, box for box').toEqual(before);
    const heights = await page.evaluate(() => (window as unknown as { izzyFooterHeights: number[] }).izzyFooterHeights);
    expect(heights.length).toBeGreaterThan(1);
    expect([...new Set(heights)], 'the footer’s height, through the takeover').toHaveLength(1);
    await view(page, testInfo, 'legal-17-takeover-same-nav');
  });
});

test('a legal page’s file address (“/privacy/index.html”) goes to the page itself, with or without JavaScript', async ({ page, request }) => {
  for (const path of ['/privacy', '/terms', '/cancellation-policy', '/accessibility']) {
    const response = await request.get(`${path}/index.html`, { maxRedirects: 0 });
    expect(response.status(), path).toBe(308);
    expect(response.headers().location, path).toBe(path);
  }
  await page.goto('/terms/index.html');
  await expect(page).toHaveURL(/\/terms$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Terms of Service');
  await expect(page).toHaveTitle('Terms of Service · Izzy Clipz Barbershop');
});
