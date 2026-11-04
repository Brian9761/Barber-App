<!-- The notes on the public test-build release page. When it publishes, the release job in .github/workflows/test-builds.yml fills in the words in double braces. -->
Demo versions of the two Izzy Clipz apps, to try on an iPhone or a Mac before they're in the App Store.

**This is a demo on sample data.** No booking is real, no real money moves, and nothing reaches the shop. Each app forgets everything when it's closed and starts over the next time.

## Which file do I need?

- **IzzyClipz-Demo.ipa**: Izzy Clipz, the app clients book with, for an iPhone with iOS 17 or later.
- **IzzyClipzBusiness-Demo.ipa**: Izzy Clipz Business, the shop's app (schedule, walk-ins, products, payments), for an iPhone XS or newer with iOS 18 or later.
- **IzzyClipz-Demo-Simulator.zip**: the client app for the iPhone Simulator on a Mac.
- **IzzyClipzBusiness-Demo-Simulator.zip**: the shop's app for the iPhone Simulator on a Mac with Apple silicon (M1 or later).
- **SHA256SUMS.txt**: fingerprints of the four files above, to check a download arrived whole (optional).

The two "Source code" downloads GitHub adds at the end are for developers; you don't need them.

## Install on an iPhone

You need a Mac or Windows computer, the iPhone's cable and an Apple ID. A free Apple ID works (you can make a spare one just for this).

1. Download the `.ipa` of the app you want.
2. Install it with [Sideloadly](https://sideloadly.io) on the computer: connect the iPhone, drag the `.ipa` into Sideloadly, type your Apple ID and click Start.
   Or with [AltStore](https://altstore.io) (its website shows how to set it up): download the `.ipa` on the iPhone, then in AltStore tap My Apps, then +, and choose it.
3. Turn on Developer Mode on the iPhone: Settings → Privacy & Security → Developer Mode, turn it on and tap Restart. After the restart, tap Turn On and enter your passcode.
4. Trust the developer, which is your own Apple ID: Settings → General → VPN & Device Management → your Apple ID (under Developer App) → Trust.
5. Open the app.

With a free Apple ID:

- The app stops opening after **7 days**. Install it again the same way (or refresh it in AltStore) to keep using it.
- An iPhone can have only **3** apps installed this way at a time. AltStore counts as one, which still leaves room for both Izzy Clipz apps.

## Try it on a Mac

1. Install Xcode from the Mac App Store (it's free), open it once and let it download iOS if it asks.
2. Open the Simulator: in Xcode's menu bar, Xcode → Open Developer Tool → Simulator.
3. Unzip the `.zip` you downloaded (double-click it, if your browser didn't already). You get `IzzyClipz.app` or `IzzyClipzBusiness.app`.
4. Drag that `.app` onto the Simulator's iPhone (it won't open on the Mac itself). It installs; click its icon to open it.

The shop's app needs a Mac with Apple silicon (M1 or later) for this; the client app also works on Intel Macs.

## What doesn't work in the demo

- **Real Tap to Pay on iPhone.** Taking real cards needs Apple's Tap to Pay entitlement, which Apple gives only to a paid Apple Developer account (the shop's). In the demo, taking a payment shows a practice tap screen instead, marked "Test mode — no real charge": no card is read and no money moves.
- **Anything reaching the shop.** Bookings, cancellations and payments stay inside the app. The products and reviews are samples, not the shop's.

## This build

Built on {{DATE}} from commit [{{COMMIT}}]({{COMMIT_URL}}). Each new build replaces this one, and the download links stay the same.

SHA-256 of each file:

```
{{SHA256SUMS}}
```

To check the files on a Mac (optional): put them in one folder, open Terminal there and run `shasum -a 256 -c SHA256SUMS.txt`. Each line should end in OK.
