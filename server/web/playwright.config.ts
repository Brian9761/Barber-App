import { defineConfig } from '@playwright/test';

// End-to-end tests: Chromium against the real API on PGlite and the built site,
// both served by e2e/serve.ts (build first: `npm run build`). Every page and the
// booking flow at desktop and phone sizes. Screenshots go to E2E_SHOTS_DIR
// (default test-results/shots).
//
// The tests share one server and one database, so they run one at a time.
// The demo version has its own config (playwright.demo.config.ts), where the web
// app's tests (pwa.spec.ts) run too.

const PORT = Number(process.env.E2E_PORT) || 4173;
const BASE_URL = `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: 'e2e',
  testIgnore: ['demo.spec.ts', 'business-demo.spec.ts'],
  outputDir: process.env.E2E_OUTPUT_DIR || 'test-results',
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: BASE_URL,
    // The shop's own zone, so "today" in the tests is the shop's today.
    timezoneId: 'America/Los_Angeles',
    locale: 'en-US',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    // Downloads (the .ics) are kept for the test to read.
    acceptDownloads: true,
  },
  projects: [
    {
      name: 'desktop',
      use: { browserName: 'chromium', viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 },
    },
    {
      name: 'phone',
      use: { browserName: 'chromium', viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true },
    },
  ],
  webServer: {
    command: 'npm run serve:local',
    url: `${BASE_URL}/api/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stderr: 'pipe',
    env: { E2E_PORT: String(PORT) },
  },
});
