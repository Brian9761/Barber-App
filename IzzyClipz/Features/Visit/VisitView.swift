import MapKit
import SwiftUI
import UIKit

/// The Visit tab: where the shop is, when it's open, how to get there and what to know before
/// coming in.
///
/// Top to bottom: the storefront with the logo sticker and the open status, the address card with
/// the screen's one red (Directions), the week's hours on a bone card, the map, good-to-know notes,
/// a few words about the shop, Instagram, links and the footer.
struct VisitView: View {
    /// Popped back to Visit when the Visit tab is tapped again.
    @State private var path = NavigationPath()
    /// Goes up when the tab is tapped again while Visit itself is showing: back to the top.
    @State private var scrollToTop = 0

    var body: some View {
        NavigationStack(path: $path) {
            VisitScreen(scrollToTop: scrollToTop)
                .navigationDestination(for: VisitRoute.self) { route in
                    switch route {
                    case .reviews:
                        ReviewsView()
                            
                            
                    }
                }
        }
    }

    /// "1.0.0 (1)", from the app's Info.plist.
    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Screens pushed from the Visit tab.
private enum VisitRoute: Hashable {
    case reviews
}

/// Words the Visit screen takes from the shop's data.
private enum VisitCopy {
    /// "Walk-ins welcome", if the shop says so.
    static var walkIns: String? {
        AppData.shop.highlights.first { $0.localizedCaseInsensitiveContains("walk-in") }
    }

    /// "Pacific Time", from the shop's time zone.
    static var timeZoneName: String {
        AppData.shop.timeZone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? "Shop time"
    }
}

/// Everything on the Visit tab, top to bottom.
private struct VisitScreen: View {
    let scrollToTop: Int

    @State private var heroIsUnderBar = false
    @State private var isScrolled = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "visitTop"

    var body: some View {
        GeometryReader { proxy in
            // The whole screen's height, bars and home indicator included: the storefront is sized
            // from it so a 375 × 667 iPhone SE still shows the Directions button above the tab bar.
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.section) {
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            VisitHero(
                                height: VisitHero.height(forScreenHeight: screenHeight),
                                showsStatus: !dynamicTypeSize.isAccessibilitySize
                            )
                            .pageScrolledUnderBar($heroIsUnderBar)
                            // At the largest text sizes the status leaves the photo for the canvas,
                            // where it can wrap.
                            if dynamicTypeSize.isAccessibilitySize {
                                VisitStatusStrip()
                            }
                        }
                        .id(Self.topID)

                        VisitAddressCard()
                        VisitHoursSection()
                        VisitMapCard()
                        VisitInfoSection()
                        VisitAboutSection()
                        InstagramCard(variant: .visit)
                        VisitLinksSection()
                        VisitFooter()
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.xxl)
                    .pageScrolled($isScrolled)
                }
                .onChange(of: scrollToTop) {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        scroller.scrollTo(Self.topID, anchor: .top)
                    }
                }
            }
        }
        .coordinateSpace(.named(PageBar.space))
        .screenBackground()
        // The storefront is the header, so "Visit" shows in the bar only once it has scrolled away.
        .pageBar(title: "Visit", showsTitle: heroIsUnderBar, isScrolled: isScrolled)
    }
}

// MARK: - Storefront

/// The storefront photo under the photo scrim, with the logo slapped on the bottom-left as a white
/// sticker (the one place the full logo shows large), the open status at the top and "WALK-INS
/// WELCOME" in the dark bottom-right corner.
private struct VisitHero: View {
    let height: CGFloat
    /// The status pill and the walk-in line on the photo. Off at accessibility text sizes, where
    /// they move under it.
    let showsStatus: Bool

