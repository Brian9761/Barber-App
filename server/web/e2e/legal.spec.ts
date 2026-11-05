import { mkdirSync } from 'node:fs';
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
  test,
  watchOtherSites,
} from './support.js';

// The shop's four legal documents as pages (drafts until the shop publishes them), and what
// they say the website does, on the real site (playwright.config.ts) and the demo
// (playwright.demo.config.ts), at a computer's size and a phone's: every page's footer links
// them; Izzy Clipz Business does too, with its own skip link, titles and focus; booking says
// what it agrees to, the fee notice links its policy, and Your details says where the details
// go; Reviews shows Google's and only links to Yelp; Visit claims no accessibility feature
// nobody has checked; and the browser keeps only what the Privacy Policy lists.
// Screenshots go to E2E_LEGAL_SHOTS_DIR (or with the others), named "<run>-legal-…".

const LEGAL_SHOTS = resolve(process.env.E2E_LEGAL_SHOTS_DIR || SHOTS_DIR);
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

    // "On this page": every section, a link to each; open on a computer, a tap away on a phone.
    const contents = page.getByRole('navigation', { name: 'On this page' });
    const details = contents.locator('details');
    if (isPhone(testInfo)) {
      await expect(details).not.toHaveAttribute('open');
      await contents.locator('summary').click();
    }
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
  await expect(legal.getByRole('link')).toHaveText(['Privacy Policy', 'Terms of Service', 'Cancellation & No-Show Policy', 'Accessibility']);
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await view(page, testInfo, 'legal-05-footer');

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
  await context.route(/\/terms$/, (route) => (route.request().resourceType() === 'document' ? route.fulfill({ status: 200, contentType: 'text/html', body: published }) : route.fallback()));
  try {
    await page.goto('/terms');
    await expect(page.getByRole('heading', { level: 1, name: 'The Terms as the shop just published them' })).toBeVisible();
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
      // Next month: outside the late-cancellation window, as most bookings are.
      const month = page.getByTestId('calendar-month');
      const thisMonth = await month.innerText();
      await page.getByRole('button', { name: 'Next month' }).click();
      await expect(month).not.toHaveText(thisMonth);
      await (await firstTime(page)).click();
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

test('Reviews shows Google’s reviews and only links to Yelp; Visit asks people to call about getting in', async ({ page, request }, testInfo) => {
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
  const line = page.getByTestId('visit-accessibility');
  await expect(line).toHaveText("Questions about getting in or around the shop? Call (442) 341-3053 and we'll help.");
  await expect(line.getByRole('link', { name: '(442) 341-3053' })).toHaveAttribute('href', 'tel:+14423413053');
  await expect(page.locator('main')).not.toContainText(/ADA|Wheelchair accessible/);
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
