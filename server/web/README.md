# Izzy Clipz website

The shop's website: Home, Services, Barbers, Reviews, Visit, booking in five steps, My appointments, and a placeholder for the Business area. It's built into `../public` and served by the same Vercel project as the API, so it calls `/api/…` on its own origin and needs no settings. Vite 6, React 18.3, TypeScript (strict), React Router 6; every version is pinned in `package-lock.json`.

## Commands

Run them here, in `server/web` (Node 22.13 or later).

| Command | What it does |
|---|---|
| `npm ci` | Installs the exact packages in `package-lock.json`. |
| `npm run dev` | The site on http://localhost:5173 with live reload. `/api` goes to the API's own dev server on http://localhost:3000, so start that first (`npm run dev` in `server/`). |
| `npm run build` | Type-checks and builds into `../public` (what Vercel serves). |
| `npm test` | Unit tests (Vitest, Testing Library, jsdom) against the server's contract fixtures. |
| `npm run typecheck` | The site's code, and the build, test and end-to-end files. |
| `npm run serve:local` | The built site and the real API on an in-memory PGlite at http://127.0.0.1:4173, a fresh empty database every start. Needs `npm ci` in `server/` too. Good for trying the whole thing on a computer. |
| `npm run e2e` | Playwright end-to-end tests in Chromium (build first). |

## How it's put together

- `src/pages/`: one file per page. `src/booking/`: the five steps (`flow.ts` is the booking's state machine), the confirmation and the way back from Stripe's card page.
- `src/api/`: the API client (`client.ts`: every failure becomes an `ApiError` with a plain sentence) and the JSON types, field for field as the server writes them.
- `src/lib/`: the rules the pages share, each with unit tests: tokens (32 random bytes in base64url, like the apps), US phone numbers, prices and lengths (like the Kit), the shop's clock and calendar (always the shop's time zone, whatever the visitor's computer says), the late-cancellation warning, `.ics` files and what the browser keeps.
- `src/styles/`: the design tokens (`tokens.css`: the apps' colors, the type scale, spacing and radii) and the shared pieces. The font is the apps' own: the system font first (SF Pro on Apple devices), then Inter, self-hosted from `@fontsource-variable/inter` and only downloaded where SF Pro isn't there. Nothing loads from another site.
- `src/assets/images/`: the app's photos (`IzzyClipz/Resources/Assets.xcassets`) as WebP. `public/`: the favicons, the share image and `robots.txt`.

The site never moves on its own: no carousels, no autoplay, no animated page changes, and none at all when the system asks for reduced motion. Text is at least 17px, everything you can tap at least 44px, and every page has the phone number.

## What the browser keeps

- `localStorage` `izzy.appointments.v1`: each appointment booked here, with its manage token (what My appointments lists and cancels with), until 30 days after it ended.
- `localStorage` `izzy.details.v1`: name, number and email, only with "Remember me on this computer".
- `izzy.card.v1`: the card token and the card's brand and last four digits, in `localStorage` with "Remember me", otherwise in `sessionStorage`.
- `sessionStorage`: the booking in progress (`izzy.booking.v1`, so a reload or the trip to Stripe's card page doesn't lose it), the card checkout in progress, and the last booking for "You're booked".

## The card on file

When the shop's no-show protection needs a card, Review's "Add a card" makes a card token, calls `POST /api/cards/checkout` with `returnTo: "web"` and `X-Card-Token`, keeps the token and the booking in this tab, and sends the browser to Stripe's page. Stripe comes back through the server to `/book/card-return?status=saved&session_id=…` (or `?status=cancelled`); that page saves the card with `POST /api/cards` and goes back to Review, which then shows "Visa •••• 4242 · Change" and lets the client book.

## End-to-end tests

`e2e/serve.ts` serves the built site and the API's own code on PGlite (through `@electric-sql/pglite-socket`, like the server's tests) with the migrations and the catalog's barbers, from one Node server routed like Vercel. Playwright starts it by itself (or reuses one already running on the port, except in CI). `/__e2e/…` is test plumbing that only this server has: live reviews from the server's own fixtures, no-show protection on and off, and a stand-in for Stripe's card page (there's no Stripe key; nothing leaves the computer).

The tests run at 1440×900 and 390×844: every page and the nav, a booking with Any barber through to My appointments and cancelling, a time someone else takes mid-booking, booking with the keyboard alone, the card on file, no errors in the browser's console, no serious axe-core findings, and nothing wider than the screen. Screenshots of every page and step go to `E2E_SHOTS_DIR` (default `test-results/shots`). `E2E_PORT` changes the port (4173).

Playwright needs its Chromium: `npx playwright install chromium` once (CI uses `npx playwright install --with-deps chromium`). Where it's already installed, point `PLAYWRIGHT_BROWSERS_PATH` at it.
