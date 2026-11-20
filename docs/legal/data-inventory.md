# Data inventory

This file records what the Izzy Clipz website, web apps, iPhone apps and server actually do with personal data, as read from the code. It backs the Privacy Policy and the other documents in this folder. Where a fact comes from a vendor rather than from our code, the vendor's page is cited at the end.

- **Checked:** November 5, 2026.
- **Code read:**
  - `v5/int` at `9910eb4`, re-checked at `815b1e8` (the commits in between change only UI tests): both iPhone apps, IzzyClipzKit and the server.
  - `v5/webapp-business` at `83a4835`, re-checked at `f06ae57` (the commits in between change only wording in the Business area's Settings page and its tests): the website and web apps. The branch is now on GitHub.
- **Branch notes:**
  - Paths marked **(web)** existed only on `v5/webapp-business` then. That branch has since been merged into `v5/int`.
  - The server is the same on both branches, with four exceptions: `server/src/website.ts` (web only), the website's build and headers in `server/vercel.json` (web only), the website's extra catalog content (barbers' bios, titles and Instagram handles) in `server/data/catalog.json` (web only), and one rounding detail when cancelling (int only).
  - The database migrations are identical on both branches.
- **Re-checked after two independent reviews,** the same day: the new facts are marked in sections 2, 6, 8 and 9, and the gaps they added are G12 to G18 in section 11.
- **Built since this check** (on `v5/int`, November 2026): the gaps the documents depend on (G1, G2, G3, G5, G12 to G18) and the November 14 legal check's code items (OWNER-CHECKLIST.md §3, items 19 to 22) are in the code. Sections 2 to 4 still describe the code as read on November 5, except where a line says "as built". Where they differ, the code wins.
- **Keep it current:** check this file again whenever code that stores, sends or deletes data changes, and before changing the Privacy Policy.

## At a glance

- **What clients give:** their name, mobile number and an optional note. The website also asks for an optional email. These are kept on the shop's server with each appointment. On November 5, nothing deleted them. **As built, the daily job removes them 12 months after the appointment** (`server/src/retention.ts`), or sooner when a client asks, with the owner's privacy tools (`npm run privacy:forget`). The appointment stays, without them.
- **Cards:**
  - Card numbers never reach the shop's apps or server. Clients type them on Stripe's page or tap their card on the barber's iPhone.
  - For a saved card, the server keeps only the brand, last 4 digits, expiry and Stripe's ids.
  - Stripe keeps the card itself, plus **the email the client types on Stripe's page**.
  - On November 5, nothing deleted saved cards. As built, the server deletes a card at Stripe (it detaches the card and deletes its Customer) once the card has expired, gone 12 months without being used for a booking, or been removed by the client or saved without "Remember me", as soon as no booking still needs it (`server/src/retention.ts`). A card saved on a Stripe account the server can't use any more (the shop changed how it connects to Stripe) isn't deleted at Stripe: the server only logs a warning, and the shop has to delete it in that account's Stripe Dashboard. Either way, the server's row stays, with the brand, last 4 and expiry but without Stripe's ids. The Checkout Session, with the email typed on Stripe's page, can't be deleted.
- **What the shop's own code doesn't do:** no analytics, ads, tracking, data sales, or marketing emails or texts. The one exception is the Business app (staff only): it includes Stripe's Tap to Pay software, which reports approximate location and usage to Stripe.
- **The website:**
  - It sets **one functional cookie**. Everything else it keeps stays in the browser, for the client's own convenience.
  - It loads no third-party scripts, styles or fonts.
  - **Reviewers' photos load from Google's servers** (on November 5, from Yelp's too). As built, Yelp's reviews are only linked, never shown (G16).
- **IP addresses:** our code doesn't store them, except as an unsalted hash used for rate limits, deleted within about 2 days. Vercel processes IP addresses in its own logs.
- **Main gaps** (details in section 11):
  - On November 5: no retention period for clients' details; saved cards never deleted at Stripe; no tooling to answer requests for a copy, a correction or deletion; the client's name in Tap to Pay payment descriptions, and the receipt email asked for before the card payment and kept; the Business app's App Store privacy answers; and, added after the reviews, G12 to G18.
  - As built, the code fixes all of them but the App Store answers: clients' details are removed 12 months after the appointment and saved cards are deleted at Stripe (G1, G2); the shop has tools to answer requests for a copy, a correction or deletion (G3); Tap to Pay descriptions leave out the client's name (G5); and G12 to G18 are in the code, including the email receipt offered only after the payment, its address passed to Stripe and not kept (G14), and the gallery photos gone from the website and the client app (G17).
  - The App Store privacy answers are written out in `README.md` and the apps' privacy manifests; the owner enters them in App Store Connect (G11; OWNER-CHECKLIST.md §4).
  - Still open, recommended but not promised: G7, G8, G10 and G19.

## 1. The systems and where they run

| System | What it is | Runs on | Region |
|---|---|---|---|
| Server (`server/`) | The API: booking, cancelling, the owner's area, payments and fees, reviews, products. It's one function, `server/api/index.ts`. | Vercel Functions, region `pdx1` (`server/vercel.json`) | US (Oregon) |
| Database | Postgres, holding every table in section 4 | Neon, added through the Vercel Marketplace in `pdx1` (`server/README.md`, deployment step 2) | US (Oregon) |
| Product photos | Pictures of the shop's products | Vercel Blob, a public store in `pdx1` (`server/src/production.ts`; `server/README.md`, step 3) | US (Oregon), served through Vercel's CDN |
| Website and web apps (web) | The site, the installable client web app, and Izzy Clipz Business at `/business` | Built into `server/public` and served by the same Vercel project, so the site calls `/api` on its own address (`server/vercel.json` (web)) | Vercel CDN |
| Demo website | Today's public demo at https://izzy-clipz.vercel.app (up on November 5, 2026). It books only inside the browser. | A static site with its own `server/web/vercel.json` (web). It never calls `/api`. | Vercel CDN |
| Izzy Clipz (iPhone, `com.izzyclipz.app`) | The client app | Talks only to the shop's API (`IzzyAPIBaseURL` in `project.yml`: `https://izzy-clipz-api.vercel.app`, which had no deployment on November 5, 2026, so a placeholder for now) | n/a |
| Izzy Clipz Business (iPhone, `com.izzyclipz.business`) | The shop's app | Talks to the shop's API, and to Stripe through Stripe's Terminal SDK 6.0.0 (`project.yml`) | n/a |
| Daily job | Clean-up | Vercel Cron, `17 11 * * *` UTC, calling `GET /api/cron/daily` (`server/vercel.json`, `server/src/cron.ts`). On Vercel's Hobby plan it can run up to 59 minutes late. | n/a |

## 2. Clients' data, item by item

Each item covers:

- what the data is and where it's collected;
- where and how it's stored, and why;
- how long it's kept, and whether any code deletes it;
- who receives it;
- what the client can see, change or delete.

### 2.1 Name

- **What:** the client's name, 1 to 60 characters (`personName` in `server/src/validation.ts`; checked again in `server/migrations/001_init.sql`).
- **Collected:**
  - On "Your details" in the client app (`IzzyClipz/Features/Booking/BookingDetailsView.swift`).
  - On "Your details" on the website (`server/web/src/booking/DetailsStep.tsx` (web)).
  - By staff, for walk-ins and phone bookings (`IzzyClipzBusiness/Features/NewBooking/NewBookingView.swift`).
  - Optionally, at checkout for a walk-in sale (`server/web/src/business/pages/today/Checkout.tsx` (web)).
- **Stored:**
  - In `appointments.customer_name`, exactly as typed.
  - Copied to `sales.customer_name`, and into a card checkout's ticket, `payments.sale_draft` (`server/src/sales.ts`, `server/migrations/006_sales.sql`).
  - In `payments.description` for a Tap to Pay payment with no note: the description then reads "Haircut with Carlos for <name>" (`IzzyClipzBusiness/Payments/CheckoutModel.swift`).
- **Why:** so the shop knows who's coming. It's shown on the schedule, at checkout and on receipts.
- **How long:** forever. No code deletes or anonymizes appointments, sales or payments.
- **Who receives it:**
  - The shop, through the Business app and through computers signed in to Izzy Clipz Business.
  - Vercel and Neon, as hosts.
  - Stripe, inside Tap to Pay payment descriptions (see 2.10). It isn't sent to Stripe for saved cards or for fees.
- **Client control:**
  - The client can see it in their appointment (`GET /api/appointments/:id`).
  - Nobody can edit it after booking. The client has no way to, and the owner's `PATCH /api/owner/appointments/:id` only changes the appointment's status (`server/src/appointments.ts`).
  - The client can't delete it.

### 2.2 Mobile number

- **What:** a US number, stored in E.164 format, like `+14425550123` (`normalizeUSPhone` in `server/src/validation.ts`).
- **Collected:** in the same places as the name. It's required when clients book for themselves and optional for walk-ins.
- **Stored:**
  - In `appointments.customer_phone`, as plain text.
  - On the website, also in the browser alongside a saved card (see 5.1).
- **Why:**
  - To reach the client about the appointment.
  - To recognize a retry of the same booking (`sameBooking` in `server/src/appointments.ts`).
  - To limit each number to 3 upcoming appointments (`enforcePhoneLimit` in `server/src/booking.ts`).
- **How long:** forever.
- **Who receives it:**
  - The shop and the hosts.
  - Staff can call or text the number from the Business app. The Call and Text buttons open the iPhone's own Phone and Messages apps (`IzzyClipzBusiness/Features/Schedule/AppointmentDetailView.swift`).
  - No code sends text messages.
- **Client control:** the same as for the name.

### 2.3 Email (website only, optional)

- **Collected:**
  - Only through an optional field on the website's "Your details" (web).
  - The client app and the Business app don't ask for an email.
  - The server accepts one on both booking routes.
- **Stored:** in `appointments.customer_email`. Staff see it on the appointment (Business app and website).
- **Why:** nothing in the code sends email. The Privacy Policy limits its use to contacting the client about the appointment. See G9.
- **How long:** forever.
- **Who receives it:** the shop and the hosts.
- **Other emails:** two other emails are separate from this one. One is a receipt email entered at Tap to Pay (2.10); the other is the email typed on Stripe's card page (2.7).

### 2.4 Note for the barber

- **Collected:** optionally, up to 300 characters (`server/src/validation.ts`), in the client app, on the website and for walk-ins.
- **Stored:** in `appointments.note`.
- **How long:** forever.
- **Who receives it:** the shop and the hosts.
- **Note:** it's free text, so clients may type anything, including health details such as a scalp condition. The Privacy Policy asks them not to.

### 2.5 What was booked, and what happened

- **What:**
  - the service and the barber;
  - start and end times;
  - the price as shown;
  - whether "any barber" was chosen;
  - the status: booked, cancelled, completed or no-show;
  - who cancelled, and who booked (the client or the shop);
  - when the client cancelled (`customer_cancelled_at`);
  - payment status and amount;
  - the checkout's total and method.

  These columns are defined in `server/migrations/001_init.sql`, `002`, `004` and `006`.
- **Why:** to run the schedule and the cancellation and no-show rules, and for the owner's analytics.
- **How long:** forever. Once the name and number are removed, these records are no longer about a person. Until then, they form a visit and no-show history linked to the client.

### 2.6 Manage token (the client's key to their booking)

- **What:** 32 random bytes that the app or website creates for each booking. The token lets the client look up and cancel that booking.
- **On the iPhone:**
  - Stored in the Keychain, service `com.izzyclipz.app.manage-tokens`. It can be read after the iPhone's first unlock, and it moves to a new iPhone with an encrypted backup (`IzzyClipz/Services/SecretStore.swift`, `IzzyClipz/App/AppDelegate.swift`).
  - Bookings not yet confirmed are kept under the item `pending-bookings`, each with its retry key, which includes the number. There are at most 10, and each stays until it's confirmed or its start time has passed (`IzzyClipz/Stores/AppointmentStore.swift`).
- **On the website:** kept in `izzy.appointments.v1` and in the `izzy_appointments` cookie (see 5.1).
- **On the server:** only the token's SHA-256 hash (`appointments.manage_token_hash`; `server/src/auth.ts`).
- **How long:**
  - On the device: until 30 days after the appointment ends (`AppointmentStore.keepDays`, and `KEEP_DAYS` in `server/web/src/lib/storage.ts` (web)).
  - The hash on the server: forever.

### 2.7 Card on file (no-show protection)

This applies only once the owner has turned no-show protection on and Stripe is set up. Protection is off until the owner turns it on (`DEFAULT_NO_SHOW_SETTINGS` in `server/src/noshow.ts`).

- **Collected by Stripe, on Stripe's own page.** This is Stripe Checkout in setup mode, and nothing is charged.
  - The app opens the page in a private `ASWebAuthenticationSession`, which shares no cookies with Safari (`IzzyClipz/Services/WebCardSaver.swift`). The website sends the browser to the page (web).
  - The page asks for the card number, expiry and security code.
  - It also asks for an **email address**. The server creates the Stripe Customer without an email, and Stripe's API reference says that in that case "Checkout will set the email entered during the session on the Customer".
  - It may also ask for the name on the card and a country and ZIP code, because billing address collection is left at Stripe's default, `auto`.
  - Only `card` payments are allowed (Apple Pay counts as a card), so Stripe's Link service shouldn't be offered.
  - *Confirm these fields once on a card page in test mode.*
- **What the server sends to Stripe** (`server/src/cards.ts`):
  - A Customer with only a description ("Izzy Clipz client (card for no-show protection)") and metadata. It carries no name, number or email.
  - A Checkout Session that shows the policy text, with the SHA-256 hash of the client's card token in its metadata. The page expires after 60 minutes (`CHECKOUT_MINUTES`).
- **What the server stores:**
  - In `saved_cards` (`server/migrations/004_no_show_protection.sql` and `005`):
    - the card token's SHA-256 hash;
    - the Checkout Session id;
    - Stripe's Customer and PaymentMethod ids;
    - the card's brand, last 4 digits, and expiry month and year;
    - whether it's a live or test card;
    - when it was saved;
    - the connected Stripe account.
  - Each protected booking also copies the card's brand and last 4 digits (`appointments.card_brand`, `card_last4`, `saved_card_id`).
- **On the iPhone:**
  - Stored in the Keychain, service `com.izzyclipz.app.saved-card`, item `no-show-card`. It stays on this iPhone only and is never included in a backup (`KeychainSecretStore.savedCard()`).
  - It's kept only when "Remember me" is on. Otherwise the card is held in memory for this booking only (`IzzyClipz/Stores/SavedCardStore.swift`).
  - "Remember me" starts on in the app (`BookingDetailsInProgress.start` in `IzzyClipz/App/AppRouter.swift`), and with a card the note under it says "your card stays saved". See G12.
- **On the website:** `izzy.card.v1`, together with the number of the client who added the card. It's in `localStorage` with "Remember me" on, and in `sessionStorage` otherwise; without "Remember me" it's also forgotten once the booking is made (see 5.1).
- **Why:** to charge the fee the client agreed to, if the barber decides to.
- **How long:** **forever**, both for the server's row and for the Customer and card at Stripe.
  - No code deletes them, and the server's Stripe client has no call for it (`server/src/deps.ts`).
  - "Remove card" and "Forget my details" in the app, and "Forget me" on the website, clear only the device. See G2.
- **Who receives it:**
  - Stripe, as the payment processor. In connect mode, this is the shop's own connected Stripe account.
  - The shop, which can see the Customer, its email, and the card's brand, last 4 digits and expiry in its Stripe Dashboard.
  - The developer, technically: the server's Stripe key can read and act on the shop's account. In connect mode it's the developer's own Connect platform key, which makes every call on the connected account (`server/README.md`).
- **What deleting can't remove:** the completed Checkout Session keeps what the client typed on Stripe's page (the email, and any name or ZIP code). Stripe's API can create, update, retrieve, list and expire Checkout Sessions, but not delete them, so that email stays in the shop's Stripe account even after the Customer is deleted (G2).
- **Unfinished card pages (as built, November 20, 2026):** each card page is recorded when it's made, in `card_checkouts` (migration 011: the Checkout Session, Customer and Stripe account ids, test or live mode, and times; no personal data). Saving the card closes the row. A page still open 22 hours after it was made (the page lasts 60 minutes; the rest is time for the apps' and the website's retries) is taken up by the daily job (`purgeUnfinishedCheckouts` in `server/src/retention.ts`), which asks Stripe to detach its card, if the page was finished, and to delete its Customer. The row then keeps no customer id, and a late save of that page is refused ("This card page has expired. Add your card again."). So a card Stripe kept when adding it didn't finish is gone within 2 days.
- **Cards the server can't reach (as built):** a saved card, or an unfinished card page, on a Stripe account the server can no longer use (the shop changed how it connects to Stripe, or switched its key between test and live) is removed here, so it can't book or be charged, but keeps its Stripe ids (`stripe_unreachable_at` on `saved_cards` and `card_checkouts`). Settings › Stripe, in Izzy Clipz Business and in the website's Business area, lists each one under "Cards to delete in Stripe" with its customer id; once the shop deletes that customer in the old account and taps Deleted in Stripe, the ids are cleared.

### 2.8 The client's agreement to the policy

- **Stored** with the appointment (`server/migrations/004_no_show_protection.sql`):
  - `no_show_policy`: the exact text the client was shown, up to 1,200 characters;
  - `no_show_consent_at`: the time of booking;
  - `no_show_fee_cents` and `late_cancel_window_minutes`.
- The server refuses a booking whose text doesn't match today's policy (`policy_changed`, `server/src/cards.ts`).
- The API never returns `no_show_policy` or `no_show_consent_at`, so neither the client nor the shop can see them in the apps today. The privacy tools (G3) must export them, because the documents promise a copy on request.
- **How long:** forever.

### 2.9 Fees charged to a card on file

- **Stored:**
  - On the appointment: the fee's status, attempts, reason and PaymentIntent id; Stripe's reason for a decline, in plain words (`no_show_fee_message`); and when it was charged.
  - A `payments` row of kind `no_show_fee` or `late_cancel_fee` (`server/src/noshowfee.ts`).
- **Sent to Stripe:**
  - the amount;
  - the Customer and PaymentMethod;
  - a description such as "No-show fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM" (`feeDescription`);
  - the appointment's id, the fee's kind and the attempt number, as metadata.

  No name or number is sent. The receipt email is added only after the fee has gone through (see Receipts).
- **Rules (as built, November 20, 2026):**
  - at most one fee per appointment, and only within 7 days after the appointment's start (`FEE_DEADLINE_DAYS` in `server/src/feecase.ts`, G2);
  - never for a booking the shop cancelled, even if it was reopened later (`appointments.shop_cancelled_at`, migration 010: set on the shop's first cancel and never cleared), or that the client cancelled online before the window or within 15 minutes of booking (`feeCase` in `server/src/feecase.ts`, G13);
  - a no-show, and a late cancellation too, only once the appointment's end has passed; a no-show never once it's marked completed (`feeCaseAt` in `server/src/feecase.ts`, G13);
  - no late-cancellation fee while another booked or completed appointment of the same barber overlaps that time (`timeTakenSince` in `server/src/noshowfee.ts`). A walk-in rung up at checkout without an appointment can't be seen, so the fee panel in Izzy Clipz Business and in the website's Business area says not to charge if another client, such as a walk-in, took the time;
  - after a decline, or when the bank wants the client to approve the charge, the card isn't charged again, and the client pays another way (`server/src/noshowfee.ts`).
- **Receipts (as built):** when a fee goes through, the server reads the email the client typed on Stripe's card page from the Checkout Session that saved the card, and sets it as the fee's `receipt_email`, which makes Stripe email the receipt (live mode only; `emailFeeReceipt` in `server/src/noshowfee.ts`). Our server doesn't store the address, but it stays on the fee's payment in the shop's Stripe account. If Stripe has no address, or the call fails, the fee still stands and the server logs it. What became of the receipt is kept with the appointment (`appointments.no_show_fee_receipt`: `sent`, `no_email` or `failed`; migration 009), never the address, and only the shop sees it: when none went out, the fee's details in Izzy Clipz Business and in the website's Business area say so, and how to send one from the Stripe Dashboard.
- **How long (as built):** the fee stays with the appointment, whose name, number, email and note are removed 12 months after it (`server/src/retention.ts`). In the shop's Stripe account, with no set end date.

### 2.10 Card payments in the shop (Tap to Pay)

- **How the card is read:** Apple's Tap to Pay on iPhone reads the card, through Stripe's Terminal SDK in the Business app. The apps and server never see the card number.
- **Sent to Stripe** (`server/src/payments.ts`):
  - the amount;
  - a description: the note staff typed, or without one, "<service> with <barber> for <client's name>" (`IzzyClipzBusiness/Payments/CheckoutModel.swift`);
  - an optional receipt email, which Stripe uses to email the receipt. Staff type it on the take-payment screen before the card is tapped (`IzzyClipzBusiness/Features/Payments/TakePaymentView.swift`); see G14;
  - the appointment's id, as metadata.
- **Stored** in `payments`:
  - id, amount, description, appointment, status, receipt email, times, kind and account;
  - the checkout's ticket (`sale_draft`, which includes the client's name). It's never cleared after the sale is recorded.
- **How long:** forever.

### 2.11 Sales (checkout)

- **Stored** (`server/migrations/006_sales.sql`, `server/src/sales.ts`):
  - In `sales`: the barber credited, the appointment, the client's name (typed, or copied from the appointment), the method (card, cash or other), the total, when the sale was made or voided, and a void reason (free text, up to 200 characters).
  - In `sale_items`: what was sold (a service, a product or a custom item such as a gift card), and at what price.
- **Why:** for checkout, receipts, analytics and the shop's books. A sale is never edited or deleted, only voided.
- **How long:** forever.

### 2.12 IP addresses and request details

- **What our code does with IP addresses:**
  - It reads the visitor's IP only for rate limits (`ipAddress()` from `@vercel/functions`, in `server/src/production.ts`).
  - It stores `<scope>:ip:<first 32 hex characters of SHA-256(IP)>` in `rate_limits` (`server/src/ratelimit.ts`) for:
    - booking: 5 an hour;
    - adding a card: 10 an hour;
    - saving a card: 10 an hour;
    - signing in on a computer: 10 every 10 minutes;
    - Stripe's return pages: 20 every 10 minutes.
  - The hash includes no secret, so an IPv4 address can be recovered by trying every possible address. It's scrambled, not anonymous.
  - The daily job deletes rows older than 24 hours (`server/src/cron.ts`), so each one is kept at most about 2 days.
  - IP addresses are stored nowhere else. The only browser detail kept is a signed-in computer's name, such as "Chrome on Mac" (see section 3).
- **Vercel** processes every request's IP address and keeps runtime logs: the path, query string, browser (user agent), status and region, plus whatever our code logs. How long it keeps them depends on the plan:
  - 1 hour on Hobby;
  - 1 day on Pro;
  - 3 days on Enterprise;
  - 30 days with Observability Plus.
- **What our code logs:**
  - Errors and warnings, as JSON lines (`server/src/router.ts`, `server/src/production.ts`, `stripeFailure` in `server/src/stripeaccount.ts`).
  - They contain ids (appointment, payment and Stripe request ids) and Stripe's error type, code and message, with keys and secrets removed.
  - They never contain request bodies, names, numbers or emails.
  - Stripe's message is logged as Stripe wrote it, so in rare cases it could repeat something like an invalid receipt email.
- **Web addresses never carry personal data.** The only ids in them are opaque: an appointment's id in its path, Stripe's `cs_…` session id on the way back from the card page, and a one-hour Stripe Connect state.

### 2.13 Reviewers' data (Google and Yelp)

- **What the server fetches** (`server/src/reviews.ts`, `server/src/cron.ts`):
  - Google reviews come from the Places API on each request. Nothing is stored except a daily count of calls in `api_usage`.
  - Yelp reviews are cached in `yelp_cache` for at most 24 hours: reviewers' names, profile and photo links, and review text.
  - Both requests carry only the server's own key and the shop's place or business id. No visitor data is sent.
- **Reviewers' photos load directly from Google's and Yelp's image servers**, on the visitor's own browser or iPhone:
  - on the website, through `<img … referrerPolicy="no-referrer">` (`server/web/src/pages/ReviewsPage.tsx` (web));
  - in the app, through `AsyncImage` (`IzzyClipz/Features/Reviews/ReviewsView.swift`).
- Google and Yelp therefore see the visitor's IP address and browser or device, as with any image.
- The demo shows sample reviews with no photos.

### 2.14 Gallery photos

- Six photos of the shop's work ship with the website (`server/web/src/assets/images/gallery-*.webp` (web)) and the client app (`IzzyClipz/Resources/Assets.xcassets/Gallery1`–`Gallery6`).
- They show clients' faces; at least one appears to be under 18. See the owner checklist (written permission, from a parent for a minor).
- **They're already public:** the demo at https://izzy-clipz.vercel.app loads all six (its script bundle, checked November 5, 2026), and they're in the app builds, including the test builds. They came from the shop's older website (`README.md`). See G17.
- They're bundled files, so taking one down means a website deploy and an app update.

## 3. The shop's and staff's data

- **Owner key:**
  - It's a server setting (`OWNER_KEY`, at least 32 characters).
  - On the Business iPhone, it's kept in the Keychain, readable only while the iPhone is unlocked and on that iPhone only (`IzzyClipzBusiness/Support/SecretStore.swift`).
  - On a computer, it can be typed in to make a sign-in code, and it's never kept there; its field isn't a password field, so browsers don't offer to save it (`server/web/src/business/pages/SignInPage.tsx` (web)).
  - **There are no per-barber accounts.** Anyone using the Business app or a signed-in computer sees every client's details.
  - Computers can't take card payments, make sign-in codes or disconnect Stripe (`requireOwner` in `server/src/auth.ts`).
- **Signing in on a computer** (`server/src/computers.ts`):
  - `computer_codes` keeps only an HMAC of the 6-digit code, keyed with the owner key. There's one code at a time; it's good for 10 minutes and stops working after 5 wrong tries.
  - `computer_sessions` keeps, for each signed-in computer:
    - the session token's SHA-256 hash;
    - a name built from the browser, such as "Chrome on Mac" (`server/web/src/business/lib/computerName.ts` (web));
    - when it was created and last used (updated at most every 10 minutes);
    - when it expires (after 30 days) or when it was signed out.
  - Ended sessions are deleted only when the next computer signs in.
  - The browser keeps `izzy.business.session.v1` (see 5.1).
- **Barbers:**
  - Their names, and whether they're active, are in `barbers`.
  - The website's titles, bios and Instagram handles come from the public catalog. Barbers are shown with their initials, not photos.
  - Sales credit and analytics per barber, including a leaderboard, are staff performance data. Anyone with owner access can see them.
- **Time off:** the barber, the times and an optional reason (free text, up to 200 characters, such as "doctor") are kept in `time_off` until the owner deletes the block (`server/src/timeoff.ts`).
- **Products:**
  - Name, description, price and photo link are in `products`.
  - Photos are stored on Vercel Blob. They're public, since the client app shows them, and copies can be cached for up to 30 days (`server/src/production.ts`).
  - The old photo is deleted when it's replaced or the product is deleted (`server/src/products.ts`).
  - Before upload, photos are redrawn and saved again, on the iPhone (`IzzyClipzBusiness/Support/ProductPhoto.swift`) and in the browser (`server/web/src/business/lib/photo.ts` (web)). This removes location and other camera metadata.
- **The shop's Stripe account:**
  - `settings` keeps the account's id, whether it's live or test, its Terminal location, what it can do, how many requirements are due, the business name, and when it was last checked (`server/src/stripeaccount.ts`).
  - The account is created with the shop's name, business category, website and phone (`server/src/stripeconnect.ts`).
  - The owner's identity and bank details go straight to Stripe's onboarding pages; the server never sees them.
  - `stripe_connect_states` keeps only the SHA-256 hashes of one-hour return states.

## 4. Database tables

| Table | Personal data | Form | Deleted today |
|---|---|---|---|
| `appointments` | Name, number, email, note, card brand and last 4, agreed policy and its time, visit and no-show history, Stripe's decline reason; as built, also whether a charged fee's receipt went out (`no_show_fee_receipt`: `sent`, `no_email` or `failed`, never the address; migration 009), and when the shop first cancelled it (`shop_cancelled_at`, migration 010) | Plain text; tokens and keys as SHA-256 hashes | On November 5: never. As built: 12 months after the appointment's end, the daily job sets the name to "Name removed" and clears the number, email, note, the manage token's and booking key's hashes and Stripe's decline reason (`server/src/retention.ts`); `npm run privacy:forget` does it sooner for one person, except on an appointment still needed (upcoming, or with a fee pending or still chargeable). The row and the rest stay |
| `sales` | Client's name, void reason | Plain text | On November 5: never (voided only). As built: the daily job clears the name and void reason 12 months after the sale, or `npm run privacy:forget` sooner; the row stays |
| `sale_items` | None (only what was sold) | | Never |
| `payments` | Description (may hold the client's name or a staff note), receipt email, `sale_draft` (client's name), Stripe ids. As built: no receipt email (migration 008 cleared them, and none is stored since), and a new card payment's description is what was sold and the barber, or the staff's note | Plain text | On November 5: never. As built: 12 months after the payment, the daily job clears a card payment's description and the client's name on its ticket (a fee's description, which names only the service, barber and time, stays); `npm run privacy:forget` does it sooner. The row stays |
| `saved_cards` | Stripe Customer and card ids, brand, last 4, expiry; as built, also when the client asked to delete it (or booked without "Remember me") and when it was removed (`delete_requested_at`, `removed_at`; migration 008) | Card token as a SHA-256 hash | Never (the row). As built: once the card is deleted at Stripe (section 12), its Stripe ids (Checkout Session, Customer and card) are cleared; the brand, last 4 and expiry stay, since old appointments name the brand and last 4. A card on a Stripe account the server can't use any more keeps its ids, marked `stripe_unreachable_at`, and is listed for the shop in Settings › Stripe until the shop deletes it in that account and taps Deleted in Stripe, which clears them (migration 011) |
| `card_checkouts` | None: Stripe ids only (Checkout Session, Customer, Stripe account), test or live mode, and times (migration 011) | Plain text | The row stays; its customer id is cleared once the page's card is saved or the daily job has it deleted at Stripe, 22 hours after the page was made |
| `rate_limits` | Scrambled IP address | Unsalted SHA-256, shortened | Daily, once over 24 hours old |
| `computer_sessions` | Computer's name, when it was used | Token as a SHA-256 hash | Ended ones, at the next computer sign-in |
| `computer_codes` | None | HMAC | Replaced by the next code |
| `stripe_connect_states` | None | SHA-256 hashes | Expired ones, at the next Stripe connection |
| `settings` | The shop's settings and Stripe account | JSON | n/a |
| `time_off` | Staff's reasons | Plain text | When the owner deletes the block |
| `products`, `barbers` | Staff names (in `barbers`) | | Products when deleted; barbers never (marked inactive) |
| `api_usage` | None (counts only) | | Daily, once over 90 days old |
| `yelp_cache` | Reviewers' public names, photos and text | JSON | At 24 hours, and daily |

Neon keeps a restore history, so a changed or deleted row can still be restored for some time afterwards:

- 6 hours on Neon's Free plan;
- up to 7 days on Launch;
- up to 30 days on Scale.

## 5. Website and web apps (web)

### 5.1 What the browser keeps

Sources: `server/web/src/lib/storage.ts`, `server/web/src/booking/flow.ts`, `server/web/src/booking/lastBooked.ts`, `server/web/src/pwa/installHint.ts`, `server/web/src/business/session.ts` and `server/web/src/business/lib/ticket.ts` (all web). Every read and write is guarded, and the site still works when storage is unavailable.

| Key | Where | Holds | Goes away |
|---|---|---|---|
| `izzy.appointments.v1` | localStorage | Each appointment booked here, with its manage token. Never the name, number, email or note: they're removed before saving. | 30 days after the appointment ends; "Forget me" |
| `izzy_appointments` | Cookie | The id and manage token of up to 10 appointments | Each entry 30 days after the appointment ends; the cookie itself ends at most 60 days after it was last written (`Max-Age`) and never later than 30 days after the last appointment in it, and an emptied cookie is deleted; "Forget me" |
| `izzy.details.v1` | localStorage | Name, number and email, only with "Remember me" on (it starts off unless this browser already remembers the client) | "Forget me"; "Not you?" |
| `izzy.card.v1` | localStorage with "Remember me"; sessionStorage otherwise | Card token, brand, last 4, expiry, and the number of whoever added the card | "Forget me"; once booked, or when the tab closes, if not remembered |
| `izzy.cardCheckout.v1` | sessionStorage | The trip to Stripe: card token, session id, number | On return from Stripe; when the tab closes |
| `izzy.booking.v1` | sessionStorage | The booking in progress, including name, number, email and note | Once booked; when the tab closes; "Forget me" |
| `izzy.lastBooked.v1` | sessionStorage | The last booking's id | When the tab closes; "Forget me" |
| `izzy.visits.v1`, `izzy.visitCounted.v1`, `izzy.installHint.v1` | localStorage and sessionStorage | How many visits, and whether (and when) the Add to Home Screen bar was closed or the app installed | Never; used only for that bar |
| `izzy.business.session.v1` | localStorage | This computer's Business session: token, id, name and dates. Never the owner key. | Sign out; when the server refuses the session; after 30 days |
| `izzy.business.lastBarber.v1` | localStorage | The barber last picked for "Sold by" (an id only) | With the sign-in: sign out; when the server refuses the session; after 30 days. A page that opens with no sign-in left also removes one left over. |
| Demo only: `izzy.demo.v1`, `izzy.demo.appointments.v1`, `izzy.demo.business.v1`, `izzy.demo.business.session.v1` | localStorage | Demo bookings with a manage token and a 53-bit scrambled code of the number (no name, number, email or note); the Business demo's sample shop and sign-in | "Forget me"; "Reset the demo"; 60 days after a booking ends. The real site deletes them if it's opened at the demo's address. |

"Forget me on this computer" on My appointments clears the details, the card, the appointment list, the cookie and the booking in progress (`server/web/src/pages/AppointmentsPage.tsx` (web)). On the server, it only asks the shop to delete the saved card, if this browser has one (`DELETE /api/cards`, `server/web/src/lib/cardRemoval.ts`): the appointments stay booked.

### 5.2 The cookie

- **What:** `izzy_appointments`, a first-party cookie.
  - It's set with `SameSite=Strict`, `Secure` on https and `Path=/`.
  - It isn't `HttpOnly`, because the page reads it.
  - It's never set in the demo.
- **Why:** an app added to an iPhone's or iPad's Home Screen, or to the Dock from Safari on a Mac, gets its own website data. Only cookies are copied into it, not localStorage, so the cookie carries the client's appointments into the app.
- **What the server does with it:** nothing. The server never reads it. But because the cookie is set with `Path=/` on the API's own address, the browser sends it with every request to the shop's server, including requests to `/api` (`credentials: 'same-origin'` in `server/web/src/api/http.ts` (web)).
- **Other cookies:** the site's code sets no other cookie. Stripe may set its own cookies on its own page.

### 5.3 Service worker caches

- `izzy-app-<version>` holds the site's own files: the page, scripts, styles, Inter font files, the shop's photos, icons, the manifest and the offline page.
- `izzy-catalog-v1` holds the public catalog.
- Requests with `Authorization`, `X-Manage-Token` or `X-Card-Token` are never answered from a cache.
- Appointments, cards, the owner's area, reviews and open times always go to the network (`server/web/src/sw/routes.ts`, `server/web/src/sw/sw.ts` (web)).

### 5.4 Which hosts the website contacts

- **Its own address:** pages, files and `/api`, all on the same origin.
- **`checkout.stripe.com`:** only when the client adds a card. This is a full-page visit to Stripe.
- **Google's image servers:** for reviewers' photos, on the live site only (see 2.13). Yelp's reviews are only linked, never shown, whatever the server sends, so nothing loads from Yelp (`server/web/src/pages/ReviewsPage.tsx`, `HomePage.tsx` (web)).
- **Vercel Blob:** for product photos in Izzy Clipz Business.
- **Only when the visitor taps a link:** Apple Maps, Google Maps, Instagram, Google and Yelp review pages, Google's terms and privacy policy, and Stripe's Dashboard (from Izzy Clipz Business).
- **Not loaded at all:** third-party scripts, styles, fonts, iframes or embedded maps.
  - The site's runtime packages are React, React Router, `uqr` (which draws QR codes in the browser) and the Inter font (`server/web/package.json`).
- **Fonts:** the system font first, then Inter, which is self-hosted from `@fontsource-variable/inter` (`server/web/src/main.tsx`).
- **Analytics or tracking:** none.
- **Calendar file:** made in the browser. It contains the service, the shop, the address and how to cancel, but none of the client's details (`server/web/src/lib/ics.ts`).
- **Security headers:**
  - The demo sends a strict Content-Security-Policy (its own address only) and `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()` (`server/web/vercel.json`). Its tests check that it never calls `/api` (`server/web/e2e/demo.spec.ts`).
  - The live site sends only `X-Content-Type-Options`, `Referrer-Policy: strict-origin-when-cross-origin` and `X-Frame-Options: DENY` (`server/vercel.json` (web)). See G8.
- **What the page tells clients:** "Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains." with the Privacy Policy linked (`DetailsStep.tsx`). In the demo: "Demo version: your name and number stay on this phone/computer. Nothing is sent to Izzy Clipz Barbershop or anywhere else."
- **Legal links:** every page's footer links the Privacy Policy, Terms of Service, Cancellation & No-Show Policy and Accessibility Statement (`server/web/src/components/Layout.tsx` (web)), and so does every page of Izzy Clipz Business; Review and book says "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy." right above "Book appointment"; the fee notice links the Cancellation & No-Show Policy. A booking made without "Remember me" sends `keepCard: false`, and the server marks the saved card for deletion in the booking's own transaction (`server/src/booking.ts`); "Forget me" and "Not you?" ask the server to delete a saved card (`DELETE /api/cards`).

## 6. The client iPhone app (Izzy Clipz)

- **Permissions:**
  - The app's Info.plist asks for none: no camera, photos, location, contacts, microphone, Bluetooth or tracking (`IzzyClipz/Info.plist`, `project.yml`).
  - "Add to Calendar" uses the system's event editor without calendar access, so the app can't read the calendar (`IzzyClipz/Components/CalendarEventEditor.swift`).
  - Notifications are requested right after the first booking, because each booking is saved with its reminders on (`appointments.add(confirmation, remind: true)` in `IzzyClipz/Features/Booking/BookingModels.swift`) and the next sync asks iOS while permission is undecided and a reminder is still ahead (`performSync` in `IzzyClipz/Stores/AppointmentStore.swift`). The client can turn an appointment's reminders off on "You're booked" (`BookedView.swift`). Turning on haircut reminders asks too. They're **local only**: the app doesn't register for push notifications and has no device token (`IzzyClipz/Features/Reminders/ReminderStore.swift`).
- **Stored in UserDefaults:**
  - `customer.name` and `customer.phone`, when "Remember me" is on. It starts off, unless this iPhone already remembers the client (`IzzyClipz/App/AppRouter.swift`, `IzzyClipz/Stores/CustomerDetailsStore.swift`).
  - `appointments.v2`: each appointment as the server last described it, **including the client's own name, number, note, and card brand and last 4**, until 30 days after the appointment ends.
  - `favorites.barberID`.
  - `reminders.enabled`, `reminders.intervalWeeks` and `reminders.lastCut` (the date of the last haircut).
- **Stored in the Keychain:** manage tokens, the saved card (see 2.6 and 2.7) and any booking still being sent, with the client's number, until the server confirms it or its time has passed (`AppointmentStore.swift`). Also `no-show-cards-to-delete` (this iPhone only): the keys of cards held only until the app closes (added without "Remember me", or with it turned off on the details step). If the app closes before a booking settles one, the shop is asked to delete it the next time the app opens, and its key stays listed until the shop answers (`SavedCardStore.swift`, `becameActive` in `AppDelegate.swift`). On iOS, Keychain items can remain after the app is deleted.
- **No files or databases of its own.** API calls use a temporary connection with no cache and no cookies (`Packages/IzzyClipzKit/Sources/IzzyClipzKit/API/IzzyAPIClient.swift`). Reviewers' photos and product photos load with `AsyncImage`, which uses the system's shared connection and its default cache, so iOS may keep copies of those public pictures in the app's Caches folder (`ReviewsView.swift`, `ShopView.swift`).
- **Network:**
  - the shop's API;
  - Stripe's card page, in a private session;
  - Google's image servers, for reviewers' photos (Yelp's reviews are only linked, never shown, so nothing loads from Yelp);
  - Vercel Blob, for product photos;
  - the shop's website, for the four legal pages, in an in-app browser (Visit → Legal);
  - Apple's map tiles, for the map of the shop (MapKit, without the user's location; `IzzyClipz/Features/Visit/VisitView.swift`).
- **Links out:**
  - calling the shop;
  - directions in Apple Maps or Google Maps (`IzzyClipz/Components/ContactButtons.swift`);
  - Instagram (`IzzyClipz/Components/InstagramCard.swift`);
  - Google and Yelp review pages, and Google's terms (`IzzyClipz/Features/Reviews/ReviewsView.swift`);
  - the new website (the build setting `IZZY_WEBSITE_URL`, Info.plist `IzzyWebsiteURL`, default https://izzy-clipz.vercel.app, read only if it's https), shown in an in-app browser from the Visit tab's "Website" row; the Share link and every Add to Calendar event use the same address, and so do the four legal pages under Visit → Legal, the consent line on Review and the privacy line on Your details (`IzzyClipz/App/Website.swift`, `LegalLinksText`). The Reviews screen also links Google's privacy policy (`ReviewsView.swift`). The app no longer links the shop's older website or its Squire page.
- **What the client can clear:** "Forget my details" (the remembered name and number, and the card, which is also deleted at the shop with `DELETE /api/cards`), "Remove card" (the same deletion, after a confirmation), and "Remove from this list" on a past or cancelled appointment (an upcoming booked one must be cancelled first: `remove` in `AppointmentStore.swift`), which also deletes its key. Apart from the card deletion at the shop, all of these act on this iPhone only. "Forget my details" leaves the stored appointments, with the client's name, number and note, until 30 days after each one. Keychain items (appointment keys, the card key, and unconfirmed bookings with the number) can stay after the app is deleted, and nothing removes them then.
- **A card saved without "Remember me":** the booking says so (`keepCard: false`), so the server marks the card for deletion in the booking's own transaction, and the app also calls `DELETE /api/cards` right after, as a second safeguard (`IzzyClipz/Stores/CardRemoval.swift`).
- **Age range:** on iOS 26 or later the app asks iOS for the user's age range at launch (Apple's Declared Age Range; from iOS 26.2 only where iOS says a law requires it), with the `com.apple.developer.declared-age-range` entitlement. The answer is kept in memory only, never stored or sent; someone under 13 sees only a screen asking a parent or guardian to book (`IzzyClipz/App/AgeCheck.swift`, `IzzyClipz/Features/AgeCheck/AgeRangeCheck.swift`).
- **Photos:** the six gallery photos of clients, the Gallery screen and the Instagram photo strip are gone; Home shows the storefront.
- **Demo builds:** these use an in-memory sample server, and nothing is sent to the shop (`IzzyClipz/App/DemoMode.swift`, `IzzyClipz/Services/FakeShopAPI.swift`).
- **What the app tells clients:**
  - "Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains." (`BookingDetailsView.swift`), and "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy." right above Book appointment, both with their policies linked
  - "Reminders are set on this iPhone only." (`ReminderSettingsView.swift`)
  - "Stripe keeps the card; this iPhone keeps only a key to it." (`NoShowBooking.swift`)
- **Legal links:** Visit → Legal opens the Privacy Policy, Terms of Service, Cancellation & No-Show Policy and Accessibility pages on the website. The Visit page lists only the accessibility features the owner confirmed, then a line to call about getting in.

## 7. The Business iPhone app (Izzy Clipz Business)

- **Keychain:** the owner key (see section 3).
- **UserDefaults:**
  - `pendingPaymentIntents`: payment ids and times, until each payment is settled (`IzzyClipzBusiness/Payments/PendingPayments.swift`);
  - `hasSetUpTapToPay`;
  - `hasSeenHowToTap`;
  - `lastSoldByBarberId`: the barber last picked for "Sold by" at checkout, until sign-out (`CheckoutModel.swift`, cleared in `AppModel.swift`).

  The schedule is kept in memory only.
- **Camera and photos:**
  - Used for product photos only (`NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in `project.yml`; `IzzyClipzBusiness/Features/Products/ProductEditorView.swift`).
  - Photos are saved again before upload, which removes their metadata (see section 3).
- **Location and Bluetooth, for Tap to Pay:**
  - **Location:** requested while the app is in use, because Stripe "must know where payments occur" and turns payments off without it.
  - **Bluetooth:** declared only because Stripe's SDK includes support for Bluetooth card readers. The app doesn't connect to Bluetooth devices (see the Info.plist text in `project.yml`).
  - **Stripe Terminal 6.0.0's own privacy manifest** declares **coarse location** and **product interaction** (used for analytics and app functionality). Neither is linked to the user or used for tracking. It was read from the 6.0.0 release archive, whose checksum matches the one Stripe's Swift package pins.
- **Tap to Pay:** the app has the `com.apple.developer.proximity-reader.payment.acceptance` entitlement (`IzzyClipzBusiness/IzzyClipzBusiness.entitlements`). Apple's Tap to Pay reads the card.
- **Client data that staff type in:**
  - a walk-in's name, and optionally a mobile number and note;
  - a receipt email, offered only after a card payment has gone through, sent to Stripe and not kept by the server;
  - what a client bought at checkout (services and products), with the client's name, kept with the sale (the name is removed after 12 months);
  - a void reason, kept with the sale (removed with the sale's name after 12 months);
  - an optional note on a card payment, which goes to Stripe as the payment's description in place of the item list (`TakePaymentView.swift`, `CheckoutModel.swift`). It can carry a client's name: Stripe keeps it with the payment, with no set end date; the shop's copy is removed after 12 months.
  - time-off reasons.
- **Stripe connection and computers:** Settings connects the shop's own Stripe account (Stripe's page in `ASWebAuthenticationSession`), and "Use on a computer" makes one-time sign-in codes for Izzy Clipz Business on a computer.
- **Age range:** the same check as the client app, kept in memory only; someone under 13 sees a screen saying the app is for the shop's team.
- **Legal links:** Settings → Legal opens the four pages on the website.
- **Call and Text buttons:** they open the iPhone's own Phone and Messages apps (see 2.2).

## 8. Third parties

| Who | Role | What they receive | Their policy |
|---|---|---|---|
| Stripe | Payment processor (in connect mode, the shop's own connected account) | **On its card page:** card details, email, possibly the name on the card and ZIP code, plus the device and IP address. **From the server:** a Customer with no name, number or email; amounts and descriptions for fees and payments (for fees, the service, barber and time; for Tap to Pay, what was sold and the barber, or a note staff typed, which can carry a name); a receipt email staff enter after a card payment has gone through, and for a fee that went through, the email from Stripe's card page, read back from Stripe; appointment ids; the shop's business details. **From the Business app:** the tapped card, the iPhone's coarse location, and the SDK's usage data. | https://stripe.com/privacy |
| Vercel | Hosting: functions, CDN, Blob, cron and logs | Everything the server handles, while it handles it; product photos; request logs with IP address, browser and path | https://vercel.com/legal/privacy-notice |
| Neon | Database, through the Vercel Marketplace | Everything in section 4, including restore history | https://neon.com/privacy-policy (it now leads to the privacy notice of Databricks, which owns Neon) |
| Google | Reviews (Places API) | **From the server:** its key and the shop's place id. **From visitors:** their IP address and browser when reviewers' photos load, plus anything on Google pages they open. | https://policies.google.com/privacy (linked on the Reviews page) |
| Yelp | Reviews (Yelp's API), only when the server has both `YELP_REVIEWS=on` and `YELP_API_KEY`: off by default, even with a key, and the documents assume it stays off (G16) | **From the server**, only when it's on: its key and the shop's business id. The website and the client app only link to Yelp and never show its reviews or photos, so visitors reach Yelp only by following that link. | https://www.yelp.com/tos/privacy_policy |
| Apple | App Store; Tap to Pay on iPhone; MapKit map tiles; the system calendar editor and local notifications (both on the device); Apple Pay on Stripe's page | What Apple's services need in order to work | https://www.apple.com/legal/privacy/ |
| Meta (Instagram) | Links only | Nothing from the apps or the site | |
| GitHub | Code hosting and CI | No client data. Tests use 555 numbers. The smoke test books "Smoke test" with a 555-01xx number on the live server and then cancels it (`server/scripts/smoke.ts`). | |
| The developer | Builds and runs the website, apps and server for the shop | Technical access to everything the server and database hold; sets the server's secrets (owner key, database address, Stripe key); in connect mode, the Stripe key is the developer's own platform key, which acts on the shop's connected account; runs the privacy tools for the shop | None of its own: the owner checklist asks for a written agreement |
| Squarespace and Squire | The shop's older website and old booking page. As built, neither iPhone app nor the website links to them (G15) | Nothing from our code; visitors who go there deal with them directly | Their own |

Both branches were searched. The code uses no ad networks, analytics or crash-reporting services, data brokers, or email or text-message services.

## 9. Can the privacy policy say it?

| Claim | True today? | Evidence and suggested wording |
|---|---|---|
| No analytics or tracking | Yes, for the website, client app and server | No analytics, crash-reporting or attribution code. Both manifests set `NSPrivacyTracking` to false. No App Tracking Transparency or ad identifier. Say that the Business app, used by staff, includes Stripe's payment software, which reports usage and approximate location to Stripe, and that the host keeps request logs. Don't say no other company can collect device data across sites: Stripe's card page does, to prevent fraud, and Google sees visitors' IP addresses when reviewers' photos load. |
| No ads | Yes | No ad code |
| We don't sell data or share it for advertising | Yes | Only service providers receive it. Mention that Google sees visitors' IP addresses when reviewers' photos load (Yelp's reviews are only linked). |
| No marketing texts or emails | Yes | No email or text code. Staff may call or text clients one to one about an appointment from the shop's phone. Stripe emails a receipt when staff enter a receipt email after a card payment, and when a fee goes through, to the email typed on its card page (`emailFeeReceipt` in `server/src/noshowfee.ts`; live mode only); it may also email receipts if the shop turns that on in Stripe. |
| Fonts are self-hosted | Yes | `@fontsource-variable/inter`. Don't say "nothing loads from other sites": reviewers' photos do, and so does Stripe's page when a client adds a card. |
| One cookie, used only to carry appointments into the Home Screen app | Yes | See 5.2. It's strictly functional. Say that it's sent to the shop's server with requests, and that the server ignores it. |
| We don't keep IP addresses | Almost | We keep a scrambled IP address for up to about 2 days to stop abuse. The host also processes IP addresses in its logs, for 1 hour to 30 days depending on the plan. |
| Card numbers never reach the shop | Yes | They go only to Stripe's page and Apple's Tap to Pay. Say that Stripe keeps the card, and the email typed on its page, in the shop's Stripe account. |
| "Your name and number are sent only to Izzy Clipz" (shown in the client app and on the site on November 5) | No | The hosts handle the details on the shop's behalf, the developer can reach them, and on November 5 Stripe got the client's name in Tap to Pay descriptions (G5). As built: the line is gone; the client app and the site say "Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains.", with the Privacy Policy linked (G9), and Tap to Pay descriptions no longer add the client's name. |
| Reminders stay on your phone | Yes | They're local notifications only. |
| The app asks for notifications only when reminders are turned on | No | It asks right after the first booking, because appointment reminders start on (section 6). |
| "Forget my details" clears the client's details from the iPhone | Partly | It clears the remembered name and number and the card. Stored appointments keep the name, number and note until 30 days after each one, and Keychain items can outlive the app (section 6). |
| Every provider protects data at least as well as the policy | No | Stripe and Apple use some data for their own purposes, and Vercel acts as a controller for some service data. Say that Vercel and Neon process data under data protection terms (once confirmed), and that Stripe and Apple use some data under their own policies. |
| The host keeps logs for up to 30 days | Only the logs the shop sees | Vercel's runtime logs are kept 1 hour to 30 days, by plan. Vercel's Privacy Notice keeps some data it controls, such as IP addresses, "for the minimum necessary period" it decides. |
| Do Not Track and Global Privacy Control | Nothing to switch off | There's no cross-site tracking, and no code reads either signal. The policy can say so. |
| Data stays in the US | Yes, for hosting | Functions, database and photos are in `pdx1` (Oregon). Vercel's CDN serves files from its nearest location. Stripe, Google, Yelp and Apple follow their own terms. |
| We delete your details after a set time | Yes, as built (on November 5, no: G1, G2) | The daily job removes the name, number, email and note from appointments 12 months after the appointment, and after 12 months the name and void reason on sales and the description and name on card payments taken at the shop; receipt emails aren't kept. The server deletes saved cards at Stripe once they've expired, gone 12 months unused for a booking, or been removed by the client or saved without "Remember me", as soon as no booking needs them; a card on a Stripe account the server can't use any more is only logged, for the shop to delete in that account's Dashboard (`server/src/retention.ts`, `server/src/cron.ts`). Stripe keeps the email typed on its card page in the Checkout Session (2.7). |
| You can ask us for a copy, a correction or deletion | Yes, as built, with owner-run tools (on November 5, only by hand: G3) | `npm run privacy:find` finds a person by number, email or name and exports, as JSON, their appointments (with the agreed policy and its time), sales, payments and saved cards; `privacy:correct` fixes an appointment's name, number or email; `privacy:forget` removes their details at once, except from appointments still needed, and deletes their saved cards at Stripe (`server/src/privacy.ts`). |
| The service isn't for children | Yes | Nothing aimed at children, and no children's services on the menu (`server/data/catalog.json`). A parent booking for a child gives their own number. The website asks no age questions. As built, both iPhone apps ask iOS for the user's age range at launch (Apple's Declared Age Range, iOS 26 or later; from iOS 26.2 only where a law requires it), keep the answer in memory only, and show someone under 13 only a screen asking a parent or guardian to book, or, in the Business app, saying it's for the shop's team (sections 6 and 7). |

## 10. Privacy manifests

**Client app** (`IzzyClipz/Resources/PrivacyInfo.xcprivacy`):

- **What it declares:**
  - Tracking is off.
  - It collects **Name, Phone Number, Email Address, Payment Info and Other User Content**, each linked to the user, not used for tracking, and used for app functionality.
  - Its only required-reason API is UserDefaults, with reason `CA92.1`.
- **How it matches the code:**
  - Name and number are collected; the note counts as other user content; the card's brand, last 4 and expiry kept with the booking count as payment info.
  - UserDefaults is the only required-reason API in the app's own code. `CA92.1` fits because the data is the app's own; the other UserDefaults suites also belong to the app (for tests and the demo).
- **Suggested additions:**
  - **Email Address (added, as built):** Stripe's card page, opened from the app, saves the email the client types to the shop's Stripe account (see 2.7).
  - **Purchase History (a judgment call, not declared):** visits, no-shows and any fee charged are linked to the person.

  The app collects nothing else.

**Business app** (`IzzyClipzBusiness/Resources/PrivacyInfo.xcprivacy`):

- **What it declares (as built):** tracking is off; it collects **Name, Phone Number, Email Address, Other User Content and Purchase History**, linked to the user, and **Photos or Videos**, not linked, none of them for tracking and all for app functionality; and it uses UserDefaults with reason `CA92.1`.
- **Stripe's SDK manifest:** Stripe's SDK brings its own manifest, which Xcode adds to the app's privacy report. It declares coarse location and product interaction (not linked, no tracking), UserDefaults with reason `CA92.1`, and disk space with reason `E174.1`.
- **What the app itself sends:**
  - product photos (Photos or Videos);
  - clients' names, numbers, notes and receipt emails typed by staff;
  - names on sales and void reasons.
- **Recommended App Store Connect answers:**
  - Coarse Location and Product Interaction (Stripe);
  - Photos or Videos;
  - Name, Phone Number, Email Address, Other User Content and Purchase History, for the clients' details and what they bought, which staff enter.

  As built, the app's own manifest declares all of these except Coarse Location and Product Interaction, which come from Stripe's manifest.
- **Minor:** `NSPhotoLibraryUsageDescription` is present even though the photo picker doesn't need library access. It's harmless.

## 11. Gaps and proposed changes

These are listed with the highest priority first. Each is either a change to the code or a sentence the documents need.

**Status in the documents:**

- **Promised by the documents, so they must be built and released together with them:** G1, G2, G3, G5, G9, G12, G13, G14, G15, G16 and G18, plus publishing and linking the documents, showing the Terms at booking, and capping the fee at the service's price (see `research.md` §18). The documents' dates stay "[TO FILL IN]" until that release. **As built (November 18, 2026):** all of them are in the code on `v5/int`, waiting for that release. Some details differ from the proposals below; where they do, the code wins.
- **Urgent, before launch and independent of it:** G17 (the gallery photos on the public demo). **Done:** the photos are out of the code on `v5/int`, the public demo and the test builds. Other branches on GitHub, including `main`, `v5/legal` and `v5/webapp-business`, still have them.
- **Disclosed in the Privacy Policy instead of changed:** G4 and G6.
- **Recommended, not promised:** G7, G8, G10, G11 and G19. **Still open on November 18,** except that for G11 both privacy manifests and the README now give the answers, which still have to be entered in App Store Connect (OWNER-CHECKLIST.md §4).

### G1. No retention period for clients' details

- **On November 5:** names, numbers, emails and notes stayed on appointments forever.
- **As built:** the daily job removes them as below (`anonymizeExpired` in `server/src/retention.ts`, run from `server/src/cron.ts`; migration 008), with three differences. A fee try still pending holds them only until 14 days after the start (the 7-day fee deadline plus 7 days, `PENDING_FEE_HOLD_DAYS`), long before the 12 months are up. A payment's checkout ticket (`sale_draft`) loses only the client's name, and keeps its items and appointment. The owner's screens still show "Walk-in" for a sale whose name was removed.
- **What the documents promise:**
  - Remove them **12 months after the appointment**.
  - Keep what was booked, when, the price, the status and the fee amounts, because the analytics use them.
  - The analytics never read names, numbers, emails or notes (`server/src/analytics.ts`, `docs/analytics.md`), so every number stays the same.
- **Why there's no separate wait after a charged fee:** fees must be charged within 7 days of the appointment (G2), and card disputes are usually allowed for 120 days after the charge, so 12 months after the appointment always comes later. The evidence for a dispute (the agreed text, the consent time, the fee, the card's brand and last 4) stays on the anonymous record anyway.

**Mechanism: extend the existing daily job.**

1. Add `server/migrations/008_retention.sql`:
   ```sql
   ALTER TABLE appointments ADD COLUMN anonymized_at timestamptz NULL;
   CREATE INDEX appointments_to_anonymize_idx ON appointments (end_at) WHERE anonymized_at IS NULL;
   ALTER TABLE sales ADD COLUMN anonymized_at timestamptz NULL;
   ALTER TABLE payments ADD COLUMN anonymized_at timestamptz NULL;
   ```
2. In `dailyCron` (`server/src/cron.ts`), run these updates after the deletes it already does. Run them in batches of 1,000 until done or about 20 seconds have passed (the function's limit is 30 seconds). In the SQL, `$1` is now and `$2` is now minus 12 months:
   ```sql
   UPDATE appointments
      SET customer_name = 'Name removed', customer_phone = NULL, customer_email = NULL, note = NULL,
          manage_token_hash = NULL, idempotency_key_hash = NULL, no_show_fee_message = NULL,
          anonymized_at = $1, updated_at = $1
    WHERE id IN (
      SELECT id FROM appointments
       WHERE anonymized_at IS NULL AND end_at < $2
         AND no_show_fee_status <> 'pending'
       ORDER BY end_at LIMIT 1000);

   UPDATE sales SET customer_name = NULL, void_reason = NULL, anonymized_at = $1, updated_at = $1
    WHERE id IN (SELECT id FROM sales WHERE anonymized_at IS NULL AND sold_at < $2 LIMIT 1000);

   UPDATE payments
      SET receipt_email = NULL, sale_draft = NULL,
          description = CASE WHEN kind = 'in_person' THEN NULL ELSE description END,
          anonymized_at = $1, updated_at = $1
    WHERE id IN (SELECT id FROM payments WHERE anonymized_at IS NULL AND created_at < $2 LIMIT 1000);
   ```
   - `'Name removed'` satisfies the name column's `NOT NULL` and length check.
   - The number, email and note may be null. Walk-ins already have no number, so the apps handle that.
   - Fee descriptions name only the service, barber and time, so they stay.
   - The owner's screens should show "Name removed" on sales with `anonymized_at` set. Today they show "Walk-in" for a sale with no name.
   - Report the counts in the job's response, as it does today, and test the change with the existing database tests (`server/test/helpers/db.ts`).
3. Read the 12-month period from one constant, so it can be changed in one place.
   - The brand and last 4 stay on old appointments, because a database rule ties them to the card (`appointments_no_show_terms`). Without the name and number, they no longer identify anyone.
4. **Wording in the Privacy Policy:** "12 months after the appointment, then we remove them. If a fee for that appointment is still being processed, we wait until it's settled." and "Database backups: up to 30 more days after we delete or remove something."

### G2. Saved cards are never deleted, and fees have no deadline

- **On November 5:**
  - The server's row, and the Customer and card at Stripe, stayed forever.
  - "Remove card" and "Forget me" cleared only the device.
  - There was **no time limit for charging a fee after the visit** (`server/src/feecase.ts`, `server/src/noshowfee.ts`).
- **As built:** as proposed below, except that a fee try still pending keeps the card only until 14 days after the start (`PENDING_FEE_HOLD_DAYS` in `server/src/retention.ts`). The server refuses a new fee try more than 7 days after the start (`FEE_DEADLINE_DAYS` and `feeCaseAt` in `server/src/feecase.ts`). `DELETE /api/cards` (`deleteCard` in `server/src/cards.ts`, `removeCard` in `server/src/retention.ts`) is called from "Remove card", "Forget my details", "Forget me" and "Not you?", and right after a booking made without "Remember me". Such a booking also says so itself (`keepCard: false`), and the server marks its card for deletion in the booking's own transaction (`server/src/booking.ts`). The daily job deletes the cards that are due (`purgeSavedCards`). One exception: a card saved on a Stripe account the server can no longer use (the shop changed how it connects to Stripe, or took the platform's access away) is removed on the server (it can't book or be charged) but keeps its ids, and Settings › Stripe lists it for the shop to delete in that account's Stripe Dashboard and then mark Deleted in Stripe (as built, November 20). Since then, a card Stripe kept when adding it didn't finish is deleted too, by the daily job, within 2 days (`card_checkouts`, migration 011; see 2.7).
- **What the documents promise:**
  1. **A charging deadline of 7 days after the appointment's start.** After it, the server refuses a new fee attempt. It's fairer to clients, it gives the card agreement a clear end (card-network rules, `research.md` §9.2), and it tells the server when a card is no longer needed.
  2. **`DELETE /api/cards`**, called with `X-Card-Token`:
     - When no booking still needs the card, it detaches the card (`paymentMethods.detach`) and deletes the Stripe Customer (`customers.del`). The card can then no longer be charged. The completed Checkout Session still holds the email typed on Stripe's page, because Stripe's API can't delete a Checkout Session; the Privacy Policy says so. (Stripe's Redaction Jobs, in public preview, can remove it from the shop's Dashboard and API; the shop hasn't adopted them.) (Stripe also keeps its own records as the law requires.)
     - A booking still needs the card if it's upcoming, if it could still be charged a fee before the 7-day deadline (it's still booked, marked a no-show, or cancelled late), or if a fee is pending. In that case, mark the card (`delete_requested_at`) and let the daily job delete it once none of those is true.
     - Call it from "Remove card" and "Forget my details" in the app, and from "Forget me" (and "Not you? Forget me") on the website.
     - **Also call it right after a booking made without "Remember me"**: on the website in `ReviewStep.tsx` before `forgetCard()`, and in the app in `keepOrForgetCard`. Today the device drops the card's key then, so the client can never remove the card, while it would stay at Stripe for up to 12 months.
  3. **The daily job** deletes cards that have expired, or haven't been used for a booking in 12 months, or were marked for deletion, as long as no booking needs them.
  4. **Code changes:**
     - Add those Stripe calls to `StripeClient` (`server/src/deps.ts`).
     - Add `removed_at` and `delete_requested_at` to `saved_cards`, and allow its Stripe ids to be null once the card is removed.
  5. **Wording in the Privacy Policy:** "A card you save on Stripe's page stays in the shop's Stripe account until the first of these happens: the card expires; 12 months pass without it being used for a booking; you remove it ... or ask us to delete it; you saved it without 'Remember me', and the booking you saved it for can no longer be charged a fee (7 days after the appointment at the latest). ... Then we ask Stripe to delete the card, and the customer record it was saved under, as soon as none of your bookings still needs it."

### G3. No way to answer requests for a copy, a correction or deletion

- **On November 5:**
  - Only raw database commands could find or delete one client's data.
  - Nobody could edit a name or number after booking.
- **As built:** the three scripts below (`server/src/privacy.ts`, `server/scripts/privacy.ts`). The apps and the API still can't edit a name or number after booking. The scripts add a few things to the proposal:
  - `privacy:find` and `privacy:forget` can also look for someone the shop knows only by name (`--name`, which also finds their walk-in checkouts).
  - `privacy:find --out` saves the export to a file.
  - `privacy:correct` also fixes the name copied to a card checkout's ticket.
  - `privacy:forget --dry-run` only shows what it would do, and `privacy:forget` says when to run it again for the appointments it had to keep.
- **What the documents promise:** a copy (including the agreed cancellation terms), a correction, and deletion, after checking the person by calling or texting the number on file.
- **Proposal:** owner-run scripts alongside `npm run migrate`:
  - `npm run privacy:find -- --phone "+1…"` (or `--email`) lists that person's appointments (with `no_show_policy` and `no_show_consent_at`), sales, payments and saved cards, and exports them as JSON.
  - `npm run privacy:correct -- --appointment <id> --name "…"` (and `--phone`, `--email`) fixes a typo on an appointment and its sale.
  - `npm run privacy:forget -- --phone "+1…"` applies G1's changes to those rows straight away, except rows a booking still needs (upcoming, inside the 7-day charging deadline, or with a fee pending), and deletes the person's saved cards at Stripe as in G2.
  - The policy describes this process, whether or not the CCPA applies (see `research.md` §3).

### G4. Stripe's page collects an email

- The email typed on Stripe's page, and possibly the name on the card and ZIP code, is saved on the shop's Stripe account. On November 5 the server never read it.
- The Privacy Policy discloses it. Check the fields once in test mode.
- No code change is needed.
- **As built:** the server now reads that email, without storing it: when a fee goes through, it takes the email from the Checkout Session that saved the card and sets it as the fee's receipt email, so Stripe emails the receipt (live mode only; `emailFeeReceipt` in `server/src/noshowfee.ts`, see 2.9).

### G5. The client's name goes to Stripe with Tap to Pay payments

- **On November 5:** without a note, the description was "<service> with <barber> for <client>". It's sent to Stripe and kept in `payments.description`.
- **As built:** without a note, it's what was sold and the barber credited, such as "Haircut with Carlos"; the client's name is never added (`paymentDescription` in `IzzyClipzBusiness/Payments/CheckoutTicket.swift`). Of the clean-up below, the receipt email isn't kept (G14), but `sale_draft` isn't cleared when its sale is recorded (it's still read when a sale is voided, `server/src/sales.ts`); the daily job removes the client's name from it after 12 months (G1).
- **In the documents:** the Privacy Policy says Stripe receives a short description of the visit, such as the service and the barber, or a note staff type.
- **Required fix (the Privacy Policy now assumes it):** drop " for <client>" in `IzzyClipzBusiness/Payments/CheckoutModel.swift`, so the description is "<service> with <barber>" unless staff type a note. The copy of older descriptions in the shop's Stripe account stays as long as Stripe keeps payment records, which the policy's retention table says.
- **Related clean-up:**
  - Stop keeping the receipt email after the payment, since Stripe has it.
  - Clear `sale_draft` when its sale is recorded (`server/src/sales.ts`).

### G6. Reviewers' photos load from Google and Yelp

- **In the documents:** disclosed (see 2.13).
- **As built:** only Google's photos load. The website and the app never show Yelp's reviews, whatever the server sends (G16), so nothing loads from Yelp's servers.
- **Alternatives:** show the reviewers' initials instead of photos, or pass the photos through the server without storing them (check Google's terms first).

### G7. The IP hash has no secret

- Use an HMAC with a server secret in `ipKey` (`server/src/ratelimit.ts`), for example a new setting called `RATE_LIMIT_SECRET`. The stored value can then no longer be turned back into an IP address.
- Keep the retention at about 2 days.

### G8. The live site has no Content-Security-Policy or Permissions-Policy

- The demo has both. Add them to `server/vercel.json` (web).
- Allow images from Vercel Blob and from Google's photo servers (the website no longer shows Yelp's reviews, G16), then check that the trip to Stripe's card page still works.
- **Why it matters:** these headers limit the harm of any injected script. That's important here because the cookie and localStorage hold manage tokens.

### G9. The website's email field has no use in the code

- The Privacy Policy says it's optional and used only to contact the client about the appointment.
- **Required:** the line under the form ("Your name and number are sent only to Izzy Clipz Barbershop, to book and manage this appointment.", in `server/web/src/booking/DetailsStep.tsx` and `IzzyClipz/Features/Booking/BookingDetailsView.swift`) isn't accurate: the hosts, Stripe and the developer handle the details too. Change it to "Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains.", with the policy linked.
- The app doesn't ask for an email.
- **As built:** the line is changed, with the Privacy Policy linked, on the website (`DetailsStep.tsx`) and in the app (`LegalCopy.detailsPrivacy` in `IzzyClipz/App/Website.swift`). The email field still has no use in the code: nothing sends email to it; staff see it, and the privacy tools can find a client by it (G3).

### G10. More clean-up in the daily job

- Delete ended computer sessions and expired Stripe Connect states every day. Today this happens only at the next computer sign-in or Stripe connection. (The Privacy Policy describes today's behavior.)
- If the owner wants, clear time-off reasons after 12 months.

### G11. App Store privacy answers

See section 10:

- For the client app, consider adding Email Address.
- For the Business app, give its real answers: Stripe's coarse location and product interaction, product photos, and the clients' details that staff enter.
- **As built:** the privacy manifests now declare them. The client app adds Email Address. The Business app declares Name, Phone Number, Email Address, Other User Content and Purchase History (linked) and Photos or Videos (not linked), and Stripe's SDK declares its coarse location and product interaction in its own manifest. The README's publishing steps list the App Store Connect answers. Still to do: give those answers in App Store Connect when the apps are published (OWNER-CHECKLIST.md §4).

### G12. "Remember me" starts on in the app

- **On November 5:** the app's "Remember me on this iPhone" started on (`BookingDetailsInProgress.start` in `IzzyClipz/App/AppRouter.swift`), and with a card it kept the card for later bookings. The website's starts off unless the browser already remembers the client.
- **As built:** it starts off in the app too, unless this iPhone already remembers the client (`remember: saved != nil` in `BookingDetailsInProgress.start` and in `remembering(_:)`).
- **Why it matters:** Stripe asks for explicit consent to save a card for later use, for example an unticked "Save my payment method for future use" box. A box that starts ticked isn't explicit consent, and invites "I never agreed to keep my card" disputes.
- **What the documents promise:** it starts off in the app too, unless this iPhone already remembers the client: `remember: saved != nil` in `BookingDetailsInProgress.start` (and in `remembering(_:)`), with the UI tests updated.

### G13. When a fee can be charged

- **On November 5** (`server/src/feecase.ts`, `server/src/appointments.ts`, `server/src/noshowfee.ts`):
  - A booking with a card on file could be marked a no-show, and charged, as soon as its start time passed, although the documents say a client who arrives before the end isn't a no-show.
  - A completed appointment without a sale could be changed to a no-show and charged, although the documents say the agreement ends when the client comes.
  - A client cancellation inside the window was late even a minute after booking a time that was already inside it (bookings can start 30 minutes ahead, and the window can be up to 48 hours).
- **As built:** all three changes below, on the server (`patchOwnerAppointment` in `server/src/appointments.ts`; `feeCase`, `feeCaseAt` and `cancelledLate` in `server/src/feecase.ts`), in the Kit (`IzzyAPI.NoShowRule`), in Izzy Clipz Business and on the website (`lib/lateCancel.ts`, `business/lib/fees.ts`). A booking with a card on file that was once marked completed (or checked out) never becomes a no-show, even after it's reopened (`completed_at`, migration 008).
- **What the documents promise, and the change:**
  1. **A no-show fee only after the end time.** `patchOwnerAppointment` refuses `no_show` for a booking with a card on file while `end_at > now` (instead of `start_at`), with the message "You can mark a no-show once the appointment has ended."; `chargeCase` refuses a no-show fee while `end_at > now`. Mirror it in the Kit and both owner screens (the app and the website's Business area), and test one minute before and after the end.
  2. **A completed appointment stays completed for fees.** `patchOwnerAppointment` refuses changing a booking with a card on file from `completed` to `no_show`, so a client who came can't be charged by mistake. Test it.
  3. **A 15-minute grace period.** `cancelledLate` also requires `customer_cancelled_at - created_at > 15 minutes`, in the server, the Kit's `NoShowRule`, and the website's `lib/lateCancel.ts` (used by the booking steps and `business/lib/fees.ts`). `test/fixtures/no-show-rule.json` gets cases with `created_at`. The notices for a time already inside the window (the website's `bookNote` in `ReviewStep.tsx`, the Kit's `lateCancelNotice` shown in `ChooseTimeView.swift`) say that cancelling it more than 15 minutes after booking may be charged. Test at 14 and 16 minutes.

### G14. The receipt email is asked for before the card payment

- **On November 5:** staff typed an optional receipt email on the take-payment screen before the card was tapped (`IzzyClipzBusiness/Features/Payments/TakePaymentView.swift`); it went to Stripe with the PaymentIntent and was kept in `payments.receipt_email` (`server/src/payments.ts`).
- **As built:** "Email a receipt (optional)" appears only after a card payment has gone through (`IzzyClipzBusiness/Features/Payments/PaymentProgressView.swift`). The server refuses a receipt email sent with a new payment; afterwards, `POST /api/owner/payments/:id/receipt` sets the address on the PaymentIntent at Stripe (not on the charge, as proposed below), so Stripe emails the receipt, and the server neither stores nor logs it (`createPayment` and `sendPaymentReceipt` in `server/src/payments.ts`). Migration 008 cleared the addresses kept before, and the daily job clears any left.
- **Why it matters:** California's Song-Beverly Credit Card Act (Civ. Code §1747.08) bars requesting personal identification information that's recorded as part of a credit card transaction (`research.md` §9.3).
- **What the documents promise, and the change:** the email receipt is offered only after the payment has gone through; the server sets `receipt_email` on that payment's charge, which makes Stripe send the receipt (Stripe's API: "If this field is updated, then a new email receipt will be sent to the updated address"), and doesn't store the address. Card payments never need an email, ZIP code or phone number.

### G15. The client app links to the older website

- **On November 5:** the Visit tab's "Website" row, its Share link and every Add to Calendar event used https://www.izzyclipzbarbershop.net (`websiteURL` in `Packages/IzzyClipzKit/Sources/IzzyClipzKit/IzzyClipzData.swift`, `websiteUrl` in `server/data/catalog.json`). That's the shop's older Squarespace site, with Squarespace's cookie and scripts, and its booking button goes to Squire.
- **As built:** all three, and the four legal pages, use the build setting `IZZY_WEBSITE_URL` (`IzzyClipz/App/Website.swift`, `project.yml`), and the Kit's `websiteURL` and the catalog's `websiteUrl` point at the new site too. The app no longer links the older site or Squire. The setting is still https://izzy-clipz.vercel.app, the public demo, whose legal pages are drafts: change it, or put the shop's real site at that address, before publishing (README, "Publishing to the App Store").
- **What the documents promise:** the Privacy Policy says there are no analytics or tracking tools in the client app, and the documents say they don't cover the older site or Squire.
- **The change:** point all three at the new website's address once it's known, or remove them until then.

### G16. Yelp reviews

- **On November 5:** with `YELP_API_KEY` set, the website and app showed Yelp's reviews and rating next to Google's (the website's Reviews page and home tile), with generic stars and no Yelp logo.
- **As built:** the website and the app never show Yelp's reviews or rating, whatever the server sends; they only link to the shop's Yelp page. The server calls Yelp only with `YELP_REVIEWS=on` as well as `YELP_API_KEY` (`server/src/config.ts`, `yelpReviewsSource` in `server/src/reviews.ts`); a key alone does nothing.
- **Why it matters:** Yelp's API Terms (September 22, 2026) describe the API as for non-commercial uses, defined as bringing no promotional or monetary value, and bar Yelp ratings next to other reviews (`research.md` §12.2).
- **What the documents promise:** only Google's reviews are shown; Yelp is linked. Leave `YELP_API_KEY` unset on the live server (the website and app then show "Read our reviews on Yelp"), unless the owner gets Yelp's written consent.

### G17. The gallery photos are already public (urgent)

- **On November 5:** the six gallery photos, with clients' faces and an apparent minor in the first one, were on the public demo and in the app builds (2.14).
- **As built:** they're gone from the website (`server/web/src/assets/images/` holds only the storefront photo) and from the app's asset catalog, with the Gallery screen. The public demo has been without them since November 5, and the test build published on November 14 replaced the old one (OWNER-CHECKLIST.md §0).
- **The change, now:** remove them from `server/web/src/assets/images/gallery-*.webp` and `IzzyClipz/Resources/Assets.xcassets/Gallery1`–`Gallery6` (or replace them with photos without faces), redeploy the demo and rebuild the test builds. A photo of a person goes back only with that person's signed permission (a parent's or guardian's for a minor). The Privacy Policy says everyone who can be recognized agreed.

### G18. The Visit page's accessibility lines

- **On November 5:** "Wheelchair accessible", "ADA-compliant entrance" and "Accessible parking near the entrance" (`server/data/catalog.json`, `IzzyClipzData.swift`). "ADA-compliant" is a legal claim nobody has inspected.
- **As built:** the unchecked lines are gone. The list has only the two lines the owner confirmed, "Room for a wheelchair inside, at the chairs and the counter" and "Disabled parking space near the entrance" (`IzzyClipzData.swift`, and `server/data/catalog.json` through the Kit's export), and the Visit page, on the website and in the app, always adds "Questions about getting in or around the shop? Call (442) 341-3053 (relay calls welcome: dial 711) and we'll help." A line about the entrance goes on only once the owner has checked it (OWNER-CHECKLIST.md §1). The Accessibility Statement doesn't depend on these lines: it asks clients to contact the shop for help getting in.

### G19. Smaller points

- **The cookie is sent to the server with every request.** Optionally, set it with `Path=/appointments`, the only place it's read, after checking that the Home Screen import still works.
- **Owner access is all or nothing.**
  - The Privacy Policy says that everyone at the shop who uses Izzy Clipz Business can see appointment details.
  - The owner should give access to the app and computer sign-ins only to trusted staff, and sign out old computers (Settings lists them).
- **Hosting plan.** The Privacy Policy's sentence about logs ("up to 30 days") covers every plan:
  - Vercel's Hobby plan is for "non-commercial, personal use only". It keeps logs for 1 hour and runs the daily job within an hour of its scheduled time.
  - Pro keeps logs for 1 day.

## 12. Retention schedule

This is what the Privacy Policy states. In the last column, "now" means it's already true today.

| Data | Where | How long | How |
|---|---|---|---|
| Name, number, email and note on appointments | Server | 12 months after the appointment | Now: the daily job, 12 months after the appointment's end (`server/src/retention.ts`). A fee still marked pending holds them only until 14 days after the start, so never past the 12 months. |
| Client's name on sales; void reasons | Server | 12 months | Now: the daily job, 12 months after the sale |
| Descriptions of card payments taken at the shop; the client's name on their checkout tickets | Server | 12 months | Now: the daily job, 12 months after the payment; a fee's description (only the kind of fee, the service, barber and time) and the ticket's items stay |
| Receipt emails typed at the counter | Server | Not kept: passed to Stripe after the payment | Now (`server/src/payments.ts`); migration 008 clears the old ones, and the daily job clears any left |
| Payment records, descriptions and receipt emails at Stripe; the card page's record (Checkout Session) with the email typed there | Stripe (the shop's account) | As long as Stripe keeps them; a Checkout Session can't be deleted | Stripe |
| What was booked, prices, sales totals | Server | Kept for the shop's records, without personal details | n/a |
| Saved card | Stripe and server | Until it expires, goes 12 months unused, or is removed; without "Remember me", until its booking can no longer be charged; in each case once no booking needs it | Now (`server/src/retention.ts`): deleted at Stripe (detached, its Customer deleted) at once on removal when no booking needs it, otherwise by the daily job. Once deleted, the server keeps the row without Stripe's ids. A card on a Stripe account the server can't use any more is marked removed and listed for the shop in Settings › Stripe, to delete in that account's Dashboard |
| Unfinished card pages: a card Stripe kept, or a customer record it made, when adding a card didn't finish | Stripe (the shop's account) | Until the daily job deletes them, 22 hours after the page was made: within 2 days | Now (`purgeUnfinishedCheckouts` in `server/src/retention.ts`; migration 011) |
| Agreed policy text and its time | Server | Kept with the appointment, no longer linked to a person after 12 months | Now (the daily job, G1) |
| Scrambled IP address for rate limits | Server | About 2 days | Now |
| Request logs the shop can see | Vercel | 1 hour (Hobby), 1 day (Pro), up to 30 days (Observability Plus) | Vercel |
| Traffic data Vercel keeps for itself (for example IP addresses, for security) | Vercel | "The minimum necessary period", as Vercel decides (its Privacy Notice) | Vercel |
| Database restore history | Neon | 6 hours to 30 days, depending on the plan | Neon |
| Yelp reviews (only with `YELP_REVIEWS=on` and a Yelp key; a key alone never calls Yelp, the website and the app never show them, and the documents assume it's off, G16) | Server | At most 24 hours | Now |
| Google reviews | Server | Not stored | Now |
| Computer sign-ins | Server and browser | Up to 30 days (ended ones deleted at the next sign-in) | Now (G10 would make it daily) |
| Product photos | Vercel Blob | Until replaced or deleted (copies cached for up to 30 days) | Now |
| Appointments and tokens on the device | iPhone and browser | 30 days after the appointment | Now |
| Remembered details and card token | iPhone and browser | Until the client chooses "Forget" | Now |
| Booking in progress | Browser tab | Until the tab closes or the booking is made | Now |

## Other things noticed (for the other documents)

- **"In the app" and "online":**
  - The policy text stored with new protected bookings says "Cancelling online is free…", and when the card may be charged: "within 7 days after your appointment time" (`policyText` in `server/src/noshow.ts`, OWNER-CHECKLIST.md §3 item 22). Bookings made before keep the text they agreed to, which says "Cancelling in the app…".
  - The website's fee notice adds "Cancelling on this website, under My appointments, works the same as cancelling in the app." (`server/web/src/booking/TimeStep.tsx` (web)), and the Cancellation & No-Show Policy says both count.
- **"May be charged":** the fee notices (`feeWarning` in `server/src/noshow.ts`, and the website's) say "may be charged", like the agreed text's "may charge" (`policyText`): the shop decides each time. The notice's title is "Late Cancellation & No-Show Fee" whenever late cancellations can be charged, or "No-Show Fee".
- **Only clients' own online cancellations can count as late:**
  - A booking the shop cancels (after a phone call, for example) is never charged.
  - A no-show can be charged only after the appointment's end, never once it's marked completed, and only if the client never cancelled; no fee can be charged more than 7 days after the start (`feeCase` and `feeCaseAt` in `server/src/feecase.ts`; G13 and G2, as built).
- **No-show protection is off** until the owner turns it on, even when Stripe is set up. When it's on:
  - the defaults are 100% of the service price and a 1-hour window;
  - the owner can choose 1% to 100% of the price or a flat $0.50 to $500, and a window from 30 minutes to 48 hours (`server/src/noshow.ts`); the fee is never more than the booked service's price, so a flat fee above it is cut to the price (`noShowFeeCents`);
  - late cancellations can be switched off, leaving only no-shows chargeable.
- **Booking limits** (`server/src/booking.ts`, `server/src/appointments.ts`, `server/data/catalog.json`):
  - 3 upcoming appointments per number;
  - 5 booking attempts per network per hour;
  - bookings can be made from 30 minutes to 60 days ahead.

## Protections already in the code (for the policy's security section)

- HTTPS everywhere. The database connection is encrypted, and its certificate is checked (`server/src/db.ts`).
- Manage tokens, card tokens, computer sessions, booking keys and Stripe return states are stored only as SHA-256 hashes. Sign-in codes are stored as keyed HMACs. The owner key is compared in constant time (`server/src/auth.ts`, `server/src/computers.ts`).
- Only Stripe and Apple ever handle card numbers.
- Booking, adding cards and signing in are all rate-limited.
- Logs contain no request bodies or personal details, and keys and secrets are removed from Stripe errors.
- API responses are never cached (`Cache-Control: no-store` in `server/src/http.ts`), and the service worker never keeps personal data.
- The website keeps appointments without the client's details, offers a saved card only to the number that added it, and starts "Remember me" off on a shared computer.
- The owner key is kept only in the Business iPhone's Keychain (on that iPhone only) and on the server. Computers sign in with a one-time code instead, and can be signed out from the iPhone.
- Product photos lose their location data before upload.
- The site's pages can't be shown inside frames, and review photos and Stripe's return pages send no referrer.

## Sources (vendor facts, read November 5, 2026)

- Vercel runtime log retention by plan, and the fields kept: [Runtime Logs](https://vercel.com/docs/logs/runtime) (page updated 2026-08-28)
- Vercel Cron timing on Hobby (±59 minutes): [Cron Jobs usage and pricing](https://vercel.com/docs/cron-jobs/usage-and-pricing) (2026-07-15)
- Vercel Hobby plan, "non-commercial, personal use only": [Hobby plan](https://vercel.com/docs/plans/hobby) (2026-09-14)
- Neon restore window by plan: [Neon plans](https://neon.com/docs/introduction/plans) (2026-11-04)
- Neon's privacy policy address now leads to Databricks' privacy notice: [neon.com/privacy-policy](https://neon.com/privacy-policy) (checked 2026-11-05)
- Stripe Checkout and the Customer's email (the `customer` and `customer_email` parameters): [Create a Checkout Session](https://docs.stripe.com/api/checkout/sessions/create)
- Stripe Terminal location requirement and the Bluetooth key: [Terminal iOS setup](https://docs.stripe.com/terminal/payments/setup-integration?terminal-sdk-platform=ios) ("To reduce fraud risks associated with payments, and to minimize disputes, Stripe must know where payments occur.")
- Checkout Sessions can be created, updated, retrieved, listed and expired, not deleted: [Checkout Sessions API](https://docs.stripe.com/api/checkout/sessions)
- Setting `receipt_email` on a charge afterwards sends a new receipt: [Update a charge](https://docs.stripe.com/api/charges/update)
- Stripe collects device and browser details across sites to detect fraud, and uses End Customers' data for its own purposes where allowed: [Stripe Privacy Policy](https://stripe.com/privacy) (last updated April 28, 2026), §1.2(b) and §2(a)
- Vercel acts as a controller for some data and keeps it "for the minimum necessary period": [Vercel Privacy Notice](https://vercel.com/legal/privacy-notice) (June 1, 2026); its Data Processing Addendum applies to Pro and Enterprise customers: [Vercel DPA](https://vercel.com/legal/dpa) (last updated March 17, 2026)
- Yelp's API is described as for non-commercial uses, and Yelp ratings may not be shown next to other reviews: [Yelp API Terms of Use](https://terms.yelp.com/developers/api_terms/) (last updated September 22, 2026), sections 1 and 5
- Stripe Terminal 6.0.0's privacy manifest: read from the [6.0.0 release archive](https://github.com/stripe/stripe-terminal-ios/releases/download/6.0.0/StripeTerminal.xcframework.zip), whose checksum matches the one [Stripe's Swift package](https://raw.githubusercontent.com/stripe/stripe-terminal-ios-spm/6.0.0/Package.swift) pins
- Privacy manifests in apps and SDKs: [Apple: Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
