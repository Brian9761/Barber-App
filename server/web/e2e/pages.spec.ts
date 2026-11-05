import type { Locator, Page } from '@playwright/test';
import { expectAccessible, expect, expectFits, expectLogosStandOut, firstTime, isPhone, screenshot, setLiveReviews, tabTo, test, watchOtherSites } from './support.js';

// Every page (the four legal ones too) opens with its one main heading and its title, works
// from the nav on a desktop and a phone, logs nothing as an error, has no serious
// accessibility problems, loads nothing from another site and never links the shop's older
// website. With "reduce motion" nothing moves; in forced colors the controls keep their
// edges, focus rings and states. Screenshots of each.

const PAGES = [
  { path: '/', shot: '01-home', heading: 'Fresh cuts. Booked in seconds.', title: 'Izzy Clipz Barbershop in Oceanside' },
  { path: '/services', shot: '02-services', heading: 'Services and prices', title: 'Services and prices · Izzy Clipz Barbershop' },
  { path: '/barbers', shot: '03-barbers', heading: 'Meet the barbers', title: 'Barbers · Izzy Clipz Barbershop' },
  { path: '/reviews', shot: '04-reviews', heading: 'Reviews', title: 'Reviews · Izzy Clipz Barbershop' },
  { path: '/visit', shot: '05-visit', heading: 'Visit the shop', title: 'Visit · Izzy Clipz Barbershop' },
  { path: '/book', shot: '06-book', heading: 'Pick a service', title: 'Step 1 of 5: Pick a service · Izzy Clipz Barbershop' },
  { path: '/appointments', shot: '07-appointments-empty', heading: 'My appointments', title: 'My appointments · Izzy Clipz Barbershop' },
  { path: '/app', shot: '20-get-the-app', heading: 'Get the app.', title: 'Get the app · Izzy Clipz Barbershop' },
  { path: '/no-such-page', shot: '09-not-found', heading: "This page isn't here.", title: 'Page not found · Izzy Clipz Barbershop' },
  { path: '/privacy', shot: '30-privacy', heading: 'Privacy Policy', title: 'Privacy Policy · Izzy Clipz Barbershop' },
  { path: '/terms', shot: '31-terms', heading: 'Terms of Service', title: 'Terms of Service · Izzy Clipz Barbershop' },
  { path: '/cancellation-policy', shot: '32-cancellation-policy', heading: 'Cancellation & No-Show Policy', title: 'Cancellation & No-Show Policy · Izzy Clipz Barbershop' },
  { path: '/accessibility', shot: '33-accessibility', heading: 'Accessibility Statement', title: 'Accessibility · Izzy Clipz Barbershop' },
] as const;

