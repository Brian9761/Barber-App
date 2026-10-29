# Izzy Clipz — iOS App

A native iPhone app for **Izzy Clipz Barbershop**, 1919 Mission Ave, Ste 105, Oceanside, CA.

Built with SwiftUI for iOS 17 and later, in the shop's red, royal blue and white, with its official logo. No accounts, no tracking, no backend to run: clients plan their visit on the app's booking calendar, then confirm the time on the shop's existing [Squire](https://getsquire.com/discover/barbershop/izzy-clipz-oceanside) page, so the barbers keep managing their calendars exactly as they do today.

<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/01-Home.png" width="190" alt="Home screen">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/12-Book-Calendar.png" width="190" alt="The booking calendar">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/14-Book-Review.png" width="190" alt="Reviewing a booking before confirming on Squire">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/17-Home-Appointment.png" width="190" alt="A saved appointment on Home">
</p>
<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/05-Services.png" width="190" alt="Service menu with prices">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/18-Shop.png" width="190" alt="Bravo products in the Shop tab">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/21-Visit.png" width="190" alt="Map, address and hours">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/24-Reviews.png" width="190" alt="Reviews">
</p>

These screenshots are taken by the UI tests on every push to `main`. The full set is on the [`screenshots` branch](https://github.com/Brian9761/Barber-App/tree/screenshots).

## Features

- **Home**: the shop's logo over a photo of its work, live open/closed status ("Open now · Closes 7 PM"), one-tap booking, call, directions and Instagram, your next appointment, popular services, the Bravo shop, the team, recent cuts and reviews.
- **Book**: four steps. Pick a service, a barber (or "first available"), then a day and time on the app's calendar, which only offers days the shop is open and start times that fit before closing. The last step opens Squire inside the app with the barber and service already picked, so the client confirms the real slot. When they come back, the app asks "Did you book it?" and saves the appointment.
- **Your appointments**: saved appointments show on Home and in Book, with a reminder the day before and an hour before, Add to Calendar, directions, and a way to remove them. After an appointment, the "time for a fresh cut" reminders count from it.
- **Services**: the full menu by category with every barber's price and length, plus search. Each service lists who offers it and books that exact item.
- **Shop**: Bravo Hair Gel products (Izzy Clipz is a proud Bravo partner): gels, clay, pomade, texture powder and grooming. Each product opens its page on bravohairgel.com to buy. Prices come with the app and are refreshed from Bravo's store when the app opens.
- **Team**: a profile for each barber with their own menu, specialties, rating, Instagram and a "Book with…" button. Clients can mark a favorite barber, which then appears on Home.
- **Visit**: a map with Apple Maps or Google Maps directions, a copyable address, weekly hours with today highlighted, walk-in, payment and accessibility info, the storefront, and reviews.
- **Reviews**: the shop's rating on Squire and Google, quoted client reviews, and "Leave a review on Google".
- **Gallery**: the shop's photos, full-screen with swipe, pinch and double-tap zoom.
- **Cut reminders**: an optional "time for a fresh cut" notification every 2–6 weeks after the last cut. Tapping it opens booking.

It supports Dynamic Type and VoiceOver.

## Getting started

Requirements: a Mac with **Xcode 16 or later** (Xcode 26 recommended, since the App Store requires its SDK).

1. Open `IzzyClipz.xcodeproj`.
2. Select the **IzzyClipz** target → **Signing & Capabilities**, choose your team, and change the bundle identifier (`com.izzyclipz.app`) to one you own.
3. Pick an iPhone simulator or your device and press **Run** (⌘R).

The project has no third-party dependencies.

## Project layout

```
IzzyClipz/                 The iOS app (SwiftUI)
  App/                     Entry point, navigation (AppRouter), app data, favorites
  Features/                Home, Booking, Appointments, Services, Team, Shop, Visit, Reviews, Gallery, Reminders
  Components/              Shared views: buttons, cards, rows, logo, Safari sheet, Add to Calendar
  Stores/                  Saved appointments and Bravo's live prices
  Theme/                   Colors, fonts, SF Symbol names
  Resources/               Asset catalog (icon, logo, photos, Bravo products, colors), privacy manifest
Packages/IzzyClipzKit/     The shop's data and logic, with no UI dependencies
IzzyClipzTests/            App unit tests
IzzyClipzUITests/          End-to-end UI tests that also capture screenshots
project.yml                XcodeGen spec the Xcode project is generated from
scripts/generate_assets.py Builds the icon, launch logo, logo cut-outs and Bravo images
```

## Updating shop information

Everything about the shop (services, prices, barbers, hours, phone, address, ratings, reviews) lives in one file:

`Packages/IzzyClipzKit/Sources/IzzyClipzKit/IzzyClipzData.swift`

- **Prices or lengths**: edit the matching `Offering` line.
- **New service**: add a `Service`, then an `Offering` for each barber who offers it. The `squireServiceID` is the `preselect=` value in that service's Squire booking link.
- **New barber**: add a `Barber` whose `id` is their Squire URL slug (the part after `/barber/` in their Squire link), then add their offerings.
- **Hours**: edit `schedule`. Hours are in Pacific time. The booking calendar offers start times every 30 minutes from opening, as long as the appointment ends by closing, up to 60 days ahead (`BookingCalendar` in `BookingCalendar.swift`).

Bravo's products live in `Packages/IzzyClipzKit/Sources/IzzyClipzKit/BravoData.swift`. Each product's `id` is its Shopify handle (the part after `/products/` on bravohairgel.com), which the app uses for the link, the photo (`Bravo-<id>` in the asset catalog) and live prices.

Then run the tests (below). `testShopDataIsValid` and the product catalog tests catch broken references, duplicate IDs and malformed links.

## Testing

```sh
# Shop logic (runs on macOS or Linux, no simulator needed)
swift test --package-path Packages/IzzyClipzKit

# The app: unit tests and UI tests on a simulator
xcodebuild test -project IzzyClipz.xcodeproj -scheme IzzyClipz \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

GitHub Actions (`.github/workflows/ios.yml`) runs everything on every push to `main`: the package tests on Linux and macOS, plus the app's unit and UI tests on Xcode 26 and Xcode 16 simulators, and a Release device build. Screenshots of every screen are uploaded as a build artifact and published to the `screenshots` branch. You can also start it from the **Actions** tab on any branch: those runs publish to `screenshots-<branch>`, and when Apple silicon Macs are short on capacity you can pick **intel** to use GitHub's Intel Macs instead.

The test suites check, among other things:

- Business hours and the booking calendar: opening and closing minutes, start times that fit before closing, lead time, the booking window, DST changes, and a phone set to another time zone.
- That every booking path lands on the right Squire page with the right barber and service, and that "Did you book it?" saves the appointment.
- Appointment reminders, cut reminders, permission handling and rapid setting changes.
- Bravo's catalog, links and live price parsing.
- That every SF Symbol and image the app uses exists.

## Regenerating the Xcode project

`IzzyClipz.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you don't need XcodeGen just to build. If you add targets or change build settings in `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

New Swift files under `IzzyClipz/` are picked up automatically when you regenerate. If you'd rather work only in Xcode, you can stop using `project.yml` and edit the project directly.

To rebuild the icon, logo cut-outs and product photos: `python3 scripts/generate_assets.py --help` (needs `pip install Pillow numpy`).

## Where the data came from

Collected October 16 and 28, 2026 from the shop's website ([izzyclipzbarbershop.net](https://www.izzyclipzbarbershop.net)), its [Squire booking page](https://getsquire.com/discover/barbershop/izzy-clipz-oceanside), its Google and [Yelp](https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside) listings, and [bravohairgel.com](https://bravohairgel.com). Some sources disagree; the app uses:

| | In the app | Also seen |
| --- | --- | --- |
| Phone | (442) 341-3053 (shop website) | (760) 410-2885 on Squire |
| Wednesday hours | 10 AM – 7 PM (Squire) | 11 AM – 6 PM on Yelp |
| Instagram | @izzy_clipz_barbershop_ (the shop, linked from Squire); @izzy_clipz_ on Izzy's profile | |
| Booking | Squire | An old Booksy listing now redirects to search |

Please confirm these with the shop before publishing. Squire also offers a few add-ons that only appear once a service is in the cart (such as designs), and those show up there during booking.

The logo and photos are the shop's own, from its website; the logo file there has a faint stock-art watermark on the mascot, so ask the shop for a clean copy before publishing. The team has no headshots online, so barbers appear as monograms. Bravo's product photos and logo are from bravohairgel.com.

## Publishing to the App Store

1. **Account**: Apple expects business apps to be published by the business, so use the shop's own Apple Developer account or get the owner's written permission to use the name, logo and photos. Get Bravo's OK to show their products and logo.
2. **App Privacy**: answer **Data Not Collected**. The app stores only the favorite barber, reminder settings and saved appointments, on the device. The included privacy manifest declares this.
3. **Review notes**: mention that booking happens on the shop's Squire page and needs no login to browse, and that Bravo products are physical goods bought on Bravo's website.
4. **Screenshots**: the App Store needs full-resolution screenshots; take them in the Simulator (**File → Save Screen**). The ones on the `screenshots` branch are downsized for the web.
5. Archive in Xcode (**Product → Archive**) and upload with the Organizer.
