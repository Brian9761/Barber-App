# Izzy Clipz — iOS App

A native iPhone app for **Izzy Clipz Barbershop**, 1919 Mission Ave, Ste 105, Oceanside, CA.

Built with SwiftUI for iOS 17 and later. No accounts, no tracking, no backend to run: appointments are booked through the shop's existing [Squire](https://getsquire.com/discover/barbershop/izzy-clipz-oceanside) page, so the barbers keep managing their calendars exactly as they do today.

## Features

- **Home**: live open/closed status ("Open now · Closes 7 PM"), one-tap booking, call, directions and Instagram, popular services, the team, recent cuts and reviews.
- **Services**: the full menu by category with every barber's price and length, plus search. Each service lists who offers it and books that exact item.
- **Book**: a three-step flow (service, barber or "first available", review) that opens Squire with the barber and service already selected. Clients just pick a time and confirm.
- **Team**: a profile for each barber with their own menu, specialties, rating, and a "Book with…" button. Clients can mark a favorite barber, which then appears on Home and first in booking.
- **Visit**: a map with Apple Maps or Google Maps directions, a copyable address, weekly hours with today highlighted, walk-in, payment and accessibility info, and the storefront photo.
- **Gallery**: the shop's photos, full-screen with swipe, pinch and double-tap zoom.
- **Cut reminders**: an optional "time for a fresh cut" notification every 2–6 weeks after the last cut. Tapping it opens booking.

It's designed for the shop's brand (barber-pole red, white and navy on a dark background) and supports Dynamic Type and VoiceOver.

## Getting started

Requirements: a Mac with **Xcode 16 or later** (Xcode 26 recommended, since the App Store requires its SDK).

1. Open `IzzyClipz.xcodeproj`.
2. Select the **IzzyClipz** target → **Signing & Capabilities**, choose your team, and change the bundle identifier (`com.izzyclipz.app`) to one you own.
3. Pick an iPhone simulator or your device and press **Run** (⌘R).

The project has no third-party dependencies.

## Project layout

```
IzzyClipz/                 The iOS app (SwiftUI)
  App/                     Entry point, navigation, favorites
  Features/                Home, Services, Booking, Team, Visit, Gallery, Reminders
  Components/              Shared views: buttons, cards, Safari sheet, zoomable image
  Theme/                   Colors, fonts, SF Symbol names
  Resources/               Asset catalog (icon, photos, colors), privacy manifest
Packages/IzzyClipzKit/     The shop's data and logic, with no UI dependencies
IzzyClipzTests/            App unit tests
IzzyClipzUITests/          End-to-end UI tests that also capture screenshots
project.yml                XcodeGen spec the Xcode project is generated from
scripts/generate_assets.py Draws the app icon and launch logo and imports photos
```

## Updating shop information

Everything about the shop (services, prices, barbers, hours, phone, address, reviews) lives in one file:

`Packages/IzzyClipzKit/Sources/IzzyClipzKit/IzzyClipzData.swift`

- **Prices or lengths**: edit the matching `Offering` line.
- **New service**: add a `Service`, then an `Offering` for each barber who offers it. The `squireServiceID` is the `preselect=` value in that service's Squire booking link.
- **New barber**: add a `Barber` whose `id` is their Squire URL slug (the part after `/barber/` in their Squire link), then add their offerings.
- **Hours**: edit `schedule`. Hours are in Pacific time.

Then run the tests (below). `testShopDataIsValid` catches broken references, duplicate IDs and malformed Squire IDs.

## Testing

```sh
# Shop logic (runs on macOS or Linux, no simulator needed)
swift test --package-path Packages/IzzyClipzKit

# The app: unit tests and UI tests on a simulator
xcodebuild test -project IzzyClipz.xcodeproj -scheme IzzyClipz \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

GitHub Actions (`.github/workflows/ios.yml`) runs everything on every push to `main`: the package tests on Linux and macOS, plus the app's unit and UI tests on Xcode 26 and Xcode 16 simulators, and a Release device build. Screenshots of every screen are uploaded as a build artifact.

The test suites check, among other things:

- Business hours, including opening and closing minutes, DST changes, and a phone set to another time zone.
- That every booking path lands on the right Squire page with the right barber and service.
- That every SF Symbol and image the app uses exists.
- Reminder scheduling, permission handling and rapid setting changes.

## Regenerating the Xcode project

`IzzyClipz.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you don't need XcodeGen just to build. If you add targets or change build settings in `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

New Swift files under `IzzyClipz/` are picked up automatically when you regenerate. If you'd rather work only in Xcode, you can stop using `project.yml` and edit the project directly.

To redraw the icon after tweaking colors: `python3 scripts/generate_assets.py` (needs `pip install Pillow`).

## Where the data came from

Collected October 16, 2026 from the shop's website ([izzyclipzbarbershop.net](https://www.izzyclipzbarbershop.net)), its [Squire booking page](https://getsquire.com/discover/barbershop/izzy-clipz-oceanside) and its [Yelp listing](https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside). Some sources disagree; the app uses:

| | In the app | Also seen |
| --- | --- | --- |
| Phone | (442) 341-3053 (shop website) | (760) 410-2885 on Squire |
| Wednesday hours | 10 AM – 7 PM (Squire) | 11 AM – 6 PM on Yelp |
| Booking | Squire | An old Booksy listing now redirects to search |

Please confirm these with the shop before publishing. Squire also offers a few add-ons that only appear once a service is in the cart (such as designs), and those show up there during booking.

Photos are the shop's own, taken from its website. The team has no headshots online, so barbers appear as monograms. The app icon is an original barber-pole design in the shop's colors. You can swap in the shop's official logo by replacing `AppIcon.png` with a 1024 × 1024 PNG without transparency.

## Publishing to the App Store

1. **Account**: Apple expects business apps to be published by the business, so use the shop's own Apple Developer account or get the owner's written permission to use the name and photos.
2. **App Privacy**: answer **Data Not Collected**. The app stores only the favorite barber and reminder settings, on the device. The included privacy manifest declares this.
3. **Review notes**: mention that booking happens on the shop's Squire page and needs no login to browse.
4. **Screenshots**: the CI artifact has every screen at iPhone size.
5. Archive in Xcode (**Product → Archive**) and upload with the Organizer.
