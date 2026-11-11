import { defineConfig } from '@playwright/test';

// End-to-end tests of the demo version (build it first: `npm run build:demo`):
// dist-demo/ served as the static site its vercel.json describes, by
// e2e/serve-demo.ts, with no API at all. The web app's tests (pwa.spec.ts) run
// here as well as on the site with the real API, and the demo's own
// (demo.spec.ts): booking and cancelling without a single request to /api;
// Izzy Clipz Business's (business-demo.spec.ts), also without one; the legal
// pages and what they say the website does (legal.spec.ts), as on the real site;
// and the fee rules the Cancellation & No-Show Policy promises (fees.spec.ts).
// Screenshots go to E2E_SHOTS_DIR (default test-results/shots), named
// demo-desktop-… and demo-phone-….

const PORT = Number(process.env.E2E_DEMO_PORT) || 4174;
const BASE_URL = `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: 'e2e',
  testMatch: ['pwa.spec.ts', 'demo.spec.ts', 'business-demo.spec.ts', 'legal.spec.ts', 'fees.spec.ts'],
  outputDir: process.env.E2E_OUTPUT_DIR || 'test-results/demo',
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never', outputFolder: 'playwright-report/demo' }]] : [['list']],
  use: {
    baseURL: BASE_URL,
    // The shop's own zone, so "today" in the tests is the shop's today.
    timezoneId: 'America/Los_Angeles',
    locale: 'en-US',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    acceptDownloads: true,
  },
  projects: [
    {
      name: 'demo-desktop',
      use: { browserName: 'chromium', viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 },
    },
    {
      name: 'demo-phone',
      use: { browserName: 'chromium', viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true },
    },
  ],
  webServer: {
    command: 'npm run serve:demo',
    url: `${BASE_URL}/manifest.webmanifest`,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    stderr: 'pipe',
    env: { E2E_DEMO_PORT: String(PORT) },
  },
});
