import { createRequire } from 'node:module';
import type { Page } from '@playwright/test';
import {
  controlledByWorker,
  emulateStandalone,
  expect,
  expectAccessible,
  isDemo,
  isPhone,
  newWorkerVersion,
  phoneSafeArea,
  screenshot,
  test,
  USER_AGENTS,
} from './support.js';

// The web app: installable (the manifest, the icons, and Chrome's own check), its service
// worker controlling the page from the first visit, the app opening offline with the offline
// page for anything it doesn't keep, a new version waiting for a tap on Reload, the Get the app
// page on an iPhone, an Android phone and a computer, the Add to Home Screen bar on phones, and
// the site opened as the app. These run on the site with the real API (playwright.config.ts)
// and on the demo version (playwright.demo.config.ts).

const require = createRequire(import.meta.url);

const PHONE_LINK = 'a[href="tel:+14423413053"]';

test('the manifest is linked and valid, its icons load, and Chrome finds nothing missing to install it', async ({ page, request }) => {
  await page.goto('/');
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/manifest.webmanifest');
  const response = await request.get('/manifest.webmanifest');
  expect(response.headers()['content-type']).toBe('application/manifest+json');
  const manifest = (await response.json()) as { icons: { src: string; sizes: string; purpose: string }[] } & Record<string, unknown>;
  expect(manifest).toMatchObject({
    id: '/',
    name: 'Izzy Clipz',
    short_name: 'Izzy Clipz',
    start_url: '/?source=app',
    scope: '/',
    display: 'standalone',
    orientation: 'portrait',
    background_color: '#000000',
    theme_color: '#000000',
  });
  expect(manifest.icons.map((icon) => `${icon.sizes} ${icon.purpose}`)).toEqual(['192x192 any', '512x512 any', '512x512 maskable']);

  // Every icon, the iPhone's included, is a PNG of the size it says.
  const touchIcon = page.locator('link[rel="apple-touch-icon"]');
  const icons = [...manifest.icons, { src: (await touchIcon.getAttribute('href'))!, sizes: (await touchIcon.getAttribute('sizes'))! }];
  for (const icon of icons) {
    const png = await request.get(icon.src);
    expect(png.status(), icon.src).toBe(200);
    expect(png.headers()['content-type'], icon.src).toBe('image/png');
    const body = await png.body();
    expect(`${body.readUInt32BE(16)}x${body.readUInt32BE(20)}`, icon.src).toBe(icon.sizes);
  }

  // The iPhone's own tags.
  await expect(page.locator('meta[name="apple-mobile-web-app-capable"]')).toHaveAttribute('content', 'yes');
  await expect(page.locator('meta[name="apple-mobile-web-app-status-bar-style"]')).toHaveAttribute('content', 'black');
  await expect(page.locator('meta[name="apple-mobile-web-app-title"]')).toHaveAttribute('content', 'Izzy Clipz');

  // Chrome's own reading: the manifest parses cleanly, and nothing stands in the way of installing.
  await controlledByWorker(page);
  const cdp = await page.context().newCDPSession(page);
  const read = await cdp.send('Page.getAppManifest');
  expect(read.url).toBe(new URL('/manifest.webmanifest', page.url()).href);
  expect(read.errors).toEqual([]);
  expect((await cdp.send('Page.getInstallabilityErrors')).installabilityErrors).toEqual([]);
});

test('the service worker controls the whole site from the first visit, and keeps no one’s appointments', async ({ page }, testInfo) => {
  await page.goto('/');
  await controlledByWorker(page);
  const worker = await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.getRegistration();
    return { scope: registration?.scope, script: navigator.serviceWorker.controller?.scriptURL };
  });
  expect(worker).toEqual({ scope: new URL('/', page.url()).href, script: new URL('/sw.js', page.url()).href });

  // What it keeps: this version's files, and on the real site the shop's public catalog. Nothing from the API besides.
  await page.waitForFunction(async () => (await caches.keys()).some((name) => name.startsWith('izzy-app-')));
  const kept = await page.evaluate(async () => {
    const out: Record<string, string[]> = {};
    for (const name of await caches.keys()) out[name] = (await (await caches.open(name)).keys()).map((r) => new URL(r.url).pathname + new URL(r.url).search);
    return out;
  });
  const files = Object.entries(kept).find(([name]) => name.startsWith('izzy-app-'))![1];
  for (const path of ['/index.html', '/offline.html', '/manifest.webmanifest', '/icon-192.png', '/apple-touch-icon.png']) {
    expect(files.some((key) => key.startsWith(`${path}?__rev=`)), path).toBe(true);
  }
  expect(files.some((key) => /^\/assets\/index-.*\.js$/.test(key))).toBe(true);
  expect(files.some((key) => /^\/assets\/inter-latin-wght-normal-.*\.woff2$/.test(key))).toBe(true);
  expect(files.some((key) => /^\/assets\/storefront-.*\.webp$/.test(key))).toBe(true);
  const fromApi = Object.values(kept)
    .flat()
    .filter((key) => key.startsWith('/api/'));
  expect(fromApi).toEqual(isDemo(testInfo) ? [] : ['/api/catalog']);
});