    private let shop = AppData.shop
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)

    /// `min(300, 0.36 × screen height)`: 240 pt on a 667 pt iPhone SE, 300 from 834 pt up.
    static func height(forScreenHeight screenHeight: CGFloat) -> CGFloat {
        min(300, max(200, (screenHeight * 0.36).rounded()))
    }

    var body: some View {
        ZStack {
            FillImage(name: Asset.storefront)
            PhotoScrim()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        // The page's heading for VoiceOver, since the storefront stands in for a title.
        .accessibilityLabel("Visit \(shop.name). The storefront at \(shop.address.street), with the shop's sign over the windows")
        .accessibilityAddTraits([.isImage, .isHeader])
        .overlay(alignment: .topLeading) {
            if showsStatus {
                LiveStatusPill(isOverPhoto: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(Theme.Space.l)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                LogoSticker(width: 120, rotation: .degrees(-6))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if showsStatus, let walkIns = VisitCopy.walkIns {
                    // Only in the bottom of the photo, where the scrim is at least 84% ink.
                    Text(walkIns)
                        .textRole(.label)
                        .foregroundStyle(Theme.bone)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.bottom, 2)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, Theme.Space.xl)
            .padding(.bottom, 18)
        }
    }
}

/// The open status and the walk-in line on the canvas, for accessibility text sizes: a dot and
/// text that wraps instead of a pill that would cut it off.
private struct VisitStatusStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TimelineView(.everyMinute) { context in
                let status = ShopStatusLine(at: context.date)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Circle()
                        .fill(Theme.color(for: status.tone))
                        .frame(width: 10, height: 10)
                    Text(status.text)
                        .textRole(.label)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.accessibilityLabel)
                .accessibilityIdentifier("shopStatus")
            }
            if let walkIns = VisitCopy.walkIns {
                Text(walkIns)
                    .textRole(.label)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Address

/// The address, the red Directions button (the screen's one red), then Call and Copy address.
private struct VisitAddressCard: View {
    @State private var copyCount = 0
    @State private var showsCopied = false
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
            address

            DirectionsButton {
                Text("Directions")
            }
            .buttonStyle(.primary(trailingSymbol: Symbol.directions))
            .accessibilityHint("Choose Apple Maps or Google Maps")
            .accessibilityIdentifier("visitDirectionsButton")

            // Two equal halves with "Copy address", then with just "Copy", then stacked.
            ViewThatFits(in: .horizontal) {
                VisitEqualWidthRow(spacing: Theme.Space.m) {
                    callButton
                    copyButton(isShort: false)
                }
                VisitEqualWidthRow(spacing: Theme.Space.m) {
                    callButton
                    copyButton(isShort: true)
                }
                VStack(spacing: Theme.Space.m) {
                    callButton
                    copyButton(isShort: false)
                }
            }
        }
        .card()
        .sensoryFeedback(.success, trigger: copyCount)
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                showsCopied = false
            } catch {
                // Cancelled by another copy, which restarts the timer.
            }
        }
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Kicker(shop.fullName)
            Text(shop.address.streetLine)
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Text(shop.address.cityLine)
                .textRole(.body)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var callButton: some View {
        CallButton {
            Label("Call", systemImage: Symbol.call)
        }
        .buttonStyle(VisitCardButtonStyle())
        .accessibilityIdentifier("visitCallButton")
    }

    private func copyButton(isShort: Bool) -> some View {
        Button(action: copyAddress) {
            Label(
                showsCopied ? "Copied" : (isShort ? "Copy" : "Copy address"),
                systemImage: showsCopied ? Symbol.checkmark : Symbol.copy
            )
        }
        .buttonStyle(VisitCardButtonStyle())
        .accessibilityLabel(showsCopied ? "Address copied" : "Copy address")
        .accessibilityIdentifier("copyAddressButton")
    }

    private func copyAddress() {
        UIPasteboard.general.string = shop.address.singleLine
        showsCopied = true
        copyCount += 1
        UIAccessibility.post(notification: .announcement, argument: "Address copied")
    }
}

/// Side-by-side columns of equal width. Its ideal width is what the widest child needs in every
/// column, so `ViewThatFits` only picks it when no label would have to wrap.
private struct VisitEqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? (widest * CGFloat(subviews.count) + gaps)
        let column = max(0, (width - gaps) / CGFloat(subviews.count))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let column = max(0, (bounds.width - gaps) / CGFloat(subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: column, height: bounds.height)
            )
        }
    }
}

/// Call and Copy address on the address card: 44 pt, `ink4` with a bone label, so the red
/// Directions above them stays the card's one loud thing.
private struct VisitCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
        return configuration.label
            .textRole(.buttonSmall)
            .foregroundStyle(Theme.bone)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapSize)
            .background(configuration.isPressed ? Theme.line : Theme.ink4, in: shape)
            .contentShape(shape)
    }
}

