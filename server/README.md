# Izzy Clipz API

The small server behind the Izzy Clipz app and the Izzy Clipz Business owner app: live booking with each barber's calendar, the owner's schedule, time off and walk-ins, the shop's own products (photos in Vercel Blob), Google and Yelp reviews, and in-person card payments with Stripe Terminal (Tap to Pay on iPhone).

TypeScript on Vercel Functions (Node 24), Postgres on Neon, region `pdx1`. One function (`api/index.ts`) serves every route through a small router, so the Hobby plan's 12-function limit never matters.

## Layout

| Path | What |
|---|---|
| `api/index.ts` | The Vercel Function: `export default { fetch }`. |
| `src/app.ts` | Every route of API v1. |
| `src/router.ts`, `src/http.ts` | Router (404/405), JSON responses, the error shape, body limits. |
| `src/availability.ts`, `src/booking.ts`, `src/appointments.ts` | Slot math, the booking transaction, appointment endpoints. |
| `src/timeoff.ts`, `src/products.ts`, `src/payments.ts`, `src/reviews.ts`, `src/cron.ts` | Owner time off, products and photos, Stripe, reviews, daily cleanup. |
| `src/auth.ts`, `src/ratelimit.ts`, `src/validation.ts`, `src/time.ts` | Owner key, manage tokens, rate limits, input rules, time zone math. |
| `src/catalog.ts`, `data/catalog.json` | The menu, team and hours, exported from IzzyClipzKit. |
| `src/db.ts`, `src/migrate.ts`, `migrations/*.sql`, `scripts/migrate.ts` | Postgres pool, migrations and the barber seed. |
| `src/production.ts` | Real dependencies (pg pool, Stripe, Blob, fetch). Tests swap in fakes. |
| `scripts/dev.ts`, `scripts/smoke.ts` | A local server without Vercel, and the end-to-end check to run after a deploy. |
| `public/` | A placeholder page. Keep it: without `public/`, Vercel publishes the source files as static files. |
| `test/` | Vitest suites, fixtures and the contract fixtures the Swift Kit decodes. |

## Environment variables

Set them in the Vercel project (as **Sensitive**). For the scripts (`migrate`, `dev`, `smoke`), put them in `.env.local`: copy `.env.example`, or run `vercel env pull .env.local`. Real environment variables win over the file, and empty values count as unset.

