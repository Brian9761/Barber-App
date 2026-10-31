# Izzy Clipz — iOS App

A native iPhone app for **Izzy Clipz Barbershop**, 1919 Mission Ave, Ste 105, Oceanside, CA.

Built with SwiftUI for iOS 17 and later. Clients book an appointment with a barber (or whoever is free) on the shop's live calendar, with **no payment up front**: they pay at the shop. They can cancel in the app, get reminders, see the shop's own products (sold only at the shop) and read the shop's Google and Yelp reviews as they are today. No account is needed.

The app talks to the shop's own small server in [`server/`](server/README.md) (bookings, availability, products, reviews). The shop runs its day from the separate owner app, Izzy Clipz Business.

The look is the shop's dark "Street Drip" palette (ink, bone and one red action per screen) on the system font, with the shop's logo.

<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/01-Home.png" width="190" alt="Home screen">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/12-Book-Calendar.png" width="190" alt="Picking a day and time from the live calendar">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/15-Book-Review.png" width="190" alt="Reviewing a booking: no payment now">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/16-Booked.png" width="190" alt="You're booked">
</p>
<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/17-Home-Appointment.png" width="190" alt="The next appointment on Home">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/05-Services.png" width="190" alt="Service menu with prices">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/19-Shop.png" width="190" alt="The shop's own products">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/25-Reviews.png" width="190" alt="Reviews from Google Maps">
</p>

