# Izzy Clipz Business (the owner app)

The shop owner's iPhone app: the schedule, walk-ins and phone bookings,
blocked time, the shop's products, and card payments with Tap to Pay on
iPhone through Stripe. It's the `IzzyClipzBusiness` target and scheme in
`project.yml` (bundle ID `com.izzyclipz.business`, iOS 18 or later).

## What each tab does

- **Schedule**: one shop day at a time (‹ › or the date picker), everyone or
  one barber. Refreshes every minute while it's on screen, and on pull.
  Today's schedule moves on to the new day after the app sat open overnight
  (an appointment left open stays until you go back).
  Tap an appointment to call or text the client, mark it completed or
  no-show, cancel it (the app asks first), reopen it, or take payment.
  **Block time** blocks a barber or the whole shop; swipe a block to remove it.
  A block over several days shows its dates, and removing it removes all of
  it (the app says so first).
- **New booking**: walk-ins and phone bookings. Pick the service and a
  barber (or anyone free), then **Now** for a walk-in who's here (from this
  minute, while the shop is open), **Next open slot** for the next time that
  hasn't started, or a day (today to 60 days ahead) and time. When the app
  comes back, a day that has passed moves on to today and the times are
  checked again. The client's name is needed; a phone number is optional.
  If the connection drops before the answer arrives, Book again finds the
  booking that went through instead of booking the client twice.