test('after one visit the app opens offline, and a page it doesn’t keep shows the offline page', async ({ page, context }, testInfo) => {
  await page.goto('/');
  await controlledByWorker(page);
  await expect(page.getByTestId('open-today')).toBeVisible();

  await context.setOffline(true);
  await page.goto('/services');
  await expect(page.getByRole('heading', { level: 1, name: 'Services and prices' })).toBeVisible();
  // The menu still shows, from the copy the app keeps; booking needs the shop, and the bar says how to call.
  await expect(page.getByRole('main').getByText('Haircut', { exact: true }).first()).toBeVisible();
  await expect(page.getByTestId('offline-notice')).toHaveText("You're offline. To book, call the shop: (442) 341-3053");
  await expect(page.getByTestId('offline-notice').locator(PHONE_LINK)).toBeVisible();
  await expectAccessible(page, 'a page opened offline');
  await screenshot(page, testInfo, '30-offline-app');

  await page.goto('/a-new-page');
  await expect(page.getByRole('heading', { level: 1, name: "You're offline." })).toBeVisible();
  await expect(page.locator('.lead')).toHaveText('To book, call the shop: (442) 341-3053');
  await expect(page.getByRole('link', { name: '(442) 341-3053' })).toHaveAttribute('href', 'tel:+14423413053');
  await expect(page.getByRole('link', { name: 'Call the shop' })).toHaveAttribute('href', 'tel:+14423413053');
  await expectAccessible(page, 'the offline page');
  await screenshot(page, testInfo, '31-offline-page');

  // Its way on: the home page, which opens without a connection.
  await page.getByRole('link', { name: 'open the home page' }).click();
  await expect(page.getByRole('heading', { level: 1, name: /Fresh cuts/ })).toBeVisible();
  await context.setOffline(false);
});

test('a new version waits for a tap on Reload, and never reloads the page by itself', async ({ page, request }, testInfo) => {
  await page.goto('/visit');
  await controlledByWorker(page);
  await page.evaluate(() => {
    (window as Window & { stillHere?: boolean }).stillHere = true;
  });
  await newWorkerVersion(request);
  try {
    await page.evaluate(async () => (await navigator.serviceWorker.getRegistration())?.update());
    const bar = page.getByTestId('update-bar');
    await expect(bar).toHaveText('A new version is ready · Reload');
    await expectAccessible(page, 'the new version bar');
    await screenshot(page, testInfo, '32-new-version', { fullPage: false });
    // Waiting, not reloading.
    await page.waitForTimeout(1500);
    expect(await page.evaluate(() => (window as Window & { stillHere?: boolean }).stillHere)).toBe(true);
    expect(await page.evaluate(async () => Boolean((await navigator.serviceWorker.getRegistration())?.waiting))).toBe(true);

    // Tapped: the new version takes over, and the page reloads into it.
    const reloaded = page.waitForEvent('load');
    await bar.getByRole('button', { name: 'Reload' }).click();
    await reloaded;
    expect(await page.evaluate(() => (window as Window & { stillHere?: boolean }).stillHere ?? false)).toBe(false);
    await expect(page.getByRole('heading', { level: 1, name: 'Visit the shop' })).toBeVisible();
    await controlledByWorker(page);
    expect(await page.evaluate(async () => (await navigator.serviceWorker.getRegistration())?.waiting ?? null)).toBeNull();
    await expect(page.getByTestId('update-bar')).toHaveText('');
  } finally {
    await newWorkerVersion(request, true);
  }
});

