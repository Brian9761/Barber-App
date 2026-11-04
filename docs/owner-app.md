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
  An online booking with a card on file shows the card and its fee, and
  lets you charge a no-show or a late cancellation (see
  [No-show protection](#no-show-protection)). Rows say "Card on file ·
  Visa •••• 4242", "Cancelled late" and "No-show fee $35 charged".
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
  succeeded shows as paid. **Payments today** lists what came in,
  including no-show and late cancellation fees (labelled as such, with
  their own subtotal). If the app can't reach the server, Take payment
  says so, with Check again and Practice in test mode.
- **Products**: add, edit (photo from the library or the camera), hide or
  show in the customer app, delete.
- **Settings**: server and Stripe status, **No-show protection**, Tap to
  Pay setup and "How to Tap", the owner key, sign out, version.

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

## No-show protection

When it's on (Settings → **No-show protection**), clients who book online
add a card (or Apple Pay) on Stripe's card page before they book. Nothing
is charged then. While booking, on Pick a day and time and again on
Review, they see a notice such as "Full Service Cancellation & No-Show
Fee" (its title and amounts follow your settings), and they agree to the
policy above Book appointment. Walk-ins and phone bookings made in this
app never have a card on file.

**What can be charged.** The same fee, for two cases, and you decide each
time:

- **A no-show**: the appointment is marked No-show, it has started, and
  the client never cancelled. **Mark no-show** shows only once a booking
  with a card on file has started: until then the client can still cancel
  in the app (free until the late-cancellation window starts).
- **A late cancellation**: the client cancelled in the app less than the
  window before the start (1 hour to begin with). Cancelling earlier is
  free. The shop cancelling is never charged, and neither is a booking
  the client cancelled that you reopened: once it's reopened, it can't be
  charged a no-show fee either (Reopen says so first). To keep a fee for
  a client who wants their time back, ask them to book again in the app.

Each booking keeps the fee and window it was booked with, so a change in
Settings only affects new bookings. Turning protection off works the same
way: new online bookings don't need a card, and bookings already made with
one keep their fee, which you can still charge.

**Charging.** Open the appointment. The **Card on file** section shows the
card, the fee agreed at booking and what it covers. **Charge no-show fee
($35)** or **Charge late cancellation fee ($35)** asks first ("Charge $35
to Kim Sample's Visa •••• 4242?"), then shows Stripe's answer:

- **Charged**: the money is in Stripe, and Payments today lists it. Only a
  charge Stripe confirms counts as charged.
- **Declined**, with the bank's reason in plain words. **Charge again**
  tries once more (it asks first), or ask the client to pay at the shop.
  Once the fee can't be charged any more (you reopened the appointment,
  say), the section says why instead.
- **The card needs the client to approve it**: their bank wants them to
  confirm the charge, which they can't do from here. Ask them to pay at
  the shop.
- **Not confirmed yet** (the answer got lost on the way): **Check again**
  finishes that charge. If it went through, it shows as charged; if it
  never reached Stripe, it's sent now (still only once). To not charge it,
  reopen the appointment first: then Check again only asks Stripe how it
  went, and nothing more is charged.

When no answer comes back at all (a dropped connection, say), the app
loads the day again and shows the fee as the server has it. If the charge
went through after all, it shows as charged (and Payments today lists
it); if Stripe said no, the decline shows. "We don't know yet if the card
was charged" shows only while that's still true: the day couldn't be
loaded, or the fee is still waiting for Stripe.

A fee is charged at most once per appointment, however many times you tap.
While a status change is on its way (Reopen, say), the fee can't be
charged, and while a fee is being charged, the status can't change. Once a
fee is charged, the **Payment** section says **Service not paid** with a
line that the fee was charged to the card on file, so the fee isn't taken
again at the counter.

**Refunds and disputes.** Reopening an appointment never refunds a fee
(the app says so before it reopens one). To give money back, refund it in
the Stripe Dashboard: find the payment (its description starts with
"No-show fee" or "Late cancellation fee", then the service, barber and
time) and choose Refund. The policy the client agreed to, and when, are
kept with the booking as evidence if a client disputes a fee.

**Settings → No-show protection**: on or off; the fee as a share of the
service (the stepper goes from 10% to 100% in steps of 5; 100%, the full
service price, to begin with) or a flat amount ($0.50 to $500); **Charge
late cancellations** on or off, and the window (30 minutes to 48 hours);
an example ("A $40 haircut: $40"); and what clients see, for the example
haircut. **Save** sends only what you changed, so a change made on another
iPhone meanwhile stays; Cancel asks before it throws changes away. If
Stripe isn't set up on the server, clients aren't asked for a card, even
with this on.

**Costs** (Stripe's US standard pricing):

- Each fee is an online card payment: 2.9% + 30¢ (about $1.32 of a $35
  fee).
- A refund costs nothing more, but Stripe keeps its fee from the payment.
- A dispute costs $15, which Stripe keeps whether you win or lose.
  Fighting it with evidence costs another $15, which comes back if you
  win.

## Test mode

When the iPhone can't do Tap to Pay (or the server has no Stripe key yet
and the owner taps **Practice in test mode**), payments use a simulated
reader: every screen says "Test mode — no real charge", nothing is read,
and nothing is sent to Stripe or recorded.

## Tests

- `IzzyClipzBusinessTests`: the stores, the checkout, the sample server,
  the simulated reader, photos, sessions, Stripe's error codes, and
  no-show protection (what an appointment's fee section says and offers,
  charging it, the labels, and the settings screen's store).
- `IzzyClipzBusinessUITests`: every flow on the in-memory sample server
  (`-ui-testing`), with screenshots named `O01-Sign-In` and so on. Launch
  arguments `-signed-in`, `-fake-offline`, `-fake-stripe-not-configured`,
  `-fake-slot-taken`, `-fake-payment-incomplete`, `-fake-empty` and others
  (see `LaunchArgument` in `AppEnvironment.swift`) make the sample server
  misbehave on purpose. For no-show protection, `-fake-cards-on-file`
  adds three clients who booked online with Visa 4242 for a $35 haircut
  with Flowxbori: Kim Sample (10 AM, a no-show), Lee Sample (11:30 AM,
  cancelled in the app at 10:50 AM: a late cancellation) and Nia Sample
  (2:30 PM, not started). `-fake-no-show-declined` and
  `-fake-no-show-needs-action` make Stripe say no to the next fee,
  `-fake-no-show-unreachable` keeps the next fee from reaching Stripe (it
  waits, and Check again then charges it), and `-fake-no-show-answer-lost`
  charges the next fee (or declines it, with `-fake-no-show-declined`) but
  loses the answer on the way back.
- The app icon is generated by `scripts/generate_business_assets.py`.
