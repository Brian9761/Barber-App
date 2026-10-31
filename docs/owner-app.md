# Izzy Clipz Business (the owner app)

The shop owner's iPhone app: the schedule, walk-ins and phone bookings,
blocked time, the shop's products, and card payments with Tap to Pay on
iPhone through Stripe. It's the `IzzyClipzBusiness` target and scheme in
`project.yml` (bundle ID `com.izzyclipz.business`, iOS 18 or later).

## What each tab does

- **Schedule**: one shop day at a time (‹ › or the date picker), everyone or
  one barber. Refreshes every minute while it's on screen, and on pull.
  Today's schedule moves on to the new day after the app sat open overnight.
  Tap an appointment to call or text the client, mark it completed or
  no-show, cancel it (the app asks first), reopen it, or take payment.
  **Block time** blocks a barber or the whole shop; swipe a block to remove it.
  A block over several days shows its dates, and removing it removes all of
  it (the app says so first).
- **New booking**: walk-ins and phone bookings. Pick the service and a
  barber (or anyone free), then **Now** for a walk-in who's here (from this
  minute, while the shop is open), **Next open slot** for the next time that
  hasn't started, or a day (today to 60 days ahead) and time. A day that has
  passed moves on to today when the app comes back. The client's name is
  needed; a phone number is optional. If the connection drops before the
  answer arrives, Book again finds the booking that went through instead of
  booking the client twice.
- **Take payment**: the amount on the keypad (filled in from an
  appointment's fixed price), an optional note and receipt email, then
  **Tap to Pay on iPhone**. The result screen says Paid, Declined,
  Cancelled or what to check; only a payment Stripe confirms as
  succeeded shows as paid. **Payments today** lists what came in.
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