/** Decodes the QR code on the page with jsQR, as a phone's camera would read it. */
async function readQrCode(page: Page): Promise<string | null> {
  await page.addScriptTag({ path: require.resolve('jsqr/dist/jsQR.js') });
  return page.evaluate(async () => {
    const svg = document.querySelector('svg.qr-code');
    if (!svg) return null;
    const image = new Image();
    image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(svg))}`;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = 400;
    canvas.height = 400;
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#fff';
    context.fillRect(0, 0, 400, 400);
    context.drawImage(image, 20, 20, 360, 360);
    const pixels = context.getImageData(0, 0, 400, 400);
    const read = (window as Window & { jsQR?: (data: Uint8ClampedArray, width: number, height: number) => { data: string } | null }).jsQR;
    return read?.(pixels.data, 400, 400)?.data ?? null;
  });
}

test.describe('Get the app on an iPhone', () => {
  test.use({ userAgent: USER_AGENTS.iphone });

  test('shows Safari’s steps with pictures: Share, Add to Home Screen, Add', async ({ page }, testInfo) => {
    test.skip(!isPhone(testInfo), 'An iPhone is a phone');
    await page.goto('/app');
    await expect(page.getByRole('heading', { level: 1, name: 'Get the app.' })).toBeVisible();
    await expect(page.getByRole('radio', { name: 'iPhone' })).toBeChecked();
    const steps = page.getByTestId('iphone-steps');
    await expect(steps.locator('.install-step__text')).toHaveText([
      'Open this page in Safari.',
      'Tap the Share button.',
      'Scroll down and tap Add to Home Screen.',
      'Tap Add.',
    ]);
    await expect(steps.locator('svg.drawing')).toHaveCount(3);
    await expect(page.getByTestId('phone-code')).toHaveCount(0);
    await expect(page.getByTestId('install-now')).toHaveCount(0);
    await expectAccessible(page, 'Get the app on an iPhone');
    await screenshot(page, testInfo, '20-get-the-app-iphone');

    // The other devices, one tap away.
    await page.getByRole('radio', { name: 'Android' }).check();
    await expect(page.getByTestId('android-steps')).toContainText('Tap Install app.');
    await page.getByRole('radio', { name: 'Computer' }).check();
    await expect(page.getByTestId('computer-steps')).toContainText('Click Install.');
  });
});

test.describe('Get the app on Android', () => {
  test.use({ userAgent: USER_AGENTS.android });

  test('installs with the browser’s own question when Chrome offers it, with Chrome’s menu as the other way', async ({ page }, testInfo) => {
    test.skip(!isPhone(testInfo), 'An Android phone is a phone');
    await page.goto('/app');
    await expect(page.getByRole('radio', { name: 'Android' })).toBeChecked();
    await expect(page.getByTestId('android-steps').locator('.install-step__text')).toHaveText([
      'Open this page in Chrome.',
      'Tap the menu ⋮ at the top right.',
      'Tap Install app.',
      'Tap Install.',
    ]);
    // Chrome offers to install (it waits for some use of the page first, so the test makes the offer).
    await page.evaluate(() => {
      const offer = new Event('beforeinstallprompt', { cancelable: true });
      Object.assign(offer, {
        prompt: () => {
          (window as Window & { asked?: boolean }).asked = true;
          return Promise.resolve();
        },
        userChoice: Promise.resolve({ outcome: 'accepted', platform: 'web' }),
      });
      window.dispatchEvent(offer);
    });
    await expect(page.getByTestId('install-now')).toBeVisible();
    await expect(page.getByRole('heading', { level: 2, name: 'Or use Chrome’s menu' })).toBeVisible();
    await expectAccessible(page, 'Get the app on Android');
    await screenshot(page, testInfo, '21-get-the-app-android');

    await page.getByRole('button', { name: 'Install Izzy Clipz' }).click();
    await expect(page.getByTestId('installed')).toHaveText('Izzy Clipz is installed.Find it on your Home Screen.');
    expect(await page.evaluate(() => (window as Window & { asked?: boolean }).asked)).toBe(true);
    await expect(page.getByTestId('install-now')).toHaveCount(0);
  });
});

test.describe('Get the app on a computer', () => {
  test.use({ userAgent: USER_AGENTS.computer });

  test('has the install steps, and a QR code that opens the page on a phone at this site’s own address', async ({ page }, testInfo) => {
    test.skip(isPhone(testInfo), 'A computer');
    await page.goto('/app');
    await expect(page.getByRole('radio', { name: 'Computer' })).toBeChecked();
    await expect(page.getByTestId('computer-steps').locator('.install-step__text')).toHaveText([
      'Open this page in Chrome or Edge.',
      'Click the install button at the right end of the address bar.',
      'Click Install.',
    ]);
    const address = new URL('/app', page.url()).href;
    await expect(page.getByTestId('phone-code-url')).toHaveText(address.replace(/^https?:\/\//, ''));
    expect(await readQrCode(page)).toBe(address);
    await expectAccessible(page, 'Get the app on a computer');
    await screenshot(page, testInfo, '22-get-the-app-computer');

    // Somewhere else, the code is that address: it's made from wherever the site is open.
    const elsewhere = new URL(page.url());
    elsewhere.hostname = 'localhost';
    await page.goto(new URL('/app', elsewhere).href);
    expect(await readQrCode(page)).toBe(new URL('/app', elsewhere).href);
  });
});

test.describe('the Add to Home Screen bar on phones', () => {
  test.use({ userAgent: USER_AGENTS.android });

  test('shows on the second visit, links to the steps, and stays closed once closed', async ({ page, context }, testInfo) => {
    test.skip(!isPhone(testInfo), 'Phones only');
    await page.goto('/visit');
    await expect(page.getByRole('heading', { level: 1, name: 'Visit the shop' })).toBeVisible();
    await expect(page.getByTestId('install-hint')).toHaveCount(0);
    await page.close();

    // A second visit: a new tab.
    const second = await context.newPage();
    await second.goto('/visit');
    const hint = second.getByTestId('install-hint');
    await expect(hint).toHaveText('Add Izzy Clipz to your Home Screen · How');
    await expectAccessible(second, 'the Add to Home Screen bar');
    await screenshot(second, testInfo, '23-install-hint', { fullPage: false });
    await hint.getByRole('link', { name: 'How to add Izzy Clipz to your Home Screen' }).click();
    await expect(second.getByRole('heading', { level: 1, name: 'Get the app.' })).toBeVisible();
    // Not on Get the app itself.
    await expect(second.getByTestId('install-hint')).toHaveCount(0);
    await second.goBack();
    await second.getByRole('button', { name: 'Hide this' }).click();
    await expect(second.getByTestId('install-hint')).toHaveCount(0);
    await second.close();

    const third = await context.newPage();
    await third.goto('/visit');
    await expect(third.getByRole('heading', { level: 1, name: 'Visit the shop' })).toBeVisible();
    await expect(third.getByTestId('install-hint')).toHaveCount(0);
  });
});

test.describe('opened as the app', () => {
  test.beforeEach(async ({ context }) => {
    await emulateStandalone(context);
  });

  test('keeps clear of the notch and home bar, has Back, says "You’re using the app", and opens other sites outside', async ({ page, context }, testInfo) => {
    const phone = isPhone(testInfo);
    // Instagram's page, without going to Instagram: nothing leaves this computer.
    await context.route('https://www.instagram.com/**', (route) => route.fulfill({ contentType: 'text/html', body: '<title>Instagram</title>' }));
    if (phone) await phoneSafeArea(page);
    await page.goto('/?source=app');
    await expect(page.getByRole('heading', { level: 1, name: /Fresh cuts/ })).toBeVisible();
    await expect(page.locator('html')).toHaveClass(/is-standalone/);

    // The nav reaches up behind the status bar with its links below it, and the footer stops above the home bar.
    const nav = page.getByRole('navigation', { name: 'Izzy Clipz' });
    expect(await nav.evaluate((element) => getComputedStyle(element).paddingTop)).toBe(phone ? '47px' : '0px');
    expect(await page.locator('.globalfooter').evaluate((element) => getComputedStyle(element).paddingBottom)).toBe(phone ? '66px' : '32px');
    await expect(nav.getByRole('link', { name: 'Get the app' })).toHaveCount(0);
    await expect(nav.getByRole('button', { name: 'Back' })).toHaveCount(0);
    await expectAccessible(page, 'Home, opened as the app');
    await screenshot(page, testInfo, '24-app-home', { fullPage: false });

    // No browser Back button around it, so the nav has one.
    await page.getByRole('link', { name: 'See services' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Services and prices' })).toBeVisible();
    await expect(nav.getByRole('button', { name: 'Back' })).toBeVisible();
    await screenshot(page, testInfo, '25-app-services-back', { fullPage: false });
    await nav.getByRole('button', { name: 'Back' }).click();
    await expect(page.getByRole('heading', { level: 1, name: /Fresh cuts/ })).toBeVisible();

    await page.goto('/app');
    await expect(page.getByTestId('using-the-app')).toContainText("You're using the app.");
    await expect(page.getByRole('radio')).toHaveCount(0);
    await expectAccessible(page, 'Get the app, opened as the app');
    await screenshot(page, testInfo, '26-app-get-the-app');

    // Instagram opens outside the app; the app stays where it was. Calls stay calls.
    await page.goto('/visit');
    const [instagram] = await Promise.all([
      context.waitForEvent('page'),
      page.getByRole('link', { name: /Follow @izzy_clipz_barbershop_ on Instagram/ }).click(),
    ]);
    expect(instagram.url()).toBe('https://www.instagram.com/izzy_clipz_barbershop_/');
    expect(new URL(page.url()).pathname).toBe('/visit');
    await instagram.close();
    await expect(page.locator(PHONE_LINK).first()).not.toHaveAttribute('target', /./);
  });
});