test.describe('every page', () => {
  // As the shop has it: live reviews from the server (its own test fixtures, Google's and Yelp's); the site shows Google's and links to Yelp.
  test.beforeAll(async ({ request }) => setLiveReviews(request, true));
  test.afterAll(async ({ request }) => setLiveReviews(request, false));

  for (const page of PAGES) {
    test(`${page.path} opens with its heading, title and description`, async ({ page: tab }, testInfo) => {
      const otherSites = watchOtherSites(tab, testInfo);
      await tab.goto(page.path);
      await expect(tab.getByRole('heading', { level: 1, name: page.heading })).toBeVisible();
      // One main heading.
      await expect(tab.locator('h1')).toHaveCount(1);
      await expect(tab).toHaveTitle(page.title);
      await expect(tab.locator('meta[name="description"]')).toHaveAttribute('content', /.{40,}/);
      await expect(tab.locator('meta[property="og:title"]')).toHaveAttribute('content', page.title);
      // The phone number is on every page, and calls the shop.
      await expect(tab.locator('a[href="tel:+14423413053"]').first()).toBeAttached();
      if (page.path === '/') {
        await expect(tab.getByTestId('open-today')).toHaveText(/^(Open today|Closed)/);
        // The rating loads once its tile comes near the screen.
        await tab.getByRole('heading', { name: 'What clients say' }).scrollIntoViewIfNeeded();
        await expect(tab.getByTestId('home-rating')).toContainText('4.9');
        // Never Yelp's rating, though the server sends one: Yelp's reviews are only linked.
        await expect(tab.locator('main')).not.toContainText('on Yelp');
        await tab.evaluate(() => window.scrollTo(0, 0));
      }
      if (page.path === '/reviews') {
        await expect(tab.getByTestId('google-reviews')).toContainText('Reviews from Google Maps');
        // The server sends Yelp's reviews and rating too (its own fixtures): only a plain link shows.
        await expect(tab.getByTestId('yelp-reviews')).toHaveCount(0);
        await expect(tab.getByText('Fixture A.')).toHaveCount(0);
        await expect(tab.getByTestId('reviews-elsewhere').getByRole('link', { name: /Read our reviews on Yelp/ })).toHaveAttribute(
          'href',
          'https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside',
        );
      }
      // The shop's policies from the footer, Privacy first.
      await expect(tab.getByRole('contentinfo').getByRole('navigation', { name: 'Legal' }).getByRole('link').first()).toHaveText('Privacy Policy');
      // Never the shop's older website or its Squire page as if they were this one.
      await expect(tab.locator('a[href*="izzyclipzbarbershop"], a[href*="squire" i]')).toHaveCount(0);
      await expectAccessible(tab, page.path);
      await expectLogosStandOut(tab, page.path);
      await screenshot(tab, testInfo, page.shot);
      // Everything came from this site (the server's reviews have no photos here).
      expect(otherSites, `${page.path} loads nothing from another site`).toEqual([]);
    });
  }

  test('the offline page has no serious accessibility problems, and links the Privacy Policy', async ({ page }) => {
    await page.goto('/offline.html');
    await expect(page.getByRole('heading', { level: 1, name: "You're offline." })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Privacy Policy' })).toHaveAttribute('href', '/privacy');
    await expectAccessible(page, '/offline.html');
    await expectFits(page, '/offline.html');
  });
});

test('every page fits a small phone, 375 pixels wide', async ({ page }, testInfo) => {
  test.skip(!isPhone(testInfo), 'A phone size');
  await page.setViewportSize({ width: 375, height: 812 });
  for (const { path } of PAGES) {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await expectFits(page, `${path} at 375px`);
  }
});

test('the phone number is on the first screen of every page and booking step', async ({ page }, testInfo) => {
  // "Prefer to call?" near the top, so nobody has to scroll past the whole menu to find it.
  for (const path of ['/', '/services', '/barbers', '/reviews', '/visit', '/appointments', '/app', '/book', '/book?barber=carlos-rafael&service=haircut']) {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    const top = await page
      .locator('main a[href="tel:+14423413053"]')
      .evaluateAll((links) => Math.min(...links.map((link) => link.getBoundingClientRect().top + window.scrollY)));
    const screen = page.viewportSize()!.height;
    expect(top, `${path} at ${testInfo.project.name} size: the first number at ${Math.round(top)}px`).toBeLessThan(screen);
  }
});

test('the phone menu keeps Tab inside it while it covers the page', async ({ page }, testInfo) => {
  test.skip(!isPhone(testInfo), 'The menu is for phone sizes');
  await page.goto('/services');
  await page.getByRole('button', { name: 'Menu' }).click();
  await expect(page.getByRole('button', { name: 'Close' })).toHaveAttribute('aria-expanded', 'true');
  for (let i = 0; i < 14; i += 1) {
    await page.keyboard.press('Tab');
    const inNav = await page.evaluate(() => document.activeElement?.closest('nav.globalnav') !== null || document.activeElement === document.body);
    expect(inNav, `Tab ${i + 1} stays in the menu and nav`).toBe(true);
  }
  // Escape closes it, back on Menu, and the page can be reached again.
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: 'Menu' })).toBeFocused();
  expect(await page.evaluate(() => document.getElementById('main')?.hasAttribute('inert'))).toBe(false);
});

test('reviews that can’t be shown say so kindly and link to Google and Yelp', async ({ page }, testInfo) => {
  await page.goto('/reviews');
  await expect(page.getByTestId('reviews-elsewhere')).toContainText("Reviews can't be shown here right now");
  await expect(page.getByRole('link', { name: /See our reviews on Google Maps/ })).toHaveAttribute('href', /google\.com\/maps/);
  await expect(page.getByRole('link', { name: /Read our reviews on Yelp/ })).toHaveAttribute('href', /yelp\.com/);
  await expectAccessible(page, '/reviews without live reviews');
  await screenshot(page, testInfo, '04-reviews-unavailable');
});

