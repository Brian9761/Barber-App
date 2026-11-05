# Data inventory

This file records what the Izzy Clipz website, web apps, iPhone apps and server actually do with personal data, as read from the code. It backs the Privacy Policy and the other documents in this folder. Where a fact comes from a vendor rather than from our code, the vendor's page is cited at the end.

- **Checked:** November 5, 2026.
- **Code read:**
  - `v5/int` at `9910eb4`, re-checked at `815b1e8` (the commits in between change only UI tests): both iPhone apps, IzzyClipzKit and the server.
  - `v5/webapp-business` at `83a4835`, re-checked at `f06ae57` (the commits in between change only wording in the Business area's Settings page and its tests): the website and web apps. The branch is now on GitHub.
- **Branch notes:**
  - Paths marked **(web)** exist only on `v5/webapp-business` today.
  - The server is the same on both branches, with four exceptions: `server/src/website.ts` (web only), the website's build and headers in `server/vercel.json` (web only), the website's extra catalog content (barbers' bios, titles and Instagram handles) in `server/data/catalog.json` (web only), and one rounding detail when cancelling (int only).
  - The database migrations are identical on both branches.
- **Keep it current:** check this file again whenever code that stores, sends or deletes data changes, and before changing the Privacy Policy.

## At a glance

- **What clients give:** their name, mobile number and an optional note. The website also asks for an optional email. These are kept on the shop's server with each appointment, and **nothing deletes them today**.
- **Cards:**
  - Card numbers never reach the shop's apps or server. Clients type them on Stripe's page or tap their card on the barber's iPhone.
  - For a saved card, the server keeps only the brand, last 4 digits, expiry and Stripe's ids.
  - Stripe keeps the card itself, plus **the email the client types on Stripe's page**.
  - Nothing deletes saved cards today, either at the shop or at Stripe.
- **What the shop's own code doesn't do:** no analytics, ads, tracking, data sales, or marketing emails or texts. The one exception is the Business app (staff only): it includes Stripe's Tap to Pay software, which reports approximate location and usage to Stripe.
- **The website:**
  - It sets **one functional cookie**. Everything else it keeps stays in the browser, for the client's own convenience.
  - It loads no third-party scripts, styles or fonts.
  - **Reviewers' photos load from Google's and Yelp's servers.**
- **IP addresses:** our code doesn't store them, except as an unsalted hash used for rate limits, deleted within about 2 days. Vercel processes IP addresses in its own logs.
- **Main gaps** (details in section 11):
  - There's no retention period for clients' details. The documents promise to remove them 12 months after the appointment, using the existing daily job.
  - Saved cards are never deleted at Stripe.
  - There's no tooling to answer requests for a copy, a correction or deletion.
  - The client's name is sent to Stripe in Tap to Pay payment descriptions (the Privacy Policy discloses it).
  - The Business app's App Store privacy answers need to cover more than they do.

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
- **On the website:** `izzy.card.v1`, together with the number of the client who added the card. It's in `localStorage` with "Remember me" on, and in `sessionStorage` otherwise; without "Remember me" it's also forgotten once the booking is made (see 5.1).
- **Why:** to charge the fee the client agreed to, if the barber decides to.
- **How long:** **forever**, both for the server's row and for the Customer and card at Stripe.
  - No code deletes them, and the server's Stripe client has no call for it (`server/src/deps.ts`).
  - "Remove card" and "Forget my details" in the app, and "Forget me" on the website, clear only the device. See G2.
- **Who receives it:**
  - Stripe, as the payment processor. In connect mode, this is the shop's own connected Stripe account.
  - The shop, which can see the Customer, its email, and the card's brand, last 4 digits and expiry in its Stripe Dashboard.

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

  No name, number or receipt email is sent.
- **Rules:** at most one fee per appointment; only after the start for a no-show; never for a booking the shop cancelled, or that the client cancelled online before the window (`feeCase` in `server/src/feecase.ts`). There's no time limit after the visit today (see G2).
- **Receipts:** Stripe may email the client a receipt, using the email on the Customer, if the shop turns on Stripe's receipt emails. That's a setting in the Stripe Dashboard, not in our code.
- **How long:** forever.

### 2.10 Card payments in the shop (Tap to Pay)

- **How the card is read:** Apple's Tap to Pay on iPhone reads the card, through Stripe's Terminal SDK in the Business app. The apps and server never see the card number.
- **Sent to Stripe** (`server/src/payments.ts`):
  - the amount;
  - a description: the note staff typed, or without one, "<service> with <barber> for <client's name>" (`IzzyClipzBusiness/Payments/CheckoutModel.swift`);
  - an optional receipt email, which Stripe uses to email the receipt (`IzzyClipzBusiness/Features/Payments/TakePaymentView.swift`);
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
- They're bundled files, so taking one down means a website deploy and an app update.

## 3. The shop's and staff's data

- **Owner key:**
  - It's a server setting (`OWNER_KEY`, at least 32 characters).
  - On the Business iPhone, it's kept in the Keychain, readable only while the iPhone is unlocked and on that iPhone only (`IzzyClipzBusiness/Support/SecretStore.swift`).
  - On a computer, it can be typed in to make a sign-in code, and it's never kept there (`server/web/src/business/pages/SignInPage.tsx` (web)).
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
| `appointments` | Name, number, email, note, card brand and last 4, agreed policy and its time, visit and no-show history, Stripe's decline reason | Plain text; tokens and keys as SHA-256 hashes | Never |
| `sales` | Client's name, void reason | Plain text | Never (voided only) |
| `sale_items` | None (only what was sold) | | Never |
| `payments` | Description (may hold the client's name or a staff note), receipt email, `sale_draft` (client's name), Stripe ids | Plain text | Never |
| `saved_cards` | Stripe Customer and card ids, brand, last 4, expiry | Card token as a SHA-256 hash | Never |
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
| `izzy_appointments` | Cookie | The id and manage token of up to 10 appointments | Each entry 30 days after the appointment ends; the cookie's `Max-Age` is 60 days; "Forget me" |
| `izzy.details.v1` | localStorage | Name, number and email, only with "Remember me" on (it starts off unless this browser already remembers the client) | "Forget me"; "Not you?" |
| `izzy.card.v1` | localStorage with "Remember me"; sessionStorage otherwise | Card token, brand, last 4, expiry, and the number of whoever added the card | "Forget me"; once booked, or when the tab closes, if not remembered |
| `izzy.cardCheckout.v1` | sessionStorage | The trip to Stripe: card token, session id, number | On return from Stripe; when the tab closes |
| `izzy.booking.v1` | sessionStorage | The booking in progress, including name, number, email and note | Once booked; when the tab closes; "Forget me" |
| `izzy.lastBooked.v1` | sessionStorage | The last booking's id | When the tab closes; "Forget me" |
| `izzy.visits.v1`, `izzy.visitCounted.v1`, `izzy.installHint.v1` | localStorage and sessionStorage | How many visits, and whether (and when) the Add to Home Screen bar was closed or the app installed | Never; used only for that bar |
| `izzy.business.session.v1` | localStorage | This computer's Business session: token, id, name and dates. Never the owner key. | Sign out; when the server refuses the session; after 30 days |
| `izzy.business.lastBarber.v1` | localStorage | The barber last picked for "Sold by" (an id only) | Never |
| Demo only: `izzy.demo.v1`, `izzy.demo.appointments.v1`, `izzy.demo.business.v1`, `izzy.demo.business.session.v1` | localStorage | Demo bookings with a manage token and a 53-bit scrambled code of the number (no name, number, email or note); the Business demo's sample shop and sign-in | "Forget me"; "Reset the demo"; 60 days after a booking ends. The real site deletes them if it's opened at the demo's address. |

"Forget me on this computer" on My appointments clears the details, the card, the appointment list, the cookie and the booking in progress (`server/web/src/pages/AppointmentsPage.tsx` (web)). It changes nothing on the server: the appointments stay booked.

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
- **Google's and Yelp's image servers:** for reviewers' photos, on the live site only (see 2.13).
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
- **What the page tells clients:** "Your name and number are sent only to Izzy Clipz Barbershop, to book and manage this appointment." (`DetailsStep.tsx`). In the demo: "Demo version: your name and number stay on this [device]. Nothing is sent to Izzy Clipz Barbershop or anywhere else."
- **No legal links yet:** the footer (`server/web/src/components/Layout.tsx` (web)) has no Privacy, Terms, Cancellation Policy or Accessibility links, and the booking steps don't link the full policy or the Terms.

## 6. The client iPhone app (Izzy Clipz)

- **Permissions:**
  - The app's Info.plist asks for none: no camera, photos, location, contacts, microphone, Bluetooth or tracking (`IzzyClipz/Info.plist`, `project.yml`).
  - "Add to Calendar" uses the system's event editor without calendar access, so the app can't read the calendar (`IzzyClipz/Components/CalendarEventEditor.swift`).
  - Notifications are requested when the client turns reminders on. They're **local only**: the app doesn't register for push notifications and has no device token (`IzzyClipz/Features/Reminders/ReminderStore.swift`, `IzzyClipz/Stores/AppointmentStore.swift`).
- **Stored in UserDefaults:**
  - `customer.name` and `customer.phone`, when "Remember me" is on. It's on by default in the app (`IzzyClipz/App/AppRouter.swift`, `IzzyClipz/Stores/CustomerDetailsStore.swift`).
  - `appointments.v2`: each appointment as the server last described it, **including the client's own name, number, note, and card brand and last 4**, until 30 days after the appointment ends.
  - `favorites.barberID`.
  - `reminders.enabled`, `reminders.intervalWeeks` and `reminders.lastCut` (the date of the last haircut).
- **Stored in the Keychain:** manage tokens and the saved card (see 2.6 and 2.7). On iOS, Keychain items can remain after the app is deleted.
- **No files, databases or caches of its own.** API calls use a temporary connection with no cache and no cookies (`Packages/IzzyClipzKit/Sources/IzzyClipzKit/API/IzzyAPIClient.swift`).
- **Network:**
  - the shop's API;
  - Stripe's card page, in a private session;
  - Google's and Yelp's image servers, for reviewers' photos;
  - Vercel Blob, for product photos;
  - Apple's map tiles, for the map of the shop (MapKit, without the user's location; `IzzyClipz/Features/Visit/VisitView.swift`).
- **Links out:**
  - calling the shop;
  - directions in Apple Maps or Google Maps (`IzzyClipz/Components/ContactButtons.swift`);
  - Instagram (`IzzyClipz/Components/InstagramCard.swift`);
  - Google and Yelp review pages, and Google's terms (`IzzyClipz/Features/Reviews/ReviewsView.swift`);
  - the shop's existing website, https://www.izzyclipzbarbershop.net (the catalog's `websiteUrl`), shown in an in-app browser. That site isn't part of this codebase, and the documents in this folder don't cover it.
