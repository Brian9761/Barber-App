# Izzy Clipz — iOS App

A native iPhone app for **Izzy Clipz Barbershop**, 1919 Mission Ave, Ste 105, Oceanside, CA.

Built with SwiftUI for iOS 17 and later. No accounts, no tracking, no backend to run: clients plan their visit on the app's booking calendar, then confirm the time on the shop's existing [Squire](https://getsquire.com/discover/barbershop/izzy-clipz-oceanside) page, so the barbers keep managing their calendars exactly as they do today. Bravo products go in a bag in the app and are paid for on Bravo's own checkout.

The look is "Street Drip": a dark ink canvas, bone cards, Archivo display type with Space Mono tags, the shop's logo on a white sticker, and one red action per screen. Switching tabs turns a barber pole across the screen.

<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/01-Home.png" width="190" alt="Home screen">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/12-Book-Calendar.png" width="190" alt="The booking calendar">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/14-Book-Review.png" width="190" alt="Reviewing a booking before confirming on Squire">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/17-Home-Appointment.png" width="190" alt="A saved appointment on Home">
</p>
<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/05-Services.png" width="190" alt="Service menu with prices">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/18-Shop.png" width="190" alt="Bravo products in the Shop tab">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/21-Visit.png" width="190" alt="The storefront, address and Directions">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/24-Reviews.png" width="190" alt="Reviews">
</p>
<p>
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/16-Booking-Saved.png" width="190" alt="BOOKED, after saving an appointment">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/32-Product-Sizes.png" width="190" alt="A Bravo gel's sizes and price">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/28-Shop-Bag.png" width="190" alt="The Bravo bag">
  <img src="https://raw.githubusercontent.com/Brian9761/Barber-App/screenshots/30-Home-Instagram.png" width="190" alt="The shop's Instagram card on Home">
</p>

These screenshots are taken by the UI tests on every push to `main`. The full set is on the [`screenshots` branch](https://github.com/Brian9761/Barber-App/tree/screenshots).

## Features

- **Home**: the shop's cuts in a swipeable photo hero with the live open/closed status, "Book an appointment", your next appointment as a ticket (or today's walk-in hours when nothing is booked), Directions and Call, popular services, the crew with your favorite barber first, reviews, the shop's Instagram and the Bravo shop.
- **Book**: four steps, with a striped progress bar in the navigation bar and an ✕ to start over. Pick a service, a barber (or "first available"), then a day and time on the app's calendar, which only offers days the shop is open and start times that fit before closing. The last step opens Squire inside the app with the barber and service already picked, so the client confirms the real slot. When they come back, the app asks "Did you book it?", saves the appointment and shows BOOKED.
- **Your appointments**: saved appointments show as tickets on Home and in Book, with a reminder the day before and an hour before. Tapping a ticket offers Add to Calendar, directions, calling the shop to change or cancel, and removing it from the phone. After an appointment, the "time for a fresh cut" reminders count from it.
- **Services**: the shop's 12 services by category with each one's price range and length, jump chips for the categories, and search. Each service lists who offers it at what price and books that exact item.
- **Shop and the bag**: Bravo Hair Gel products (Izzy Clipz is a proud Bravo partner): gels, clay, pomade, texture powder and grooming. Add them to the bag with the "+" on each tile or from a product's page, where the blue and white gels come in 4 oz and 16 oz. The bag shows each line with a quantity stepper, the subtotal and how far it is from Bravo's free U.S. shipping at $64. "Checkout on Bravo" opens Bravo's own Shopify checkout with the items already in its cart; payment and shipping happen on bravohairgel.com. When the checkout closes, the app asks "Did you finish checking out?" and empties the bag on "Yes". Prices come with the app and are refreshed from Bravo's store when the app opens.
- **Team**: a page for each barber with a monogram, their own menu, specialties, rating, Instagram if they have one, and a "Book with…" button. Clients can mark a favorite barber, which then appears on Home.
- **Visit**: the storefront, the address with Directions (Apple Maps or Google Maps), Call and Copy address, the week's hours with today marked, a map, walk-in, payment and accessibility info, the shop's Instagram, and links to the website, reviews and Google's review form.
- **Instagram**: the shop's account (@izzy_clipz_barbershop_) has a card on Home, and Visit adds "Message us". Izzy's page links his own account (@izzy_clipz_). They open in the Instagram app if it's installed, Safari otherwise. The app doesn't show Instagram posts.
- **Reviews**: the shop's rating on Squire and Google, quoted client reviews, and "Leave a review on Google".
- **Gallery**: the shop's photos, full screen with swipe, pinch and double-tap zoom.
- **Cut reminders**: an optional "time for a fresh cut" notification every 2–6 weeks after the last cut. Tapping it opens booking.

### Navigation

- **The tab bar** is the app's own floating bar (Home, Services, Book, Shop, Visit) with a raised red Book button in the middle. Every tab keeps its screens and scroll position while another one is showing. Tapping the selected tab again goes back to its first screen, or to the top. A small barber pole stands over the selected tab.
- **The barber pole**: switching tabs sweeps a full-height pole across the screen in 0.46 s. It comes in from the side of the tab you picked, and the new tab is revealed behind it. The new tab takes taps from the start, and a tap during a sweep starts the next one at once. Booking steps and other pushed screens keep the standard iOS push and swipe-back, with a thin pole riding in on the new screen's edge. With Reduce Motion on, tabs cross-fade in 0.2 s and nothing spins. Nothing animates at rest. The design notes are in `IzzyClipz/Components/PoleTabContainer.swift` and `BarberPole.swift`.

The app is dark only. It supports Dynamic Type (layouts rearrange at the largest sizes), VoiceOver, Reduce Motion and Reduce Transparency.

## Getting started

Requirements: a Mac with **Xcode 16 or later** (Xcode 26 recommended, since the App Store requires its SDK).

1. Open `IzzyClipz.xcodeproj`.
2. Select the **IzzyClipz** target → **Signing & Capabilities**, choose your team, and change the bundle identifier (`com.izzyclipz.app`) to one you own.
3. Pick an iPhone simulator or your device and press **Run** (⌘R).

The project has no third-party dependencies.

## Project layout

```
IzzyClipz/                 The iOS app (SwiftUI)
  App/                     Entry point, the tab container and sheets (RootView), navigation (AppRouter), app data, favorites
  Features/                Home, Booking, Appointments, Services, Team, Shop (and the bag), Visit, Reviews, Gallery, Reminders
  Components/              Shared views: the tab bar, the barber pole, buttons, cards, rows, Instagram card, Safari sheet, Add to Calendar
  Stores/                  Saved appointments, Bravo's live prices and the bag
  Theme/                   Colors, type roles and fonts, navigation bar style, SF Symbol names
  Resources/               Asset catalog (icon, logo, photos, Bravo products, colors), fonts and their licenses, privacy manifest
Packages/IzzyClipzKit/     The shop's data and logic (hours, calendar, menu, reminders, Bravo catalog, bag), with no UI dependencies
IzzyClipzTests/            App unit tests
IzzyClipzUITests/          End-to-end UI tests that also capture screenshots, and the recorded demo tour
project.yml                XcodeGen spec the Xcode project is generated from
scripts/generate_assets.py Builds the icon, launch logo, logo cut-outs and Bravo images
scripts/build_fonts.py     Builds the fonts in IzzyClipz/Resources/Fonts
```

## Updating shop information

Everything about the shop (services, prices, barbers, hours, phone, address, Instagram, ratings, reviews) lives in one file:

`Packages/IzzyClipzKit/Sources/IzzyClipzKit/IzzyClipzData.swift`

- **Prices or lengths**: edit the matching `Offering` line.
- **New service**: add a `Service`, then an `Offering` for each barber who offers it. The `squireServiceID` is the `preselect=` value in that service's Squire booking link.
- **New barber**: add a `Barber` whose `id` is their Squire URL slug (the part after `/barber/` in their Squire link), then add their offerings. Their monogram tile shows the first two letters of `name`.
- **Hours**: edit `schedule`. Hours are in Pacific time. The booking calendar offers start times every 30 minutes from opening, as long as the appointment ends by closing, up to 60 days ahead (`BookingCalendar` in `BookingCalendar.swift`).

Bravo's products live in `Packages/IzzyClipzKit/Sources/IzzyClipzKit/BravoData.swift`. Each product's `id` is its Shopify handle (the part after `/products/` on bravohairgel.com), which the app uses for the link, the photo (`Bravo-<id>` in the asset catalog) and live prices. Its `variantID` is the Shopify variant a cart link adds (`https://bravohairgel.com/cart/<variantID>:<quantity>,…`), from `https://bravohairgel.com/products.json`. Sizes of one item (the 4 oz and 16 oz gels) are separate products with the same name and category; the Shop shows them as one tile and the product page offers the sizes. The free-shipping threshold is `freeShippingThreshold` on the sponsor.

Then run the tests (below). `testShopDataIsValid` and the product catalog tests catch broken references, duplicate IDs, missing variant IDs and malformed links; one test checks the bundled variant IDs against a copy of Bravo's feed.

## Fonts

The app's typefaces are static font files in `IzzyClipz/Resources/Fonts`, each next to its license:

| Font | Used for | License |
| --- | --- | --- |
| Archivo (ExtraCondensed Black, Condensed ExtraBold, Expanded Black and ExtraBold, Regular, Medium, SemiBold, Bold) | Titles, prices, the wordmark, buttons, body text | SIL Open Font License 1.1 (`OFL-Archivo.txt`) |
| Space Mono (Regular, Bold) | Tags and numbers | SIL Open Font License 1.1 (`OFL-SpaceMono.txt`) |
| Rubik Wet Paint | The one dripping word a screen may have: FRESH on Home, BOOKED after saving | SIL Open Font License 1.1 (`OFL-RubikWetPaint.txt`) |

None of them has a Reserved Font Name, so the renamed static cuts of Archivo are allowed. Archivo comes from Google Fonts as one variable font; `scripts/build_fonts.py` cuts the eight static styles out of it and copies the other two families (see the script's docstring for where to download them; it needs `pip install fonttools`). Every file is listed under `UIAppFonts` in both `project.yml` and `IzzyClipz/Info.plist`, and in `BrandFont` (`IzzyClipz/Theme/Typography.swift`). Views pick fonts through `TextRole`, never by name, so text scales with Dynamic Type. A unit test checks that every listed file is in the app and loads under its PostScript name.

## Testing

```sh
# Shop logic (runs on macOS or Linux, no simulator needed)
swift test --package-path Packages/IzzyClipzKit

# The app: unit tests and UI tests on a simulator
xcodebuild test -project IzzyClipz.xcodeproj -scheme IzzyClipz \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

GitHub Actions (`.github/workflows/ios.yml`) runs everything on every push to `main`: the package tests on Linux and macOS, plus the app's unit and UI tests on Xcode 26 and Xcode 16 simulators, and a Release device build. Screenshots of every screen are uploaded as a build artifact and published to the `screenshots` branch. You can also start it from the **Actions** tab on any branch: those runs publish to `screenshots-<branch>`, and when Apple silicon Macs are short on capacity you can pick **intel** to use GitHub's Intel Macs instead. The **Demo video** workflow records a walk through the app (`IzzyClipzUITests/DemoTour.swift`) with the live Squire and Bravo pages and publishes it to the `demo` branch.

The UI tests run the app with `-ui-testing`: it starts with no favorite, appointments or bag, uses the bundled Bravo prices, and shows a preview of each web address instead of loading it or leaving the app.

The test suites check, among other things:

- Business hours and the booking calendar: opening and closing minutes, start times that fit before closing, lead time, the booking window, DST changes, and a phone set to another time zone.
- That every booking path lands on the right Squire page with the right barber and service, and that "Did you book it?" saves the appointment and shows it on Home.
- The tab bar: every tab reachable and marked when selected, a second tap going back to the first screen, taps landing during the pole sweep, and the bar sitting on the bottom edge clear of the home indicator.
- The bag: quick add, the stepper, the subtotal and free-shipping meter, the exact cart link Bravo's checkout gets, and "Did you finish checking out?" both ways. Product sizes change the price and what goes in the bag.
- Instagram links on Home, Visit and Izzy's page.
- Appointment reminders, cut reminders, permission handling and rapid setting changes.
- Bravo's catalog, variant IDs, links and live price parsing.
- That every SF Symbol, image and font the app uses exists.

## Regenerating the Xcode project

`IzzyClipz.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you don't need XcodeGen just to build. If you add files or targets, or change build settings in `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

New Swift files and resources under `IzzyClipz/` are picked up automatically when you regenerate. The `Info.plist` properties in `project.yml` (including `UIAppFonts` and the dark `UIUserInterfaceStyle`) overwrite `IzzyClipz/Info.plist`, so change them in `project.yml` and keep the two the same. If you'd rather work only in Xcode, you can stop using `project.yml` and edit the project directly.

To rebuild the icon, logo cut-outs and product photos: `python3 scripts/generate_assets.py --help` (needs `pip install Pillow numpy`). `python3 scripts/generate_assets.py --launch-only` rebuilds just the launch screen's logo sticker and the color sets from the catalog's own `Logo.png`, with no source artwork needed.

## Where the data came from

Collected October 16, 28 and 30, 2026 from the shop's website ([izzyclipzbarbershop.net](https://www.izzyclipzbarbershop.net)), its [Squire booking page](https://getsquire.com/discover/barbershop/izzy-clipz-oceanside), its Google and [Yelp](https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside) listings, and [bravohairgel.com](https://bravohairgel.com) (products, prices and variant IDs from its `products.json`). Some sources disagree; the app uses:

| | In the app | Also seen |
| --- | --- | --- |
| Phone | (442) 341-3053 (shop website) | (760) 410-2885 on Squire |
| Wednesday hours | 10 AM – 7 PM (Squire) | 11 AM – 6 PM on Yelp |
| Instagram | @izzy_clipz_barbershop_ (the shop, linked from Squire); @izzy_clipz_ on Izzy's profile | |
| Booking | Squire | An old Booksy listing now redirects to search |

Please confirm these with the shop before publishing. Squire also offers a few add-ons that only appear once a service is in the cart (such as designs), and those show up there during booking.

The logo and photos are the shop's own, from its website; the logo file there has a faint stock-art watermark on the mascot, so ask the shop for a clean copy before publishing. The team has no headshots online, so barbers appear as monograms. Bravo's product photos and logo are from bravohairgel.com.

## Publishing to the App Store

1. **Account**: Apple expects business apps to be published by the business, so use the shop's own Apple Developer account or get the owner's written permission to use the name, logo and photos. Get Bravo's OK to show their products and logo and to send clients to their checkout.
2. **App Privacy**: answer **Data Not Collected**. The app stores only the favorite barber, reminder settings, saved appointments and the bag, on the device. Bravo's checkout happens on bravohairgel.com, so the app never sees names, addresses or payment details. The included privacy manifest declares this.
3. **Review notes**: mention that booking happens on the shop's Squire page and needs no login to browse, and that Bravo products are physical goods sold and shipped by Bravo: the bag hands its items to Bravo's own web checkout.
4. **Screenshots**: the App Store needs full-resolution screenshots; take them in the Simulator (**File → Save Screen**). The ones on the `screenshots` branch are downsized for the web.
5. Archive in Xcode (**Product → Archive**) and upload with the Organizer.
