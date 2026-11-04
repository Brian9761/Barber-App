# Izzy Clipz website

The shop's website: Home, Services, Barbers, Reviews, Visit, booking in five steps, My appointments, Get the app, and a placeholder for the Business area. It's built into `../public` and served by the same Vercel project as the API, so it calls `/api/…` on its own origin and needs no settings. Vite 6, React 18.3, TypeScript (strict), React Router 6; every version is pinned in `package-lock.json`.

It's also a web app anyone can install: on an iPhone with Safari's Share → Add to Home Screen, on Android with Chrome's Install, on a computer with Chrome's or Edge's install button. It then opens full screen with the shop's icon, and works offline as far as it can (see [The web app](#the-web-app)). A demo version books in the browser without the shop's server, so it can be published on its own (see [The demo version](#the-demo-version)).

## Commands

Run them here, in `server/web` (Node 22.13 or later).

| Command | What it does |
|---|---|
| `npm ci` | Installs the exact packages in `package-lock.json`. |
| `npm run dev` | The site on http://localhost:5173 with live reload. `/api` goes to the API's own dev server on http://localhost:3000, so start that first (`npm run dev` in `server/`). |
| `npm run dev:demo` | The demo version with live reload: no API needed. |
| `npm run build` | Type-checks and builds into `../public` (what Vercel serves), service worker included. |
| `npm run build:demo` | Type-checks and builds the demo version into `dist-demo/`, with its own `vercel.json`. |
| `npm test` | Unit tests (Vitest, Testing Library, jsdom) against the server's contract fixtures. |
| `npm run typecheck` | The site's code, the service worker, and the build, test and end-to-end files. |
| `npm run serve:local` | The built site and the real API on an in-memory PGlite at http://127.0.0.1:4173, a fresh empty database every start. Needs `npm ci` in `server/` too. Good for trying the whole thing on a computer. |
| `npm run serve:demo` | The built demo at http://127.0.0.1:4174, hosted the way its `vercel.json` says. |
| `npm run e2e` | Playwright end-to-end tests in Chromium against the site and the real API (build first). |
| `npm run e2e:demo` | The same for the demo version (`npm run build:demo` first). |

## How it's put together

- `src/pages/`: one file per page. `src/booking/`: the five steps (`flow.ts` is the booking's state machine), the confirmation and the way back from Stripe's card page.
- `src/api/`: the API client and the JSON types, field for field as the server writes them. Pages call `api` from `client.ts`; `http.ts` is the client over the network (every failure becomes an `ApiError` from `errors.ts`, with a plain sentence), and `backend.ts` says which one the site uses: the demo build swaps it for `src/demo/backend.ts`.
- `src/pwa/`: the web app's pieces: registering the service worker and the "A new version is ready · Reload" bar, the offline notice, the browser's install offer, the device and browser, opened as the app or not, the Add to Home Screen bar, the drawings on Get the app and its QR code. `src/sw/`: the service worker itself (`sw.ts`) and its rules (`routes.ts`).
- `src/demo/`: the demo version's stand-in for the shop (`api.ts`), its sample reviews and its notice.
- `src/lib/`: the rules the pages share, each with unit tests: tokens (32 random bytes in base64url, like the apps), US phone numbers, prices and lengths (like the Kit), the shop's clock and calendar (always the shop's time zone, whatever the visitor's computer says), the late-cancellation warning, `.ics` files and what the browser keeps.
- `src/styles/`: the design tokens (`tokens.css`: the apps' colors, the type scale, spacing and radii) and the shared pieces. The font is the apps' own: the system font first (SF Pro on Apple devices), then Inter, self-hosted from `@fontsource-variable/inter` and only downloaded where SF Pro isn't there. Nothing loads from another site.
- `src/assets/images/`: the app's photos (`IzzyClipz/Resources/Assets.xcassets`) as WebP.
- `src/assets/logo.ts`: the shop's logo as a vector, the same tracing the apps' logo images are drawn from. `src/components/Logo.tsx` draws it in the text color, so it's sharp at any size: white on the black bands (the nav, the hero, the sticker on the storefront photo) and near-black on the white and light gray ones (the footer, the Visit tile, Business). Only the nav's logo has a name for screen readers, "Izzy Clipz", as the link to Home; the others are decoration.
- `public/`: the icons made from the logo on black, rendered from the shop's vector logo (32 and 48 px for browser tabs, 180 px for iPhone home screens, 192 and 512 px in `manifest.webmanifest`, and a 512 px one with room around the logo for Android to crop to a circle or rounded square), the manifest, the offline page (`offline.html`), the share image link previews show (`og-image.png`, the logo on black, 1200×630) and `robots.txt`.

The site never moves on its own: no carousels, no autoplay, no animated page changes, and none at all when the system asks for reduced motion. Text is at least 17px, everything you can tap at least 44px, and every page has the phone number.

## The web app

- **Installable.** `public/manifest.webmanifest` names it Izzy Clipz, opens it full screen from `/?source=app` with the whole site in scope, black, with the icons above; `index.html` has the iPhone's tags (`apple-touch-icon`, `apple-mobile-web-app-capable` and `mobile-web-app-capable`, a black status bar, the title). That's all Chrome, Edge and Android need to offer to install it (a name, the 192 and 512 icons, a start page, a display mode); iPhones take any site to the Home Screen and open it as an app with these tags. Opened from the Home Screen the page reaches the screen's edges (`viewport-fit=cover`), and the nav, the menu, the footer and the page's sides keep clear of the notch, the status bar and the home bar (`env(safe-area-inset-*)`, in `tokens.css`).
- **The service worker** (`src/sw/`, built into `/sw.js` at the end of every build with the list of the build's files). It keeps this version's page, scripts, styles, Inter's Latin fonts, the shop's photos, the icons, the manifest and the offline page. The site's pages open from that copy, also offline. A page this version doesn't know is asked for on the network, and without a connection `offline.html` answers: "You're offline. To book, call the shop: (442) 341-3053", with a tap-to-call link. From the API it keeps only the shop's public catalog (`/api/catalog`: menu, team and hours), network first and the last copy offline, so the app opens with them. Nothing with a token or personal data is ever kept: appointments, cards and the owner's area always go to the network, as do the reviews (Google's terms) and the open times. The demo's worker never asks `/api` at all.
- **New versions** install quietly next to the one in use and wait. The page shows "A new version is ready · Reload", and only a tap on Reload makes the new one take over and reloads the page; an app left open looks for one whenever it comes back on screen. `/sw.js` is served with `Cache-Control: no-cache` (`../vercel.json`).
- **Offline**, a line under the nav says how to book by phone, and My appointments shows nothing it can't check with the shop (it could have changed): it says so, and checks again once the connection is back.
- **Get the app** (`/app`, in the nav and the footer) opens on the visitor's own device, from what the browser says it is, with the others one tap away: on an iPhone, Safari's Share, Add to Home Screen and Add (and what to do inside Instagram or in another browser); on Android, an Install button with the browser's own question when Chrome offers one (`beforeinstallprompt`), and Chrome's menu otherwise; on a computer, Chrome's or Edge's install button or the steps, and Add to Dock for Safari on a Mac. Each step has a drawing of what to tap in the site's style. On a computer, a QR code (made in the browser with `uqr`, from the address the site is open at) opens it on a phone. Opened as the app, it just says "You're using the app".
- **On phones**, "Add Izzy Clipz to your Home Screen · How" shows under the nav after the first booking or from the second visit, never in the app, and stays closed once closed.
- **Opened as the app** (`display-mode: standalone`, or Safari's `navigator.standalone`; the page gets the `is-standalone` class), there's no browser around it, so the nav has a Back button on every page but Home and the booking steps, "Get the app" leaves the nav, and links to other sites (maps, Instagram, reviews) open outside the app. Calls work as they are.

## The demo version

`npm run build:demo` (or `VITE_DEMO_MODE=1 vite build`) builds the same site into `dist-demo/`, to publish before the shop's server is ready. The normal build is untouched by it.

- Its API calls are answered in the browser by `src/demo/api.ts`, which has the API client's own interface: the build puts `src/demo/backend.ts` in place of `src/api/backend.ts`, so the demo has no code that calls `/api`, and the normal build none of the demo's.
- Like the apps' `FakeShopAPI`, it uses the shop's real catalog (the server's own `data/catalog.json`, built in), works out the open times from the shop's hours, slot interval, lead time and 60-day window on the shop's clock (`America/Los_Angeles`, the real time, so daylight saving changes are handled), and gives every barber two or three sample bookings each open day, the same every time, so some times are taken. Bookings and cancellations follow the server's rules (a retry with the same manage token gets the same appointment back, 3 upcoming appointments per number, cancelling until the start, the late-cancellation question for a booking with a card on file) and are kept in `localStorage` (`izzy.demo.v1`), so they're still there after a reload. No-show protection is off, as on the server until the owner turns it on: no card, no Stripe. The reviews are samples ("Sample reviewer A") with no rating.
- Home, Review and "You're booked" say "Demo version: bookings aren't sent to the shop. To book for real, call (442) 341-3053."; Reviews says the reviews are samples.
- `dist-demo/vercel.json` (from `vercel.demo.json`) hosts it as a static site of its own: files first, the page for every other path but `/api/` and `/assets/`, `/sw.js` with `Cache-Control: no-cache`, the manifest as `application/manifest+json`, a year's caching for `/assets/`, and `X-Robots-Tag: noindex`, so the demo doesn't show up in searches for the shop. Deploy the folder as it is, with no build step.

## What the browser keeps

- `localStorage` `izzy.appointments.v1`: each appointment booked here, with its manage token (what My appointments lists and cancels with), until 30 days after it ended. Not the client's name, number, email or note.
- `localStorage` `izzy.details.v1`: name, number and email, only with "Remember me on this computer".
- `izzy.card.v1`: the card token, the card's brand and last four digits, and the number (E.164) of the client who added it, in `localStorage` with "Remember me", otherwise in `sessionStorage` until it's booked.
- `sessionStorage`: the booking in progress (`izzy.booking.v1`, so a reload or the trip to Stripe's card page doesn't lose it), the card checkout in progress, the last booking for "You're booked", and whether this tab's visit is counted (`izzy.visitCounted.v1`).
- `localStorage` `izzy.visits.v1` (how many visits) and `izzy.installHint.v1` (the Add to Home Screen bar was closed): only for that bar.
- The service worker's caches: `izzy-app-<version>` (this version's files; older versions' go once a new one takes over) and `izzy-catalog-v1` (the shop's public catalog). Nothing personal.
- In the demo only, `localStorage` `izzy.demo.v1`: the bookings made in it, as the shop's server would keep them (with the name and number typed in), until 60 days after they ended.

A computer can be shared, so "Remember me" starts off unless this computer already remembers the client, a saved card is only ever offered to the number that added it, and a booking that's done (or a new one) doesn't carry the last client's details or note. "Not you? Forget me on this computer" on Your details, and "Forget me on this computer" on My appointments, clear what's kept here; the appointments stay booked with the shop.

## The card on file

When the shop's no-show protection needs a card, Review's "Add a card" makes a card token, calls `POST /api/cards/checkout` with `returnTo: "web"` and `X-Card-Token`, keeps the token and the booking in this tab, and sends the browser to Stripe's page. Stripe comes back through the server to `/book/card-return?status=saved&session_id=…` (or `?status=cancelled`); that page saves the card with `POST /api/cards` and goes back to Review, which then shows "Visa •••• 4242 · Change" and lets the client book. Only the card page this tab opened last is saved (an older one, reached through the browser's history, says so), and "Try again" shows only when trying again can work (the shop wasn't reached, or asked to wait). If the server answers `card_required` anyway (the shop turned protection on meanwhile), Review checks the policy again and forgets only a card it sent.

## End-to-end tests

Two configs: `playwright.config.ts` runs the site with the real API (`npm run e2e`), and `playwright.demo.config.ts` the demo version on `e2e/serve-demo.ts`, which serves `dist-demo/` the way its `vercel.json` says and counts any request to `/api` (`npm run e2e:demo`; its port is `E2E_DEMO_PORT`, 4174). `e2e/pwa.spec.ts` runs in both: the manifest linked and valid with Chrome finding nothing missing to install it (`Page.getInstallabilityErrors`), every icon at its size, the service worker controlling the page from the first visit and keeping nothing from the API but the catalog, the app opening offline and the offline page for a new route, a new version waiting for a tap on Reload (`/__e2e/new-version` changes `/sw.js`), Get the app with an iPhone's, an Android phone's and a computer's user agent (the QR code read back with `jsqr`, at two addresses), the Add to Home Screen bar, and the site opened as the app (Chromium can't be put in that display mode, so the page is told so where it asks, and the screen's safe area is set through the DevTools protocol). `e2e/demo.spec.ts` books, reloads and cancels on the demo watching every request from the pages and the service worker, and the demo's server, for `/api`.


`e2e/serve.ts` serves the built site and the API's own code on PGlite (through `@electric-sql/pglite-socket`, like the server's tests) with the migrations and the catalog's barbers, from one Node server routed like Vercel. Playwright starts it by itself (or reuses one already running on the port, except in CI). `/__e2e/…` is test plumbing that only this server has: live reviews from the server's own fixtures, no-show protection on and off, and a stand-in for Stripe's card page (there's no Stripe key; nothing leaves the computer). Its Save and Back go to the `success_url` and `cancel_url` the server gave it, so the server's own way back to the website is tested too; on a server without that way back (`returnTo: "web"`), the test of coming back from the card page is skipped and says why.

The tests run at 1440×900 and 390×844: every page and the nav, a booking with Any barber through to My appointments and cancelling, a time someone else takes mid-booking, booking with the keyboard alone, the card on file, no errors in the browser's console, no serious axe-core findings, nothing wider than the screen, every logo standing out from what's behind it (never white on a light band, in Windows High Contrast too), and the icons and share image at the sizes the page says. Screenshots of every page and step go to `E2E_SHOTS_DIR` (default `test-results/shots`). `E2E_PORT` changes the port (4173).

Playwright needs its Chromium: `npx playwright install chromium` once (CI uses `npx playwright install --with-deps chromium`). Where it's already installed, point `PLAYWRIGHT_BROWSERS_PATH` at it.