test('the nav goes to every page and back home', async ({ page }, testInfo) => {
  await page.goto('/');
  const nav = page.getByRole('navigation', { name: 'Izzy Clipz' });
  const destinations = [
    { link: 'Services', heading: 'Services and prices' },
    { link: 'Barbers', heading: 'Meet the barbers' },
    { link: 'Reviews', heading: 'Reviews' },
    { link: 'Visit', heading: 'Visit the shop' },
    { link: 'My appointments', heading: 'My appointments' },
  ];
  for (const destination of destinations) {
    if (isPhone(testInfo)) {
      // On a phone the links are in the menu, next to the Book pill.
      await expect(nav.getByRole('link', { name: destination.link, exact: true })).toBeHidden();
      await nav.getByRole('button', { name: 'Menu' }).click();
      await expect(nav.getByRole('button', { name: 'Close' })).toHaveAttribute('aria-expanded', 'true');
      if (destination.link === 'Services') {
        await expectAccessible(page, 'the phone menu');
        await screenshot(page, testInfo, '10-menu-open', { fullPage: false });
      }
    }
    await nav.getByRole('link', { name: destination.link, exact: true }).click();
    await expect(page.getByRole('heading', { level: 1, name: destination.heading })).toBeVisible();
    await expect(page).toHaveURL(new RegExp(`/${destination.link === 'My appointments' ? 'appointments' : destination.link.toLowerCase()}$`));
    if (!isPhone(testInfo)) await expect(nav.getByRole('link', { name: destination.link, exact: true })).toHaveAttribute('aria-current', 'page');
    // The menu closes once the page changes.
    await expect(nav.getByRole('button', { name: 'Close' })).toHaveCount(0);
  }
  await nav.getByRole('link', { name: 'Book an appointment' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Pick a service' })).toBeVisible();
  await nav.getByRole('link', { name: 'Izzy Clipz', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Fresh cuts. Booked in seconds.' })).toBeVisible();

  // The footer's "For the shop": Izzy Clipz Business, signed in with a code from the app (e2e/business.spec.ts).
  await page.getByRole('contentinfo').getByRole('link', { name: 'Izzy Clipz Business' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
});

test('Home’s actions lead to booking and the services', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('main').getByRole('link', { name: 'See services', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Services and prices' })).toBeVisible();
  await page.getByRole('link', { name: 'Book Haircut', exact: true }).click();
  await expect(page.getByTestId('step-count')).toHaveText('Step 2 of 5');
  await expect(page.getByRole('heading', { level: 1, name: 'Pick a barber' })).toBeVisible();
  await page.goto('/barbers');
  await page.getByRole('link', { name: 'Book with Carlos' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Pick a service' })).toBeVisible();
  await expect(page.getByText('Booking with')).toBeVisible();
  await expect(page.getByText('Includes mustache & eyebrows, plus straight-razor detail and styling.').first()).toBeVisible();
});

test('the site’s files are served as they are, and every other address opens the site', async ({ request }) => {
  const robots = await request.get('/robots.txt');
  expect(robots.ok()).toBe(true);
  expect(await robots.text()).toContain('Allow: /');
  const deepLink = await request.get('/book/time');
  expect(deepLink.headers()['content-type']).toContain('text/html');
  const missingAsset = await request.get('/assets/missing-file.js');
  expect(missingAsset.status()).toBe(404);
  const catalog = await request.get('/api/catalog');
  expect(catalog.headers()['cache-control']).toBe('public, max-age=300');
  expect((await catalog.json()).shop.phone.display).toBe('(442) 341-3053');
});

test('in Windows High Contrast, light or dark, every logo takes the system’s colors', async ({ page }, testInfo) => {
  test.skip(isPhone(testInfo), 'High Contrast is a Windows computer setting');
  for (const colorScheme of ['dark', 'light'] as const) {
    await page.emulateMedia({ forcedColors: 'active', colorScheme });
    for (const path of ['/', '/visit', '/business']) {
      await page.goto(path);
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
      await expectLogosStandOut(page, `${path} in High Contrast, ${colorScheme}`);
    }
  }
});

/** How a control is drawn now: its border, underline, background and outline. */
function drawn(control: Locator) {
  return control.evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      border: style.borderTopStyle === 'none' ? 0 : parseFloat(style.borderTopWidth),
      underline: style.textDecorationLine.includes('underline'),
      background: style.backgroundColor,
    };
  });
}

/** The system's highlight color in forced colors, as the browser paints it. */
function highlightColor(page: Page): Promise<string> {
  return page.evaluate(() => {
    const probe = document.createElement('div');
    probe.style.setProperty('forced-color-adjust', 'none');
    probe.style.setProperty('background-color', 'Highlight');
    document.body.append(probe);
    const color = getComputedStyle(probe).backgroundColor;
    probe.remove();
    return color;
  });
}

test('in forced colors (Windows High Contrast), the controls keep their edges, focus rings and states', async ({ page, phone }, testInfo) => {
  test.skip(isPhone(testInfo), 'High Contrast is a Windows computer setting');
  await page.emulateMedia({ forcedColors: 'active' });

  // The choices are cards with an edge.
  await page.goto('/book?service=haircut');
  const any = page.getByTestId('any-barber');
  expect((await drawn(any)).border, 'a choice’s edge').toBeGreaterThanOrEqual(1);
  await any.click();

  // Each time has an edge; the picked time and the picked day take the system's highlight.
  const highlight = await highlightColor(page);
  const chip = await firstTime(page);
  expect((await drawn(chip)).border, 'a time’s edge').toBeGreaterThanOrEqual(1);
  await chip.click();
  expect((await drawn(chip)).background, 'the picked time').toBe(highlight);
  expect((await drawn(page.locator('.calendar__day[aria-pressed="true"]'))).background, 'the picked day').toBe(highlight);
  // Buttons keep an edge, and the focus ring shows (tabTo checks it on the way).
  const next = page.getByRole('button', { name: 'Continue' });
  expect((await drawn(next)).border, 'a button’s edge').toBeGreaterThanOrEqual(1);
  await tabTo(page, next);
  await page.keyboard.press('Enter');

  // Fields have edges; Remember me is the browser's own checkbox.
  for (const label of ['Name', 'Mobile number']) {
    expect((await drawn(page.getByRole('textbox', { name: label, exact: true }))).border, label).toBeGreaterThanOrEqual(1);
  }
  await page.getByRole('textbox', { name: 'Name', exact: true }).fill('Hana Contrast');
  await page.getByRole('textbox', { name: 'Mobile number' }).fill(phone);
  await next.click();
  // Buttons that look like links are underlined, so they don't read as plain words.
  expect((await drawn(page.getByRole('button', { name: 'Change service' }))).underline, '“Change”').toBe(true);

  // The device picker on Get the app has a frame; its picked choice an outline in the system's highlight.
  await page.goto('/app');
  expect((await drawn(page.locator('.segmented').first())).border, 'the device picker’s frame').toBeGreaterThanOrEqual(1);
  // "On this page" on a legal page has a frame too.
  await page.goto('/privacy');
  expect((await drawn(page.locator('.legal-toc'))).border, '“On this page”').toBeGreaterThanOrEqual(1);
});

test('with “reduce motion”, nothing on the site moves', async ({ page }, testInfo) => {
  test.skip(isPhone(testInfo), 'Once is enough: the same styles at every size');
  await page.emulateMedia({ reducedMotion: 'reduce' });
  for (const path of ['/', '/book', '/visit', '/privacy', '/app', '/business']) {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    const moving = await page.evaluate(() =>
      Array.from(document.querySelectorAll('*'))
        .flatMap((element) =>
          [null, '::before', '::after'].flatMap((pseudo) => {
            const style = getComputedStyle(element, pseudo);
            const longest = Math.max(...`${style.transitionDuration},${style.animationDuration}`.split(',').map((d) => parseFloat(d) || 0));
            return style.animationName !== 'none' || longest > 0 ? [`${element.tagName.toLowerCase()}.${element.getAttribute('class') ?? ''}${pseudo ?? ''}`] : [];
          }),
        )
        .slice(0, 5),
    );
    expect(moving, `${path}: nothing moves`).toEqual([]);
    expect(await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior)).toBe('auto');
  }
});

test('the icons, the home-screen icon and the share image are the logo’s, at the sizes the page says', async ({ page, request }) => {
  await page.goto('/');
  const head = page.locator('head');
  const pictures = [
    ...(await head.locator('link[rel="icon"], link[rel="apple-touch-icon"]').evaluateAll((links) =>
      links.map((link) => ({ href: link.getAttribute('href')!, size: link.getAttribute('sizes')! })),
    )),
    {
      href: (await head.locator('meta[property="og:image"]').getAttribute('content'))!,
      size: `${await head.locator('meta[property="og:image:width"]').getAttribute('content')}x${await head.locator('meta[property="og:image:height"]').getAttribute('content')}`,
    },
  ];
  expect(pictures.map((picture) => picture.href)).toEqual(['/favicon-32.png', '/favicon-48.png', '/apple-touch-icon.png', '/og-image.png']);
  await expect(head.locator('meta[name="twitter:image"]')).toHaveAttribute('content', '/og-image.png');
  const manifestHref = (await head.locator('link[rel="manifest"]').getAttribute('href'))!;
  const manifest = await request.get(manifestHref);
  expect(manifest.headers()['content-type']).toBe('application/manifest+json');
  const { icons } = (await manifest.json()) as { icons: { src: string; sizes: string }[] };
  pictures.push(...icons.map((icon) => ({ href: icon.src, size: icon.sizes })));
  for (const { href, size } of pictures) {
    const response = await request.get(href);
    expect(response.status(), href).toBe(200);
    expect(response.headers()['content-type'], href).toBe('image/png');
    // A PNG's width and height are in its first chunk, after the 8-byte signature and the chunk's 8-byte head.
    const png = await response.body();
    expect(`${png.readUInt32BE(16)}x${png.readUInt32BE(20)}`, href).toBe(size);
  }
});