- **What the client can clear:** "Forget my details" (name, number and card), "Remove card", and "Remove from this list" on each appointment. All of these act on this iPhone only.
- **Demo builds:** these use an in-memory sample server, and nothing is sent to the shop (`IzzyClipz/App/DemoMode.swift`, `IzzyClipz/Services/FakeShopAPI.swift`).
- **What the app tells clients:**
  - "Your name and number are sent only to Izzy Clipz…" (`BookingDetailsView.swift`)
  - "Reminders are set on this iPhone only." (`ReminderSettingsView.swift`)
  - "Stripe keeps the card; this iPhone keeps only a key to it." (`NoShowBooking.swift`)
- **No legal links yet:** the app has no Privacy Policy, Terms, Cancellation Policy or Accessibility links.

## 7. The Business iPhone app (Izzy Clipz Business)

- **Keychain:** the owner key (see section 3).
- **UserDefaults:**
  - `pendingPaymentIntents`: payment ids and times, until each payment is settled (`IzzyClipzBusiness/Payments/PendingPayments.swift`);
  - `hasSetUpTapToPay`;
  - `hasSeenHowToTap`.

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
  - a receipt email;
  - time-off reasons.
- **Call and Text buttons:** they open the iPhone's own Phone and Messages apps (see 2.2).