// MARK: - Hours

/// The week's hours on a bone card, today marked.
private struct VisitHoursSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("Hours")
            // Re-checked every minute so "today" moves on at midnight.
            TimelineView(.everyMinute) { context in
                VisitHoursCard(today: AppData.clock.weekday(of: context.date))
            }
        }
    }
}

private struct VisitHoursCard: View {
    let today: Weekday

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Weekday.mondayFirst) { day in
                VisitHoursRow(
                    day: day,
                    hours: AppData.clock.schedule.hours(on: day),
                    isToday: day == today
                )
                if day != Weekday.mondayFirst.last {
                    Rectangle()
                        .fill(Theme.ink.opacity(0.08))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            Text("\(VisitCopy.timeZoneName). Hours may change on holidays.")
                .textRole(.caption)
                .foregroundStyle(Theme.smokeDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.m)
        }
        .boneCard(padding: Theme.Space.xl)
    }
}

/// "MONDAY   10 AM – 7 PM". Today gets a 4 pt ink bar, bold type and an ink "TODAY" tag, so it
/// stands out by more than color.
private struct VisitHoursRow: View {
    let day: Weekday
    let hours: OpeningHours?
    let isToday: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) {
                dayLabel
                Spacer(minLength: Theme.Space.l)
                hoursLabel
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                dayLabel
                hoursLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .overlay(alignment: .leading) {
            if isToday {
                Capsule()
                    .fill(Theme.ink)
                    .frame(width: 4)
                    .padding(.vertical, Theme.Space.s)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("hours-\(day.name.lowercased())")
    }

    private var dayLabel: some View {
        HStack(spacing: Theme.Space.s) {
            Text(day.name)
                .font(.system(.subheadline, design: .default, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.ink : Theme.smokeDark)
            if isToday {
                MonoTag(text: "Today", style: .ink)
            }
        }
    }

    private var hoursLabel: some View {
        Text(hours?.label ?? "Closed")
            .font(.system(.body, design: .default, weight: isToday ? .bold : .semibold).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Today, Tuesday: 10 AM to 7 PM". Spelled out, since a dash between times isn't always read
    /// as "to".
    private var accessibilityText: String {
        let spokenHours = hours.map { "\($0.opens.label) to \($0.closes.label)" } ?? "Closed"
        return isToday ? "Today, \(day.name): \(spokenHours)" : "\(day.name): \(spokenHours)"
    }
}

// MARK: - Map

/// A flat map of the block with the shop's pin in electric blue (red stays on Directions).
/// Tapping it opens the shop in Apple Maps.
private struct VisitMapCard: View {
    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: shop.coordinate.latitude, longitude: shop.coordinate.longitude)
    }

    var body: some View {
        Button {
            router.openOutside(shop.appleMapsURL)
        } label: {
            map
                .overlay(alignment: .bottomTrailing) {
                    badge
                }
                .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Map of \(shop.address.streetLine), \(shop.address.city)")
        .accessibilityHint("Opens the shop in Apple Maps")
        .accessibilityIdentifier("mapDirections")
    }

    private var map: some View {
        Map(
            initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
            interactionModes: []
        ) {
            Marker(shop.name, systemImage: Symbol.services, coordinate: coordinate)
                .tint(Theme.electric)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // The whole card is one button; the map itself shouldn't take touches.
        .allowsHitTesting(false)
        .frame(height: 180)
        .clipShape(shape)
    }

    private var badge: some View {
        HStack(spacing: 5) {
            Text("Open in Maps")
            Image(systemName: Symbol.external)
                .font(.system(size: 11, weight: .heavy))
        }
        .textRole(.buttonSmall)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.Space.l)
        .frame(minHeight: 32)
        .background(Theme.bone, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(Theme.Space.m)
        .accessibilityHidden(true)
    }
}

// MARK: - Good to know

private struct VisitInfoSection: View {
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("Good to know")
            VStack(alignment: .leading, spacing: 0) {
                VisitInfoRow(symbol: Symbol.walkIn, title: "What to expect", items: shop.highlights)
                VisitDivider()
                VisitInfoRow(symbol: Symbol.payment, title: "Payment", items: shop.paymentMethods)
                VisitDivider()
                VisitInfoRow(symbol: Symbol.accessibility, title: "Accessibility", items: shop.accessibility)
            }
            .card(padding: Theme.Space.xxs)
        }
    }
}

/// A bone symbol on an `ink4` tile, a title and the items from the shop's data.
private struct VisitInfoRow: View {
    let symbol: String
    let title: String
    let items: [String]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            VisitIconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Text(items.joined(separator: " · "))
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(items.joined(separator: ", "))")
    }
}

/// A 44 pt `ink4` tile with a bone symbol, like the service icons. Decorative.
private struct VisitIconTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.bone)
            .frame(width: Theme.minimumTapSize, height: Theme.minimumTapSize)
            .background(Theme.ink4, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A hairline between rows on an ink card. Decoration only.
private struct VisitDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.leading, 66)
            .padding(.trailing, Theme.Space.m)
            .accessibilityHidden(true)
    }
}