- **Take payment**: the amount on the keypad (filled in from an
  appointment's fixed price), an optional note and receipt email, then
  **Tap to Pay on iPhone**. Cancel works until the card is read; from
  then on the screen says Processing. The result screen says Paid,
  Declined, Cancelled or what to check; only a payment Stripe confirms as
  succeeded shows as paid. **Payments today** lists what came in. If the
  app can't reach the server, Take payment says so, with Check again and
  Practice in test mode.
- **Products**: add, edit (photo from the library or the camera), hide or
  show in the customer app, delete.
- **Settings**: server and Stripe status, Tap to Pay setup and "How to
  Tap", the owner key, sign out, version.

## Going live

1. **Server**: set `OWNER_KEY` (a long random secret, at least 32
   characters) on Vercel and redeploy. Sign in to the app by pasting it.
2. **Stripe**: in the Stripe Dashboard, create a **Terminal location**
   (Terminal → Locations) with the shop's address (the app shows customers
   the name "Izzy Clipz" on Apple's Tap to Pay screen). Set
   `STRIPE_SECRET_KEY` (start with the `sk_test_…` key) and
   `STRIPE_TERMINAL_LOCATION_ID` (`tml_…`) on the server. Settings in the
   app then shows "Set up", "Test mode" and the location.
3. **Apple**: Tap to Pay on iPhone needs Apple's entitlement
   `com.apple.developer.proximity-reader.payment.acceptance` (already in
   `IzzyClipzBusiness.entitlements`).
   - The **Account Holder** of an **organization** Apple Developer account
     requests it at developer.apple.com/contact/request/tap-to-pay-on-iphone
     (name Stripe as the payment provider, United States).
   - The development entitlement comes first (usually 1–2 business days):
     enable "Tap to Pay on iPhone" for `com.izzyclipz.business` under
     Identifiers → Additional Capabilities, and let Xcode refresh the
     profiles. Until then, the app shows "Tap to Pay isn't enabled for this
     app yet" and offers test mode.
   - TestFlight and the App Store need the **publishing** entitlement:
     reply to Apple's email with screen recordings of the setup, "How to
     Tap" and a payment, as Apple asks. Consider distributing the app as an
     Unlisted App.
4. **First run on the iPhone** (an iPhone XS or later with the latest iOS,
   a passcode, signed in to iCloud): Settings → **Set up Tap to Pay on
   iPhone**. Apple asks the owner to accept its terms once, the iPhone
   configures itself (a progress bar, up to a couple of minutes), then
   "How to Tap" shows. Allow location when asked: card networks need it.
5. **Test**: with the `sk_test_…` key, take a payment with a Stripe
   physical test card (amounts ending in .00 approve, .05 declines).
   Real cards and Apple Pay don't work in test mode.
6. **Live**: switch the server to the `sk_live_…` key and a location
   created in live mode (`STRIPE_TERMINAL_LOCATION_ID`). The app
   reconnects to the new location by itself; Settings shows "Live: real
   money". Optionally add `STRIPE_WEBHOOK_SECRET` for the webhook. If the
   location is still the test-mode one (or has a typo), Tap to Pay says
   "Stripe didn't accept the Terminal location set on the server" until
   it's fixed, and the server's logs show Stripe's own error.
7. **No-show protection** (a card on file for online bookings) stays off
   while you test, whatever Stripe key the server has: a test key would
   send clients to a test-mode card page that turns real cards down. Turn
   it on in Settings → No-show protection only with the live key, once the
   customer app version with the card screen is in the App Store.

## The shop's own Stripe account (Stripe Connect)

Instead of putting the shop's own Stripe key on the server (step 2 above),
the server can run on the app developer's Stripe Connect platform: then the
owner connects the shop's **own** Stripe account from Settings, and Tap to
Pay, saved cards and no-show or late-cancellation fees all go to it (he
pays Stripe's fees and sees everything in his own Stripe Dashboard).

- **Server** (the developer, once): turn on Connect and set its branding in
  the developer's Stripe Dashboard, then set `STRIPE_SECRET_KEY` to the
  platform's key, `STRIPE_CONNECT=on`, `PUBLIC_BASE_URL` (the server's https
  address) and `STRIPE_CONNECT_WEBHOOK_SECRET` (from a Connect webhook
  endpoint). `STRIPE_TERMINAL_LOCATION_ID` isn't needed: the server makes
  the shop's Terminal location on his account the first time Tap to Pay
  needs it. The steps are in `server/README.md` (Stripe Connect).
- **The owner**: Settings → **Connect Stripe** opens Stripe's own window,
  where he signs in or signs up and finishes setting up. Back in the app,
  Settings shows what Stripe says: "Connected. Card payments are on.", or
  what's left to do ("Finish setting up Stripe to take card payments.",
  "Stripe is checking your details…", "Stripe paused card payments: open
  Stripe to fix it."). Until it's connected, Tap to Pay, saving cards and
  no-show protection stay off ("Connect Stripe in Settings to take card
  payments."). Disconnecting only forgets the account in the app; it stays
  open at Stripe.

## Using the Business area on a computer

The website's Business area signs in with a code, never the owner key:
Settings → **Use on a computer** shows a 6-digit code for 10 minutes, and
the owner types it on the website. The computer stays signed in for 30
days; Settings can sign any computer (or all of them) out, and so can the
website's Sign out. Tap to Pay, new codes and disconnecting Stripe stay in
the app on the iPhone. A new `OWNER_KEY` signs every computer out.

## Test mode

When the iPhone can't do Tap to Pay (or the server has no Stripe key yet
and the owner taps **Practice in test mode**), payments use a simulated
reader: every screen says "Test mode — no real charge", nothing is read,
and nothing is sent to Stripe or recorded.

## Tests

- `IzzyClipzBusinessTests`: the stores, the checkout, the sample server,
  the simulated reader, photos, sessions and Stripe's error codes.
- `IzzyClipzBusinessUITests`: every flow on the in-memory sample server
  (`-ui-testing`), with screenshots named `O01-Sign-In` and so on. Launch
  arguments `-signed-in`, `-fake-offline`, `-fake-stripe-not-configured`,
  `-fake-slot-taken`, `-fake-payment-incomplete`, `-fake-empty` and others
  (see `LaunchArgument` in `AppEnvironment.swift`) make the sample server
  misbehave on purpose.
- The app icon is generated by `scripts/generate_business_assets.py`.
