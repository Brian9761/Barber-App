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
- `src/assets/images/`: the app's photos (`IzzyClipz/Resources/Assets.xcassets`) as WebP.
- `src/assets/logo.ts`: the shop's logo as a vector, the same tracing the apps' logo images are drawn from. `src/components/Logo.tsx` draws it in the text color, so it's sharp at any size: white on the black bands (the nav, the hero, the sticker on the storefront photo) and near-black on the white and light gray ones (the footer, the Visit tile, Business). Only the nav's logo has a name for screen readers, "Izzy Clipz", as the link to Home; the others are decoration.
- `public/`: the icons made from the logo (32 and 48 px for browser tabs, 180 px for iPhone home screens, 512 px in `manifest.webmanifest` for Android's), the share image link previews show (`og-image.png`, the logo on black, 1200×630) and `robots.txt`.

The site never moves on its own: no carousels, no autoplay, no animated page changes, and none at all when the system asks for reduced motion. Text is at least 17px, everything you can tap at least 44px, and every page has the phone number.

## What the browser keeps

- `localStorage` `izzy.appointments.v1`: each appointment booked here, with its manage token (what My appointments lists and cancels with), until 30 days after it ended. Not the client's name, number, email or note.
- `localStorage` `izzy.details.v1`: name, number and email, only with "Remember me on this computer".
- `izzy.card.v1`: the card token, the card's brand and last four digits, and the number (E.164) of the client who added it, in `localStorage` with "Remember me", otherwise in `sessionStorage` until it's booked.
- `sessionStorage`: the booking in progress (`izzy.booking.v1`, so a reload or the trip to Stripe's card page doesn't lose it), the card checkout in progress, and the last booking for "You're booked".

A computer can be shared, so "Remember me" starts off unless this computer already remembers the client, a saved card is only ever offered to the number that added it, and a booking that's done (or a new one) doesn't carry the last client's details or note. "Not you? Forget me on this computer" on Your details, and "Forget me on this computer" on My appointments, clear what's kept here; the appointments stay booked with the shop.

## The card on file

When the shop's no-show protection needs a card, Review's "Add a card" makes a card token, calls `POST /api/cards/checkout` with `returnTo: "web"` and `X-Card-Token`, keeps the token and the booking in this tab, and sends the browser to Stripe's page. Stripe comes back through the server to `/book/card-return?status=saved&session_id=…` (or `?status=cancelled`); that page saves the card with `POST /api/cards` and goes back to Review, which then shows "Visa •••• 4242 · Change" and lets the client book. Only the card page this tab opened last is saved (an older one, reached through the browser's history, says so), and "Try again" shows only when trying again can work (the shop wasn't reached, or asked to wait). If the server answers `card_required` anyway (the shop turned protection on meanwhile), Review checks the policy again and forgets only a card it sent.

## End-to-end tests

`e2e/serve.ts` serves the built site and the API's own code on PGlite (through `@electric-sql/pglite-socket`, like the server's tests) with the migrations and the catalog's barbers, from one Node server routed like Vercel. Playwright starts it by itself (or reuses one already running on the port, except in CI). `/__e2e/…` is test plumbing that only this server has: live reviews from the server's own fixtures, no-show protection on and off, and a stand-in for Stripe's card page (there's no Stripe key; nothing leaves the computer). Its Save and Back go to the `success_url` and `cancel_url` the server gave it, so the server's own way back to the website is tested too; on a server without that way back (`returnTo: "web"`), the test of coming back from the card page is skipped and says why.

The tests run at 1440×900 and 390×844: every page and the nav, a booking with Any barber through to My appointments and cancelling, a time someone else takes mid-booking, booking with the keyboard alone, the card on file, no errors in the browser's console, no serious axe-core findings, nothing wider than the screen, every logo standing out from what's behind it (never white on a light band), and the icons and share image at the sizes the page says. Screenshots of every page and step go to `E2E_SHOTS_DIR` (default `test-results/shots`). `E2E_PORT` changes the port (4173).

Playwright needs its Chromium: `npx playwright install chromium` once (CI uses `npx playwright install --with-deps chromium`). Where it's already installed, point `PLAYWRIGHT_BROWSERS_PATH` at it.