## 8. Third parties

| Who | Role | What they receive | Their policy |
|---|---|---|---|
| Stripe | Payment processor (in connect mode, the shop's own connected account) | **On its card page:** card details, email, possibly the name on the card and ZIP code, plus the device and IP address. **From the server:** a Customer with no name, number or email; amounts and descriptions for fees and payments (the service, barber and time, plus the client's name in Tap to Pay descriptions without a note); receipt emails typed at Tap to Pay; appointment ids; the shop's business details. **From the Business app:** the tapped card, the iPhone's coarse location, and the SDK's usage data. | https://stripe.com/privacy |
| Vercel | Hosting: functions, CDN, Blob, cron and logs | Everything the server handles, while it handles it; product photos; request logs with IP address, browser and path | https://vercel.com/legal/privacy-notice |
| Neon | Database, through the Vercel Marketplace | Everything in section 4, including restore history | https://neon.com/privacy-policy (it now leads to the privacy notice of Databricks, which owns Neon) |
| Google | Reviews (Places API) | **From the server:** its key and the shop's place id. **From visitors:** their IP address and browser when reviewers' photos load, plus anything on Google pages they open. | https://policies.google.com/privacy (linked on the Reviews page) |
| Yelp | Reviews (Yelp's API) | The same pattern as Google | https://www.yelp.com/tos/privacy_policy |
| Apple | App Store; Tap to Pay on iPhone; MapKit map tiles; the system calendar editor and local notifications (both on the device); Apple Pay on Stripe's page | What Apple's services need in order to work | https://www.apple.com/legal/privacy/ |
| Meta (Instagram) | Links only | Nothing from the apps or the site | |
| GitHub | Code hosting and CI | No client data. Tests use 555 numbers. The smoke test books "Smoke test" with a 555-01xx number on the live server and then cancels it (`server/scripts/smoke.ts`). | |

Both branches were searched. The code uses no ad networks, analytics or crash-reporting services, data brokers, or email or text-message services.

## 9. Can the privacy policy say it?

| Claim | True today? | Evidence and suggested wording |
|---|---|---|
| No analytics or tracking | Yes, for the website, client app and server | No analytics, crash-reporting or attribution code. Both manifests set `NSPrivacyTracking` to false. No App Tracking Transparency or ad identifier. Say that the Business app, used by staff, includes Stripe's payment software, which reports usage and approximate location to Stripe, and that the host keeps request logs. |
| No ads | Yes | No ad code |
| We don't sell data or share it for advertising | Yes | Only service providers receive it. Mention that Google and Yelp see visitors' IP addresses when reviewers' photos load. |
| No marketing texts or emails | Yes | No email or text code. Staff may call or text clients one to one about an appointment from the shop's phone. Stripe emails a receipt when staff enter a receipt email, and may email receipts if the shop turns that on in Stripe. |
| Fonts are self-hosted | Yes | `@fontsource-variable/inter`. Don't say "nothing loads from other sites": reviewers' photos do, and so does Stripe's page when a client adds a card. |
| One cookie, used only to carry appointments into the Home Screen app | Yes | See 5.2. It's strictly functional. Say that it's sent to the shop's server with requests, and that the server ignores it. |
| We don't keep IP addresses | Almost | We keep a scrambled IP address for up to about 2 days to stop abuse. The host also processes IP addresses in its logs, for 1 hour to 30 days depending on the plan. |
| Card numbers never reach the shop | Yes | They go only to Stripe's page and Apple's Tap to Pay. Say that Stripe keeps the card, and the email typed on its page, in the shop's Stripe account. |
| "Your name and number are sent only to Izzy Clipz" (shown in the apps and on the site) | Almost | The hosts handle the details on the shop's behalf. Stripe gets the client's name in Tap to Pay descriptions (G5). The line doesn't mention email (G9). |
| Reminders stay on your phone | Yes | They're local notifications only. |
| Do Not Track and Global Privacy Control | Nothing to switch off | There's no cross-site tracking, and no code reads either signal. The policy can say so. |
| Data stays in the US | Yes, for hosting | Functions, database and photos are in `pdx1` (Oregon). Vercel's CDN serves files from its nearest location. Stripe, Google, Yelp and Apple follow their own terms. |
| We delete your details after a set time | **No** | Nothing deletes appointments, sales, payments or saved cards (G1, G2). The documents promise it; it must be built first. |
| You can ask us for a copy, a correction or deletion | Only by hand | There's no tooling for it (G3). The documents promise it; the tools must be built first. |
| The service isn't for children | Yes | No age questions, nothing aimed at children, and no children's services on the menu (`server/data/catalog.json`). A parent booking for a child gives their own number. |

## 10. Privacy manifests

**Client app** (`IzzyClipz/Resources/PrivacyInfo.xcprivacy`):

- **What it declares:**
  - Tracking is off.
  - It collects **Name, Phone Number, Payment Info and Other User Content**, each linked to the user, not used for tracking, and used for app functionality.
  - Its only required-reason API is UserDefaults, with reason `CA92.1`.
- **How it matches the code:**
  - Name and number are collected; the note counts as other user content; the card's brand, last 4 and expiry kept with the booking count as payment info.
  - UserDefaults is the only required-reason API in the app's own code. `CA92.1` fits because the data is the app's own; the other UserDefaults suites also belong to the app (for tests and the demo).
- **Suggested additions:**
  - **Email Address (consider adding):** Stripe's card page, opened from the app, saves the email the client types to the shop's Stripe account (see 2.7).
  - **Purchase History (a judgment call):** visits and no-shows are linked to the person.

  The app collects nothing else.

**Business app** (`IzzyClipzBusiness/Resources/PrivacyInfo.xcprivacy`):

- **What it declares:** tracking is off, it **collects nothing**, and it uses UserDefaults with reason `CA92.1`.
- **Stripe's SDK manifest:** Stripe's SDK brings its own manifest, which Xcode adds to the app's privacy report. It declares coarse location and product interaction (not linked, no tracking), UserDefaults with reason `CA92.1`, and disk space with reason `E174.1`.
- **What the app itself sends:**
  - product photos (Photos or Videos);
  - clients' names, numbers, notes and receipt emails typed by staff;
  - names on sales and void reasons.
- **Recommended App Store Connect answers:**
  - Coarse Location and Product Interaction (Stripe);
  - Photos or Videos;
  - to be safe, Name, Phone Number, Email Address and Other User Content, for the clients' details that staff enter.

  Optionally, add the app's own items to its manifest too.
- **Minor:** `NSPhotoLibraryUsageDescription` is present even though the photo picker doesn't need library access. It's harmless.

## 11. Gaps and proposed changes

These are listed with the highest priority first. Each is either a change to the code or a sentence the documents need.

**Status in the documents:**

- **Promised by the documents, so they must be built before the live version goes public:** G1, G2 and G3, plus publishing and linking the documents, showing the Terms at booking, and capping the fee at the service's price (see `research.md` §18).
- **Disclosed in the Privacy Policy instead of changed:** G4, G5 and G6.
- **Recommended, not promised:** G7 to G12.

### G1. No retention period for clients' details

- **Now:** names, numbers, emails and notes stay on appointments forever.
- **What the documents promise:**
  - Remove them **12 months after the appointment**, except while a fee for it is still pending.
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

- **Now:**
  - The server's row, and the Customer and card at Stripe, stay forever.
  - "Remove card" and "Forget me" clear only the device.
  - There's **no time limit for charging a fee after the visit** (`server/src/feecase.ts`, `server/src/noshowfee.ts`).
- **What the documents promise:**
  1. **A charging deadline of 7 days after the appointment's start.** After it, the server refuses a new fee attempt. It's fairer to clients, it gives the card agreement a clear end (card-network rules, `research.md` §9.2), and it tells the server when a card is no longer needed.
  2. **`DELETE /api/cards`**, called with `X-Card-Token`:
     - When no booking still needs the card, it detaches the card (`paymentMethods.detach`) and deletes the Stripe Customer (`customers.del`). The card can then no longer be charged, and the email Stripe collected is no longer on the shop's account. (Stripe keeps its own records as the law requires.)
     - A booking still needs the card if it's upcoming, still inside the 7-day charging deadline, or has a fee pending. In that case, mark the card and let the daily job delete it once those have passed.
     - Call it from "Remove card" and "Forget my details" in the app, and from "Forget me" (and "Not you? Forget me") on the website.
  3. **The daily job** deletes cards that have expired, or haven't been used for a booking in 12 months, or were marked for deletion, as long as no booking needs them.
  4. **Code changes:**
     - Add those Stripe calls to `StripeClient` (`server/src/deps.ts`).
     - Add `removed_at` and `delete_requested_at` to `saved_cards`, and allow its Stripe ids to be null once the card is removed.
  5. **Wording in the Privacy Policy:** "Your saved card stays with Stripe so you can book again quickly, until the first of these happens: the card expires; 12 months pass without it being used for a booking; you remove it ... or ask us to delete it. We then ask Stripe to delete it ... as soon as none of your bookings still needs it."

### G3. No way to answer requests for a copy, a correction or deletion

- **Now:**
  - Only raw database commands can find or delete one client's data.
  - Nobody can edit a name or number after booking.
- **What the documents promise:** a copy (including the agreed cancellation terms), a correction, and deletion, after checking the person by calling or texting the number on file.
- **Proposal:** owner-run scripts alongside `npm run migrate`:
  - `npm run privacy:find -- --phone "+1…"` (or `--email`) lists that person's appointments (with `no_show_policy` and `no_show_consent_at`), sales, payments and saved cards, and exports them as JSON.
  - `npm run privacy:correct -- --appointment <id> --name "…"` (and `--phone`, `--email`) fixes a typo on an appointment and its sale.
  - `npm run privacy:forget -- --phone "+1…"` applies G1's changes to those rows straight away, except rows a booking still needs (upcoming, inside the 7-day charging deadline, or with a fee pending), and deletes the person's saved cards at Stripe as in G2.
  - The policy describes this process, whether or not the CCPA applies (see `research.md` §3).

### G4. Stripe's page collects an email

- The email typed on Stripe's page, and possibly the name on the card and ZIP code, is saved on the shop's Stripe account. The server never reads it.
- The Privacy Policy discloses it. Check the fields once in test mode.
- No code change is needed.

### G5. The client's name goes to Stripe with Tap to Pay payments

- **Now:** without a note, the description is "<service> with <barber> for <client>". It's sent to Stripe and kept in `payments.description`.
- **In the documents:** the Privacy Policy says the description sent to Stripe can include the client's name.
- **Optional fix:** drop " for <client>" in `IzzyClipzBusiness/Payments/CheckoutModel.swift`. The policy stays true either way.
- **Related clean-up:**
  - Stop keeping the receipt email after the payment, since Stripe has it.
  - Clear `sale_draft` when its sale is recorded (`server/src/sales.ts`).

### G6. Reviewers' photos load from Google and Yelp

- **In the documents:** disclosed (see 2.13).
- **Alternatives:** show the reviewers' initials instead of photos, or pass the photos through the server without storing them (check Google's terms first).