These screenshots are taken by the UI tests on every push to `main`. The full set is on the [`screenshots` branch](https://github.com/Brian9761/Barber-App/tree/screenshots). The products and reviews in them are the UI tests' sample data, not the shop's.

## Features

- **Home**: the shop's cuts in a swipeable photo pager with the live open/closed status, "Book an appointment" (no payment needed), the next appointment (or today's walk-in hours when nothing is booked), Directions and Call, popular services, the crew with your favorite barber first, Google's live rating, the shop's products and its Instagram. Pull down to refresh.
- **Book**: five steps, each headed "Step 2 of 5" with a thin bar, and "Start over" in the bar.
  1. A service.
  2. A barber, or **Any barber** when several barbers share the service (the shop's server books whoever is free first). Every barber's own price and length is shown; Flowxbori's 45-minute and hour-long haircuts are separate rows.
  3. A day and time from the shop's live calendar: days with openings are marked on the month, times are grouped into morning, afternoon and evening, in the shop's time zone (with a note when the phone is set to another one).
  4. Name, US mobile number and an optional note for the barber, remembered on the iPhone for next time unless turned off.
  5. A review that says **No payment now — you'll pay at the shop**, then **Book appointment**.

  Then "You're booked", with Add to Calendar, a reminders switch and Done. If someone else takes the time first, the app goes back to the times, refreshed, and says so. Offline, every screen says what happened and offers Try again and Call the shop.
- **Your appointments**: on Home (the next one) and in Book (everything ahead and the last 30 days). The app checks them with the shop when it opens and on pull to refresh, so a cancellation by the shop or a finished appointment shows up. Cancel appointment asks first, then tells the shop. Reminders come the day before and an hour before; cancelled appointments lose theirs. Each card has Add to Calendar and Directions.
- **Services**: the shop's 12 services by category with each one's price range and length, jump chips and search. Each service lists who offers it at what price and books that exact item.
- **Shop**: the shop's own products, added by the owner in Izzy Clipz Business: photo, name, price when the shop lists one, description and "Available at the shop". There's no cart and no checkout. Until the shop adds any: "New products are coming soon. Ask at the shop what's in stock."
- **Team**: a page for each barber with a monogram, their own menu, specialties, Instagram if they have one, and "Book with…". Clients can mark a favorite barber, which then appears on Home.
- **Visit**: the storefront, the address with Directions (Apple Maps or Google Maps), Call and Copy address, the week's hours with today marked, a map, walk-in, payment and accessibility info, the shop's Instagram, and links to the website and reviews.
- **Reviews**: Google's rating, count and up to five reviews in Google's order ("Most relevant on Google"), live, under "Reviews from Google Maps", each with its author and a link to it on Google Maps; Yelp's in a section of its own when the shop's server has them, otherwise "Read our reviews on Yelp". The two are never combined. "Leave a review on Google" opens Google's form.
- **Gallery**: the shop's photos, full screen with swipe, pinch and double-tap zoom.
- **Cut reminders**: an optional "time for a fresh cut" notification every 2–6 weeks after the last cut. Tapping it opens booking.

The tab bar is the system's (Home, Services, Book, Shop, Visit), with no animation between tabs; each tab keeps its screens while another one is showing. The app is dark only and uses the system font with Dynamic Type everywhere, and supports VoiceOver, Reduce Motion and Reduce Transparency.

## Getting started

Requirements: a Mac with **Xcode 16 or later** (Xcode 26 recommended, since the App Store requires its SDK).

1. Open `IzzyClipz.xcodeproj`. If files were added or removed since it was last generated, regenerate it first (see below).
2. Select the **IzzyClipz** target → **Signing & Capabilities**, choose your team, and change the bundle identifier (`com.izzyclipz.app`) to one you own.
3. Set the shop's server in `project.yml` and `IzzyClipz/Info.plist` under `IzzyAPIBaseURL` (keep the two the same). It's `https://izzy-clipz-api.vercel.app` until the server is deployed under its real address. The app only accepts an https address (or http to localhost for a local server: `npm run dev` in `server/`).
4. Pick an iPhone simulator or your device and press **Run** (⌘R).

The project has no third-party dependencies.

## Project layout

```
IzzyClipz/                 The iOS app (SwiftUI)
  App/                     Entry point, the tabs and sheets (RootView), navigation (AppRouter), app data, favorites
  Features/                Home, Booking, Appointments, Services, Team, Shop, Visit, Reviews, Gallery, Reminders
  Components/              Shared views: buttons, cards, rows, loading/empty/error states, Instagram card, Safari sheet, Add to Calendar
  Services/                The server's address, the Keychain helper, and FakeShopAPI (the in-memory server for UI tests)
  Stores/                  Appointments (with their manage tokens), the client's details, products and reviews
  Theme/                   Colors, text roles, navigation bar style, SF Symbol names
  Resources/               Asset catalog (icon, logo, photos, colors), privacy manifest
Packages/IzzyClipzKit/     The shop's data and logic (hours, calendar, menu, reminders) and the client for the server's API, with no UI dependencies
IzzyClipzTests/            App unit tests
IzzyClipzUITests/          End-to-end UI tests that also capture screenshots, and the recorded demo tour
server/                    The shop's server (Vercel and Postgres), with its own README
project.yml                XcodeGen spec the Xcode project is generated from
scripts/generate_assets.py Builds the icon, launch logo, logo cut-outs and photo sets
```

## Updating shop information

The menu, the team and the hours live in one file, `Packages/IzzyClipzKit/Sources/IzzyClipzKit/IzzyClipzData.swift`; the shop's server books against the same data, exported to `server/data/catalog.json`.

- **Prices or lengths**: edit the matching `Offering` line.
- **New service**: add a `Service`, then an `Offering` for each barber who offers it. Each offering needs a menu item ID (any UUID); its ID on the server is `<barber id>/<item id>`, so never change an existing one.
- **New barber**: add a `Barber` with a URL-safe `id` (e.g. `jane-doe`), then their offerings. Their monogram tile shows the first two letters of `name`.
- **Hours**: edit `schedule`, in Pacific time. Times are offered every 30 minutes from opening, as long as the appointment ends by closing, at least 30 minutes ahead and up to 60 days ahead.

Then regenerate the server's copy and deploy the server:

```sh
UPDATE_CATALOG_JSON=1 swift test --package-path Packages/IzzyClipzKit --filter CatalogExportTests
```

A Kit test fails while `server/data/catalog.json` differs from the Kit. Products are managed by the owner in Izzy Clipz Business, not in this file. Reviews come live from Google and Yelp through the server.

## Font

The app uses the system font (SF Pro) with Dynamic Type text styles. Views pick a `TextRole` (`IzzyClipz/Theme/Typography.swift`), which maps to a text style and weight, so text follows the client's text size setting. Strings are written in sentence case and shown as written.

## Testing

```sh
# Shop logic and the API client (runs on macOS or Linux, no simulator needed)
swift test --package-path Packages/IzzyClipzKit

# The app: unit tests and UI tests on a simulator
xcodebuild test -project IzzyClipz.xcodeproj -scheme IzzyClipz \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

GitHub Actions (`.github/workflows/ios.yml`) runs everything on every push to `main`: the package tests on Linux and macOS, plus the app's unit and UI tests on Xcode 26 and Xcode 16 simulators, and a Release device build. Screenshots of every screen are uploaded as a build artifact and published to the `screenshots` branch. You can also start it from the **Actions** tab on any branch: those runs publish to `screenshots-<branch>`, and when Apple silicon Macs are short on capacity you can pick **intel** to use GitHub's Intel Macs instead. The **Demo video** workflow records a walk through the app (`IzzyClipzUITests/DemoTour.swift`) and publishes it to the `demo` branch. The server has its own workflows (see `server/README.md`).

The UI tests run the app with `-ui-testing`: it starts with no favorite, details or appointments, never touches the network (an in-memory stand-in for the server answers instead, with sample products and reviews marked as test data), shows a preview of each web address instead of loading it or leaving the app, and keeps manage tokens in memory. Launch arguments set up each situation:

| Argument | What it does |
| --- | --- |
| `-fakeOffline` | Every request fails as if the phone were offline. |
| `-fakeBookingOffline` | The first booking attempt fails offline; Try again works. |
| `-fakeSlotTaken` | The first booking finds the time just taken. |
| `-fakeNoProducts` | The shop has no products yet. |
| `-fakeReviewsUnavailable` | Google's reviews can't be shown and Yelp isn't set up. |
| `-fakeYelp` | The server also has Yelp reviews. |
| `-fakeBookedAppointment` | Starts with an appointment booked in the app. |
| `-fakeShopCancels` | Appointments the server already holds come back cancelled by the shop. |
| `-fakeSquireAppointment` | Starts with an appointment the previous version saved after booking on Squire. |
| `-fakeSavedDetails` | The client's name and number are already remembered. |

The test suites check, among other things:

- Business hours and the booking calendar: opening and closing minutes, start times that fit before closing, lead time, the booking window, DST changes, and a phone set to another time zone.
- Availability asked for two weeks at a time and kept by the shop's day; every booking failure turned into words and a way forward; slot starts sent back unchanged and numbers sent in E.164.
- Appointments: tokens kept in the Keychain (never in UserDefaults), a token the Keychain refuses kept for the launch and flagged, statuses refreshed from the server, offline and unknown appointments kept rather than dropped, cancelling, reminders, and the previous version's Squire appointments carried over read-only.
- Every booking path in the UI, a taken time, offline errors with Try again, cancelling, a cancellation by the shop, the shop with and without products, and the reviews with and without Google and Yelp.
- The API client against the server's own contract fixtures, and the catalog export against `server/data/catalog.json`.
- That every SF Symbol and image the app uses exists, and that the privacy manifest declares what's sent to the shop.

## Regenerating the Xcode project

`IzzyClipz.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you don't need XcodeGen just to build. If you add or remove files or targets, or change build settings in `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

New Swift files and resources under `IzzyClipz/` are picked up automatically when you regenerate. The `Info.plist` properties in `project.yml` (including `IzzyAPIBaseURL` and the dark `UIUserInterfaceStyle`) overwrite `IzzyClipz/Info.plist`, so change them in `project.yml` and keep the two the same. If you'd rather work only in Xcode, you can stop using `project.yml` and edit the project directly.

To rebuild the icon, logo cut-outs and photos: `python3 scripts/generate_assets.py --help` (needs `pip install Pillow numpy`). `python3 scripts/generate_assets.py --launch-only` rebuilds just the launch screen's logo sticker and the color sets from the catalog's own `Logo.png`, with no source artwork needed.

## Where the data came from

Collected October 16, 28 and 30, 2026 from the shop's website ([izzyclipzbarbershop.net](https://www.izzyclipzbarbershop.net)), its former Squire booking page, and its Google and [Yelp](https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside) listings. Some sources disagree; the app uses:

| | In the app | Also seen |
| --- | --- | --- |
| Phone | (442) 341-3053 (shop website) | (760) 410-2885 on Squire |
| Wednesday hours | 10 AM – 7 PM (Squire) | 11 AM – 6 PM on Yelp |
| Instagram | @izzy_clipz_barbershop_ (the shop); @izzy_clipz_ on Izzy's profile | |

Please confirm these with the shop before publishing.

The logo and photos are the shop's own, from its website; the logo file there has a faint stock-art watermark on the mascot, so ask the shop for a clean copy before publishing. The team has no headshots online, so barbers appear as monograms.

## Publishing to the App Store

1. **Account**: Apple expects business apps to be published by the business, so use the shop's own Apple Developer account or get the owner's written permission to use the name, logo and photos.
2. **Server**: deploy `server/` first and put its address in `IzzyAPIBaseURL` (see `server/README.md`).
3. **App Privacy**: answer **Data Collected**, all **Linked to the user**, **not used for tracking**, for **App Functionality** only:
   - **Contact Info → Name** and **Contact Info → Phone Number**: sent to the shop's server when the client books, so the shop knows who's coming and can reach them.
   - **User Content → Other User Content**: the optional note for the barber.

   The app sends nothing else and has no analytics or ads. The favorite barber, reminder settings, the remembered name and number, and the appointments stay on the iPhone (the manage tokens in the Keychain). The shop's server keeps each appointment with the client's name and number for the shop. The included privacy manifest (`IzzyClipz/Resources/PrivacyInfo.xcprivacy`) declares the same. The privacy policy URL the App Store asks for should say this, and that reviews are shown from Google Maps (whose terms and privacy policy the Reviews screen links) and Yelp.
4. **Review notes**: booking happens in the app on the shop's own server; nothing is paid in the app (clients pay in person at the shop). Products are shown only, not sold in the app. Give App Review a way to book a test appointment the shop will expect (or ask them to cancel what they book).
5. **Screenshots**: the App Store needs full-resolution screenshots; take them in the Simulator (**File → Save Screen**) with the real server, since the test screenshots use sample products and reviews.
6. Archive in Xcode (**Product → Archive**) and upload with the Organizer.