| Variable | Needed for | Notes |
|---|---|---|
| `DATABASE_URL` | Everything that touches the database | Neon's **pooled** URL. Added by the Neon integration. |
| `DATABASE_URL_UNPOOLED` | `npm run migrate` | Neon's direct URL (schema changes shouldn't go through PgBouncer). Added by the integration. |
| `OWNER_KEY` | Owner endpoints | At least 32 characters, or owner endpoints answer 503 `owner_not_configured`. Make one with `openssl rand -base64 48`. The owner pastes it into the Business app once. |
| `CRON_SECRET` | `GET /api/cron/daily` | Random, 16+ characters. Vercel Cron sends it as `Authorization: Bearer …`. Unset means the cron route always answers 401. |
| `BLOB_READ_WRITE_TOKEN` | Product photos | Added when a Blob store is connected (the SDK can also use the store's OIDC credentials). |
| `GOOGLE_PLACES_API_KEY` | Live Google reviews | Places API (New), restricted to that API. Unset: the app gets `available: false` and a Google Maps link. |
| `GOOGLE_PLACE_ID` | Google reviews | Default `ChIJGz5HChRv3IARYJJy_6jyRm8`. |
| `GOOGLE_DAILY_LIMIT` | Google reviews | Calls per shop-local day, default `30` (stays inside the 1,000 free calls a month). `0` turns Google off. |
| `YELP_API_KEY` | Yelp reviews | Only if the shop pays for the Yelp Places API. Unset: `available: false` and the Yelp page link. |
| `YELP_BUSINESS_ID` | Yelp reviews | Default `izzy-clipz-barbershop-oceanside` (the alias works as an id). |
| `STRIPE_SECRET_KEY` | Payments | `sk_test_…` or `sk_live_…` (restricted `rk_` keys work too). Unset: payment endpoints answer 503 `stripe_not_configured`. |
| `STRIPE_TERMINAL_LOCATION_ID` | Payments | `tml_…`. Passed to connection tokens; the Business app also needs it to connect Tap to Pay. |
| `STRIPE_WEBHOOK_SECRET` | `POST /api/stripe/webhook` | `whsec_…` from the webhook endpoint. Optional: without it the webhook answers 503 and `…/complete` is the only way payments get recorded. |
| `PG_POOL_MAX` | Optional | Pool size per function instance, default 5. |

## Local development

Node 22.12 or later (`.nvmrc` says 24, which is what Vercel runs).

```sh
cd server
npm ci
npm test              # vitest: everything, against PGlite (no database to install)
npx tsc --noEmit      # strict type check (also what `npm run build` does on Vercel)
```

To run the API itself:

```sh
DATABASE_URL=postgres://… OWNER_KEY=… npm run migrate   # once
DATABASE_URL=postgres://… OWNER_KEY=… npm run dev       # http://localhost:3000/api/health
```

`npm run dev` (`scripts/dev.ts`) serves the same app with the production dependencies over plain Node HTTP and reads `.env.local` if it exists, so it needs no Vercel login. `vercel dev` works too once the project is linked.

## Tests

`npm test` runs every suite against **PGlite** (Postgres 18 compiled to WASM, with `btree_gist`), served over the Postgres wire protocol by `@electric-sql/pglite-socket`, so the production `pg` pool code runs unchanged. PGlite has one session, so the test pool has one connection and concurrent requests queue for it; the race tests still fire requests at the same moment.

To run the same tests against a **real Postgres** (true concurrency, pool of 5), point `TEST_DATABASE_URL` at a role that can create databases. Each test file gets its own throwaway database:

```sh
TEST_DATABASE_URL=postgres://postgres@127.0.0.1:5432/postgres npm test
```

CI (`.github/workflows/server.yml`) does both, on Ubuntu: PGlite on Node 22 and 24, and Postgres 17 on Node 24.

What's covered: availability against fixtures exported from the Kit's `BookingCalendar` (both 2026 DST changes, Sundays, the 60-day edge, past days, late "today"), booking (happy path, overlaps rejected by the exclusion constraint, back to back, cancellation frees the slot, any-barber assignment, time off, lead time, window, hours, validation), races (2 and 10 bookings for one slot at once, two any-barber bookings, two bookings for one phone), rate limits, manage tokens, safe retries with the app's own token (a retry after success, the same token for another booking, malformed tokens, copies of one request racing, retries and the rate limits), every owner endpoint including 401/503, products with a fake Blob, Stripe with a fake client and real webhook signatures, Google and Yelp normalization from recorded fixtures, "nothing from Google is stored", the Yelp 12/24-hour rules, the cron job, the router's 404/405, migrations, and the server's own time zone not mattering.

### Fixtures

- `data/catalog.json` and `test/fixtures/kit-slots.json` are generated from IzzyClipzKit, so the server books with exactly the app's menu, ids, hours and slot rules. Offering ids are the Kit's `Offering.id` (`<barber>/<squire item id>`); `firstAvailable` comes from `Catalog.firstAvailableOption(forService:)`; weekday keys are the Kit's `Weekday` (1 = Sunday … 7 = Saturday). The Kit's `CatalogExport` test fails if `catalog.json` drifts; regenerate it from the Kit, then run `npm run migrate` so the barber list follows.
- `test/fixtures/google/*.json` and `test/fixtures/yelp/*.json` follow the response formats in Google's Place Details (New) and Yelp's Places API reference. Their names and texts are obviously test data, not real reviews.
- `test/fixtures/contract/*.json` are one example of every response type (and `errors/<code>.json` of every error code), written by the real handlers in `test/contract.test.ts` after checking them against strict schemas of the contract. The Swift Kit decodes the same files. If a handler's output changes on purpose, regenerate them with `UPDATE_CONTRACT_FIXTURES=1 npm test` and commit the diff.

### Smoke test after a deploy

```sh
npm run smoke -- https://izzy-clipz-api.vercel.app            # or SMOKE_BASE_URL
SMOKE_OWNER_KEY=… npm run smoke -- https://izzy-clipz-api.vercel.app
```

`scripts/smoke.ts` checks health, books the last start time of a day near the end of the 60-day window ("Smoke test", a 555-01xx number) with a manage token of its own, retries the booking with the same token and checks it gets the same appointment back, checks it left availability, reads it back with its manage token, cancels it and checks the slot came back. With `SMOKE_OWNER_KEY` (the server's `OWNER_KEY`; there's no separate test-only key) it also checks the owner schedule and cancels through the owner API if anything fails midway. `.github/workflows/server-smoke.yml` runs it by hand or after each successful production deployment, using the `API_BASE_URL` repository variable and the optional `SMOKE_OWNER_KEY` secret.

## Migrations

```sh
DATABASE_URL_UNPOOLED=postgres://… npm run migrate    # or with .env.local from `vercel env pull`
```

Applies `migrations/NNN_name.sql` in order, each in its own transaction, recorded with a checksum in `schema_migrations`. Running it again does nothing; two runs at once are serialized by an advisory lock. It refuses to continue if an applied file was edited: add a new numbered file instead. It then upserts the barbers from `data/catalog.json` (barbers no longer listed stay in the table, marked inactive, because old bookings point at them).

Run it once when the database is created, after every new migration, and after every catalog change. It isn't part of the Vercel build, so preview deployments can't change the production schema.

## Deploy

1. **Project**: a Vercel project on this repo with **Root Directory = `server`** and framework **Other**. `vercel.json` sets the region (`pdx1`), the `/api/*` rewrite to the one function, its 30 s limit and the daily cron. `package.json` `engines` selects Node 24.
2. **Database**: add **Neon** from the Vercel Marketplace in region **`pdx1`** (it can't be changed later), with Neon Auth off, connected to Production, Preview and Development. Leave preview branching off at first. Then run `npm run migrate` with the new `DATABASE_URL_UNPOOLED`.
3. **Photos**: create a **public** Blob store in `pdx1` and connect it to the project.
4. **Secrets**: add `OWNER_KEY`, `CRON_SECRET` and, when ready, the Google, Yelp and Stripe variables above. Redeploy after changing variables.
5. **Stripe** (when the shop's account is connected): create a Terminal Location for the shop and set `STRIPE_TERMINAL_LOCATION_ID`. Add a webhook endpoint at `https://<domain>/api/stripe/webhook` with API version `2026-10-28.endive` (stripe-node 23's) for `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`, `payment_intent.processing` and `payment_intent.requires_action`, and set `STRIPE_WEBHOOK_SECRET`.
6. **Check**: `GET https://<domain>/api/health` → `{ "ok": true, "version": "4.0.0" }`, then `npm run smoke -- https://<domain>`. Point the apps at the production domain, not at a per-deployment URL (those are behind Deployment Protection).

Vercel's Hobby plan is for non-commercial use only; a shop taking bookings and payments needs Pro. Pro also allows an hourly cron (see the Yelp note below).

## How it behaves

- **Times**: the API speaks UTC instants (`2026-11-02T18:00:00Z`, no fractional seconds) and shop-local days (`2026-11-02`). All day and hour math happens in the catalog's time zone (`America/Los_Angeles`) with Luxon, never in the server's own zone, so daylight saving changes are handled by tzdata.
- **Availability** follows the Kit's `BookingCalendar`: start times every 30 minutes from opening, ending by closing, at least 30 minutes from now, today through today + 60 days, minus the barber's booked or completed appointments and time off (theirs or the whole shop's). Every requested day is listed, with no slots when there's nothing to book. "Any barber" uses the catalog's `firstAvailable` offerings: a start is open when one of those barbers is free for their own item's length, and `barberIds` lists the free ones in team order.
- **Booking** is one transaction with no global lock: the barber rows are share-locked (time off takes them exclusively, so a booking and new time off can't interleave), time off is checked, and the exclusion constraint `appointments_no_overlap` rejects overlaps (`23P01` → 409 `slot_taken`). "Any barber" picks the free barber with the fewest live bookings that day, ties in team order, and moves to the next one if the constraint says it was just taken. Customers must pick one of the calendar's start times. The shop may book any minute inside opening hours, including "now" or earlier today, with no lead time; seconds are dropped.
- **Limits**: 5 booking attempts per IP per hour (counted in 10-minute buckets of a sliding hour, after the request passes validation; a retry of a booking that went through isn't an attempt; the IP is stored only as a hash), and 3 upcoming booked appointments per phone number (shop bookings count too). Both answer 429 `rate_limited`. The shop's own bookings have no IP limit. Consider one Vercel WAF rate-limit rule on `/api/*` as an outer guard.
- **Manage tokens**: 32 random bytes, base64url (43 characters), returned once at booking. The app may make its own and send it as `X-Manage-Token` on `POST /api/appointments` (see safe retries); otherwise the server makes one. Only the SHA-256 is stored (unique per appointment) and it's compared in constant time. A missing `X-Manage-Token` is 401; a wrong token or unknown id is 404, so ids can't be probed. Customers can cancel until the appointment starts.
- **Safe retries**: the app's own manage token doubles as the booking's idempotency key, so a retry after a lost answer (a flaky mobile network) can't book twice or get `slot_taken` for the client's own appointment. If an appointment already has that token and the request asks for the same target in the same way (the same `offeringId`, or the same `serviceId` with `barberId: "any"`), the same start and the same phone number, the answer is 200 with `{ appointment, manageToken }` (the same token, the appointment as it is now, even if it has been cancelled since); the name, email and note aren't compared. The same token with other details is 400 `invalid_request` ("That booking token was already used."). A token that isn't exactly 32 bytes in canonical base64url is 400 too. Retries are answered before the time rules and the IP limit, so they work after the lead time has passed and once the hour's attempts are used up. Two copies of one request racing make one appointment: the unique index on `manage_token_hash` (or the barber's overlap constraint) stops the second insert, and it answers like a retry. Shop bookings ignore the header.
- **Owner auth**: `Authorization: Bearer <OWNER_KEY>`, compared as SHA-256 digests in constant time.
- **Reviews**: Google is fetched live on every `GET /api/reviews` (field mask `rating,userRatingCount,reviews,googleMapsUri`) and passed through in Google's order; nothing from Google is stored, only our own daily call counter in `api_usage`. Over the daily limit, unconfigured or failing, Google comes back `available: false` with the Maps link; after a failure the server waits a minute before calling Google again (10 minutes for Yelp, serving its cached copy meanwhile), so a slow or broken API doesn't hold up every visitor. Yelp (only with a key) is cached in `yelp_cache`, refreshed when it's 12 hours old, served stale only while it's under 24 hours old (if Yelp is down), and deleted at 24 hours on every read. The daily cron also purges the whole Yelp cache, because a once-a-day job that runs up to an hour late can't otherwise bound how long an unread row sits; on Pro, change the cron to hourly to tighten that. Every response is `Cache-Control: no-store`.
- **Payments**: the server creates every PaymentIntent (`allowed_payment_method_types: ['card_present']`, `capture_method: 'automatic'`, USD), so the app can't change the amount. `POST /api/owner/payments/:id/complete` asks Stripe for the PaymentIntent and records its status; only `succeeded` marks the appointment paid (the paid amount is the sum of its succeeded payments). The webhook does the same from Stripe's side, and a late event can't undo `succeeded` or `canceled`.
- **Errors** always look like `{ "error": { "code": "slot_taken", "message": "Someone just booked that time. Pick another." } }`, with messages written for the person using the app. Unexpected failures are logged (no request bodies or personal data) and answer 500 `server_error`.

### Contract details worth knowing

- `POST /api/appointments` takes an optional `X-Manage-Token` header (the app's own manage token, 32 random bytes in base64url) and answers 201 for a new booking or 200 for a retry of one that went through (see safe retries above). Without it, nothing changes.
- `invalid_request` also covers 405 (wrong method, with an `Allow` header), 413 (body too large: 16 KB for JSON, 4 MB for photos) and 415 (photo that isn't `image/jpeg`).
- `POST /api/owner/payments/:id/complete` answers 200 with the payment and Stripe's current `status`; the app should treat only `"succeeded"` as paid.
- `GET /api/owner/availability`: the same query and answer as `GET /api/availability`, with the owner key and without the lead time, so a walk-in can take the next slot that hasn't started yet.
- `GET /api/owner/me`: `stripe.locationId` is the Terminal location the owner app connects Tap to Pay to (`STRIPE_TERMINAL_LOCATION_ID`), `null` until Stripe is configured.
- `GET /api/availability`: `from` defaults to today and must be within a year of it; `days` defaults to 1 (max 31). `serviceId` + `barberId=any` works for the services listed in the catalog's `firstAvailable` (those at least two barbers share); for the others it's a 400 and the app should ask for a barber.
- `GET /api/owner/appointments`, `/api/owner/time-off` and `/api/owner/payments` take shop-local days: `date`, or `from` and `to` (inclusive; at most 62 days, or 366 for time off), defaulting to today. Time off is listed when it overlaps those days.
- `POST /api/owner/time-off` accepts `barberId` missing or `null` for the whole shop. Blocking time over existing appointments keeps them; it only stops new bookings.