### G7. The IP hash has no secret

- Use an HMAC with a server secret in `ipKey` (`server/src/ratelimit.ts`), for example a new setting called `RATE_LIMIT_SECRET`. The stored value can then no longer be turned back into an IP address.
- Keep the retention at about 2 days.

### G8. The live site has no Content-Security-Policy or Permissions-Policy

- The demo has both. Add them to `server/vercel.json` (web).
- Allow images from Vercel Blob and from Google's and Yelp's photo servers, then check that the trip to Stripe's card page still works.
- **Why it matters:** these headers limit the harm of any injected script. That's important here because the cookie and localStorage hold manage tokens.

### G9. The website's email field has no use in the code

- The Privacy Policy says it's optional and used only to contact the client about the appointment.
- Optionally, change the line under the form to "Your details are sent only to…", since it mentions only the name and number.
- The app doesn't ask for an email.

### G10. More clean-up in the daily job

- Delete ended computer sessions and expired Stripe Connect states every day. Today this happens only at the next computer sign-in or Stripe connection. (The Privacy Policy describes today's behavior.)
- If the owner wants, clear time-off reasons after 12 months.

### G11. App Store privacy answers

See section 10:

- For the client app, consider adding Email Address.
- For the Business app, give its real answers: Stripe's coarse location and product interaction, product photos, and the clients' details that staff enter.

### G12. Smaller points

- **The cookie is sent to the server with every request.** Optionally, set it with `Path=/appointments`, the only place it's read, after checking that the Home Screen import still works.
- **"Remember me" starts on in the app but off on the website.** Either default is fine for the documents, which describe both. `research.md` §8.3 item 9 recommends unticked in the app too (owner decision).
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
| Name, number, email and note on appointments | Server | 12 months after the appointment (later only while a fee is pending) | G1 (today: forever) |
| Client's name on sales; void reasons | Server | 12 months | G1 (today: forever) |
| Receipt emails, payment descriptions, checkout tickets | Server | At most 12 months | G1 (today: forever) |
| What was booked, prices, sales totals | Server | Kept for the shop's records, without personal details | n/a |
| Saved card | Stripe and server | Until it expires, goes 12 months unused, or is removed, once no booking needs it | G2 (today: forever) |
| Agreed policy text and its time | Server | Kept with the appointment, no longer linked to a person after 12 months | G1 |
| Scrambled IP address for rate limits | Server | About 2 days | Now |
| Request logs | Vercel | 1 hour (Hobby), 1 day (Pro), up to 30 days (Observability Plus) | Vercel |
| Database restore history | Neon | 6 hours to 30 days, depending on the plan | Neon |
| Yelp reviews | Server | At most 24 hours | Now |
| Google reviews | Server | Not stored | Now |
| Computer sign-ins | Server and browser | Up to 30 days (ended ones deleted at the next sign-in) | Now (G10 would make it daily) |
| Product photos | Vercel Blob | Until replaced or deleted (copies cached for up to 30 days) | Now |
| Appointments and tokens on the device | iPhone and browser | 30 days after the appointment | Now |
| Remembered details and card token | iPhone and browser | Until the client chooses "Forget" | Now |
| Booking in progress | Browser tab | Until the tab closes or the booking is made | Now |

## Other things noticed (for the other documents)

- **"In the app":**
  - The policy text stored with every protected booking says "Cancelling in the app…", including for bookings made on the website (`policyText` in `server/src/noshow.ts`).
  - The website's fee notice adds "Cancelling on this website, under My appointments, works the same as cancelling in the app." (`server/web/src/booking/TimeStep.tsx` (web)), and the Cancellation & No-Show Policy says both count.
  - Optionally, change the server's wording to "online" for new bookings. Existing bookings keep the text they agreed to.
- **"Is charged" and "may charge":** the fee notice says "is charged" (`feeWarning`), while the agreed text says "may charge" (`policyText`). The documents follow the agreed text (the shop decides each time). Optionally, make the notice say "may be charged" too.
- **Only clients' own online cancellations can count as late:**
  - A booking the shop cancels (after a phone call, for example) is never charged.
  - A no-show can be charged only after the appointment's start, and only if the client never cancelled (`feeCase` in `server/src/feecase.ts`).
- **No-show protection is off** until the owner turns it on, even when Stripe is set up. When it's on:
  - the defaults are 100% of the service price and a 1-hour window;
  - the owner can choose 1% to 100% of the price or a flat $0.50 to $500, and a window from 30 minutes to 48 hours (`server/src/noshow.ts`);
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
- Stripe Terminal location requirement and the Bluetooth key: [Terminal iOS setup](https://docs.stripe.com/terminal/payments/setup-integration?terminal-sdk-platform=ios)
- Stripe Terminal 6.0.0's privacy manifest: read from the [6.0.0 release archive](https://github.com/stripe/stripe-terminal-ios/releases/download/6.0.0/StripeTerminal.xcframework.zip), whose checksum matches the one [Stripe's Swift package](https://raw.githubusercontent.com/stripe/stripe-terminal-ios-spm/6.0.0/Package.swift) pins
- Privacy manifests in apps and SDKs: [Apple: Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