// MARK: - About

/// The shop in its own words.
private struct VisitAboutSection: View {
    private let shop = AppData.shop

    var body: some View {
        if !shop.about.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("The shop")
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(shop.about, id: \.self) { paragraph in
                        Text(paragraph)
                            .textRole(.body)
                            .foregroundStyle(Theme.smoke)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Links

/// The website, sharing the shop, the reviews and Google's review form.
private struct VisitLinksSection: View {
    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("More")
            VStack(spacing: 0) {
                website
                VisitDivider()
                share
                VisitDivider()
                reviews
                VisitDivider()
                leaveReview
            }
            .card(padding: Theme.Space.xxs)
        }
    }

    private var website: some View {
        Button {
            router.openWeb(shop.websiteURL)
        } label: {
            VisitLinkRow(symbol: Symbol.website, title: "Website", detail: websiteLabel)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(shop.name) website")
        .accessibilityValue(websiteLabel)
        .accessibilityIdentifier("visitWebsiteLink")
    }

    private var share: some View {
        ShareLink(
            item: shop.websiteURL,
            subject: Text(shop.fullName),
            message: Text("\(shop.fullName), \(shop.address.singleLine)")
        ) {
            // No trailing arrow: it opens the share sheet, not a page.
            VisitLinkRow(
                symbol: Symbol.share,
                title: "Share the shop",
                detail: "Send \(shop.name) to a friend",
                trailingSymbol: nil
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Share \(shop.name)")
        .accessibilityIdentifier("visitShareLink")
    }

    private var reviews: some View {
        NavigationLink(value: VisitRoute.reviews) {
            VisitLinkRow(
                symbol: Symbol.reviews,
                title: "Reviews",
                detail: "On Google and Yelp",
                trailingSymbol: Symbol.chevron
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Reviews")
        .accessibilityIdentifier("visitSeeAllReviews")
    }

    private var leaveReview: some View {
        Button {
            router.openOutside(shop.googleReviewURL)
        } label: {
            VisitLinkRow(symbol: Symbol.writeReview, title: "Leave a review on Google", detail: "Write a few words on Google")
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Leave a review on Google")
        .accessibilityHint("Opens Google's review form")
        .accessibilityIdentifier("leaveReviewButton")
    }

    /// "izzyclipzbarbershop.net".
    private var websiteLabel: String {
        let host = shop.websiteURL.host() ?? shop.websiteURL.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

}

/// An icon tile, a title over a detail line, and a trailing arrow (↗ for web pages, › for the
/// app's own screens).
private struct VisitLinkRow: View {
    let symbol: String
    let title: String
    let detail: String
    var trailingSymbol: String? = Symbol.external

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            VisitIconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Text(detail)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.smoke)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Footer

private struct VisitFooter: View {
    var body: some View {
        VStack(spacing: Theme.Space.m) {
            MascotSticker(size: 40)
            VStack(spacing: Theme.Space.xxs) {
                Text("Book in the app, pay at the shop")
                Text("Version \(VisitView.appVersion)")
            }
            .textRole(.label)
            .foregroundStyle(Theme.smoke)
            .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}
