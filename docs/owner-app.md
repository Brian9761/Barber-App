# Izzy Clipz Business (the owner app)

The shop owner's iPhone app: the schedule, walk-ins and phone bookings,
blocked time, checkouts (services, products and amounts, paid by card
with Tap to Pay on iPhone through Stripe, in cash or another way), the
shop's analytics and products, and the shop's own Stripe account. It's
the `IzzyClipzBusiness` target and scheme in `project.yml` (bundle ID
`com.izzyclipz.business`, iOS 18 or later). The tabs are Schedule, New
booking, Take payment, Analytics and Settings.

## What each tab does

- **Schedule**: one shop day at a time (‹ › or the date picker), everyone or
  one barber. Refreshes every minute while it's on screen, and on pull.
  Today's schedule moves on to the new day after the app sat open overnight
  (an appointment left open stays until you go back).
  Tap an appointment to call or text the client, **Check out** (the main
  action for a booked or completed appointment that isn't checked out:
  it opens Take payment with its service on the ticket), mark it done or
  a no-show, cancel it (the app asks first), or reopen it. A checked-out
  appointment says "Paid $60 · Cash" and stays completed until its sale is
  voided (Take payment → Today's sales). An appointment paid by card
  before sales existed asks before checking out something extra.
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
- **Take payment** is a checkout ("Check out"):
  - **Who it's for**: the appointment it started from, or "Walk-in" with
    an optional name. ✕ makes it a walk-in for the same client.
  - **Sold by**: the barber who gets credit (required): the appointment's
    barber, otherwise the last one chosen on this iPhone.
  - **Items**, each with its price (tap to change it), a quantity for
    products, and a remove button: **+ Service** (the barber's services at
    that barber's prices; a "From" price is where it starts), **+ Product**
    (the shop's products with photos, hidden ones too; one without a price
    asks for it) and **+ Amount** (the keypad, named "Other" or whatever you
    type). Checking out an appointment adds its service at its price.
  - The **total**, then **How are they paying?**: **Tap to Pay on iPhone**
    (when the iPhone can take cards), **Cash**, or **Other** (Squire, Zelle,
    Cash App…, recorded only). Cash and Other ask first ("Record a $60
    cash sale for Izzy?"), then show the receipt ("Sold $60 · Cash ·
    Izzy") with the items; **Done** clears the ticket. If the answer gets
    lost, **Record again** sends the same sale with the same
    Idempotency-Key, so it's never saved twice.
  - A card goes through Tap to Pay as before: Cancel works until the card
    is read, then the screen says Processing, and only a payment Stripe
    confirms as succeeded shows as paid. The ticket goes with the payment,
    and the server records the card sale when it goes through. The
    payment's description at Stripe is what was sold and who sold it
    ("Haircut & Beard with Izzy"), never the client's name; a note you type
    is sent as typed.
  - **No email is asked before a card payment.** Once it went through,
    **Email a receipt (optional)** sends the client a receipt through
    Stripe (`POST /api/owner/payments/:id/receipt`). The address goes to
    Stripe only: neither the app nor the server keeps it (California's
    Song-Beverly Credit Card Act; docs/legal/research.md §9.3).
  - **Today's sales** at the bottom: time, client, barber, method and
    total, voided ones struck through. A sale opens to its details; **Void
    sale** asks first, with an optional reason (for a card: refund it in
    the Stripe Dashboard: voiding doesn't refund it). **Card payments
    today** lists the card money that came in, including no-show and late
    cancellation fees.
  - If the app can't reach the server, Take payment says so, with Check
    again and Practice in test mode. While the shop's own Stripe account
    isn't connected, it says how to connect, with **Go to Settings**; cash
    and other sales work meanwhile.
- **Analytics**: how the shop is doing, live, for the whole shop or one
  barber: sales, the top barber and the leaderboard, services, products
  and productivity (see [Analytics](#analytics)).
- **Settings**: **Products** (add, edit with a photo from the library or
  the camera, hide or show in the customer app, delete), **Card payments
  (Stripe)** (see [The shop's own Stripe account](#the-shops-own-stripe-account-stripe-connect)),
  **Use on a computer**, **No-show protection**, Tap to Pay setup and "How
  to Tap", the server's status, the owner key, **Legal** (the Privacy
  Policy, Terms of Service, Cancellation & No-Show Policy and
  Accessibility pages of the shop's website, in the in-app browser), sign
  out, version.

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
   `IzzyClipzBusiness.entitlements`), and Apple's Declared Age Range needs
   `com.apple.developer.declared-age-range` (also there; with automatic
   signing Xcode turns the capability on for the app ID).
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
   "How to Tap" shows. Allow location when asked: "Stripe needs to know
   where card payments are taken, to reduce fraud and disputes, so it
   checks this iPhone's location while you take a payment with Tap to Pay
   on iPhone. Without it, Tap to Pay is turned off."
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

- **A no-show**: the appointment is marked No-show, it has ended, and
  the client never cancelled. **Mark no-show** shows only once a booking
  with a card on file has ended: until then the client may still come
  (and can cancel in the app until the start). A visit marked completed
  never becomes a no-show, even once it's reopened: the client came.
- **A late cancellation**: the client cancelled in the app less than the
  window before the start (1 hour to begin with), and more than 15
  minutes after booking. Cancelling earlier, or within 15 minutes of
  booking, is free. The shop cancelling is never charged, and neither is
  a booking the client cancelled that you reopened: once it's reopened,
  it can't be charged a no-show fee either (Reopen says so first). To
  keep a fee for a client who wants their time back, ask them to book
  again in the app.

A fee is never more than the booked service's price (the settings'
example says so, with the cheap service a flat fee is capped for), and it
can be charged only up to 7 days after the appointment's start: after
that, Charge goes away and the details say why ("It's more than 7 days
after the appointment, so the fee can't be charged."). Each booking keeps the fee and window it was
booked with, so a change in Settings only affects new bookings. Turning
protection off works the same way: new online bookings don't need a
card, and bookings already made with one keep their fee, which you can
still charge.

**Charging.** Open the appointment. The **Card on file** section shows the
card, the fee agreed at booking and what it covers. **Charge no-show fee
($35)** or **Charge late cancellation fee ($35)** asks first ("Charge $35
to Kim Sample's Visa •••• 4242?"), then shows Stripe's answer:

- **Charged**: the money is in Stripe, and Card payments today lists it. Only a
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
went through after all, it shows as charged (and Card payments today lists
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
(the app says so before it reopens one), and neither does cancelling it
afterwards (Cancel appointment says so first). To give money back, refund
it in the Stripe Dashboard: find the payment (its description starts with
"No-show fee" or "Late cancellation fee", then the service, barber and
time) and choose Refund. The policy the client agreed to, and when, are
kept with the booking as evidence if a client disputes a fee.

**Settings → No-show protection**: on or off; the fee as a share of the
service (the stepper goes from 10% to 100% in steps of 5; 100%, the full
service price, to begin with) or a flat amount ($0.50 to $500, never
more than a service's price); **Charge
late cancellations** on or off, and the window (30 minutes to 48 hours);
an example ("A $40 haircut: $40"); and what clients see, for the example
haircut. **Save** sends only what you changed, so a change made on another
iPhone meanwhile stays: loading the screen again (pull to refresh, or
coming back to it) keeps your unsaved changes and shows the other
iPhone's change everywhere else. Cancel asks before it throws changes
away. If Stripe isn't set up on the server, clients aren't asked for a
card, even with this on.

**Costs** (Stripe's US standard pricing):

- Each fee is an online card payment: 2.9% + 30¢ (about $1.32 of a $35
  fee).
- A refund costs nothing more, but Stripe keeps its fee from the payment.
- A dispute costs $15, which Stripe keeps whether you win or lose.
  Fighting it with evidence costs another $15, which comes back if you
  win.

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
  the shop's Terminal location on his account as soon as it can take card
  payments. The steps are in `server/README.md` (Stripe Connect).
- **The owner**: Settings → **Card payments (Stripe)** shows where the
  account stands: "Connected" with a green check and the business name,
  "Not connected", "Finish setting up", "Stripe is checking your details",
  "Paused by Stripe", "Uses the server's Stripe key" or "Not set up on the
  server", with the server's own message ("Connected. Card payments are
  on. Payouts to your bank are on."). **Connect Stripe** (or **Finish
  setting up**) opens Stripe's own window (`ASWebAuthenticationSession`,
  sharing Safari's sign-in), where he signs in or signs up and finishes
  setting up. Back in the app it says "You're connected. You can take card
  payments now." or "Stripe still needs a few details: tap Finish setting
  up." Closing the window shows nothing new (the account the server
  started stays, so the button then reads Finish setting up). **Open
  Stripe Dashboard** opens Stripe in Safari. **Disconnect Stripe** asks
  first: card payments stop until he connects again, and cards clients
  saved stay with the old account. Disconnecting only forgets the account
  in the app; it stays open at Stripe. Until it's connected, Tap to Pay,
  saving cards and no-show protection stay off: Take payment says how to
  connect, with Go to Settings.
- **Tap to Pay after connecting**: the first time the app connects Tap to
  Pay with his own account, Apple asks him to accept its Tap to Pay terms
  again (with the shop's Apple ID), because each Stripe account that takes
  its own payments accepts them for itself. It's once per account, on any
  iPhone.

## Using the Business area on a computer

The website's Business area signs in with a code, never the owner key:
Settings → **Use on a computer** ("See your schedule, sales and analytics
on a computer.") says to go to the server's `/business` page on the
computer and type the code. The code is big and grouped ("483 920"), with
"Expires in 9:42" counting down; it works once, for 10 minutes, and **Get
a new code** replaces it. The computer stays signed in for 30 days;
**Computers signed in** lists each one with when it was last used and
**Sign out**, and **Sign out all computers** asks first. The website's
Sign out works too. Tap to Pay, new codes and disconnecting Stripe stay in
the app on the iPhone. A new `OWNER_KEY` signs every computer out.

## Analytics

The **Analytics** tab shows how the shop is doing, live, for the whole
shop or one barber: total sales and the change from the period before,
the top sales barber, the leaderboard (by sales, services, products or
clients served), top services, products sold, daily sales, and business
productivity tiles, each with an ⓘ that says what it means. Pick Today,
Week, Month, Year or your own dates (up to 366 days). It refreshes every
30 seconds while it's on screen, and on pull. Every number is defined in
[analytics.md](analytics.md).

The store is `IzzyClipzBusiness/Stores/AnalyticsStore.swift` and the
screen `IzzyClipzBusiness/Features/Analytics/AnalyticsView.swift`. With
the sample server (UI tests and the demo version), the numbers come from
its own appointments and sales plus the 8 weeks before today
(`FakeSampleHistory`), the same on every run: this year Izzy sells the
most, Carlos the most products, and Cristian does the most cuts. The UI
tests are in `IzzyClipzBusinessUITests/AnalyticsUITests.swift`
(screenshots `O70-…` to `O79-…`).

## The legal pages and the age check

- **Settings → Legal** opens the Privacy Policy, Terms of Service,
  Cancellation & No-Show Policy and Accessibility pages of the shop's
  website (`/privacy`, `/terms`, `/cancellation-policy`, `/accessibility`)
  in the in-app browser. The website's address is the build setting
  `IZZY_WEBSITE_URL` in `project.yml` (Info.plist `IzzyWebsiteURL`): the
  current public site, `https://izzy-clipz.vercel.app`, until the shop's
  own domain replaces it there, in that one place.
- **Apple's Declared Age Range** (California's Digital Age Assurance Act,
  from January 1, 2027; docs/legal/research.md §4.2): on iOS 26 and later
  the app asks iOS, when it opens, for the person's age range against one
  gate, 13: from iOS 26.2 only where iOS says a law requires it
  (`isEligibleForAgeFeatures`), and always on 26.0 and 26.1, which can't
  say. iOS shows its own sheet the first time. The rule is the customer
  app's: only a range entirely under 13 (its highest age is 12 or less)
  shows "Izzy Clipz Business is for the shop's team" with the shop's
  number, and no details are taken. The answer is kept only in memory;
  any other answer (13 or older, declined, a range on both sides of 13),
  an error or an older iOS just carries on.

## Test mode

When the iPhone can't do Tap to Pay (or the server has no Stripe key yet
and the owner taps **Practice in test mode**), payments use a simulated
reader: every screen says "Test mode — no real charge", nothing is read,
and nothing is sent to Stripe or recorded.

## Tests

- `IzzyClipzBusinessTests`: the stores, the checkout (the ticket, cash
  and other sales with their Idempotency-Key, card sales, receipts after
  the payment), today's sales and voiding, the shop's Stripe connection,
  computer codes and sessions, the sample server, the simulated reader,
  photos, sessions, Stripe's error codes, the legal pages and the age
  check, and no-show protection (what an appointment's fee section says
  and offers, charging it, the labels, and the settings screen's store).
- `IzzyClipzBusinessUITests`: every flow on the in-memory sample server
  (`-ui-testing`), with screenshots named `O01-Sign-In` and so on. Launch
  arguments `-signed-in`, `-fake-offline`, `-fake-stripe-not-configured`,
  `-fake-slot-taken`, `-fake-payment-incomplete`, `-fake-empty` and others
  (see `LaunchArgument` in `AppEnvironment.swift`) make the sample server
  misbehave on purpose. The shop's Stripe account is connected unless
  `-fake-stripe-not-connected` (Connect Stripe then connects at once),
  `-fake-stripe-needs-info` (the first try leaves details missing) or
  `-fake-stripe-cancel` (the first try closes the window). The sample day
  has Diego's cash checkout in Today's sales, two computers signed in, and
  computer codes that come in the same order (483920 first). For no-show protection, `-fake-cards-on-file`
  adds three clients who booked online with Visa 4242 for a $35 haircut
  with Flowxbori: Kim Sample (10 AM, a no-show), Lee Sample (11:30 AM,
  cancelled in the app at 10:50 AM: a late cancellation) and Nia Sample
  (2:30 PM, not started). `-fake-no-show-declined` and
  `-fake-no-show-needs-action` make Stripe say no to the next fee,
  `-fake-no-show-unreachable` keeps the next fee from reaching Stripe (it
  waits, and Check again then charges it), and `-fake-no-show-answer-lost`
  charges the next fee (or declines it, with `-fake-no-show-declined`) but
  loses the answer on the way back.
- The app icon (the shop's white logo on black above a red "Business" mark)
  and the sign-in screen's logo are rendered from a vector tracing of the
  logo the shop sent, and replaced as files when it changes;
  `scripts/generate_business_assets.py` writes the colors.
