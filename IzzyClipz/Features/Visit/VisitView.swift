import MapKit
import SwiftUI
import UIKit

/// The Visit tab: where the shop is, when it's open, what to know before
/// coming in, and what clients say.
struct VisitView: View {
    var body: some View {
        NavigationStack {
            VisitScreen()
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

/// Everything on the Visit tab, top to bottom.
private struct VisitScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(spacing: 14) {
                    VisitMapCard()
                    VisitAddressCard()
                }
                VisitHoursSection()
                VisitInfoSection()
                VisitShopSection()
                VisitReviewsSection()
                VisitLinksSection()
                VisitFooter()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Map and address

/// A map of the block with the shop pinned. Tapping it offers directions.
private struct VisitMapCard: View {
    private let shop = AppData.shop
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: shop.coordinate.latitude, longitude: shop.coordinate.longitude)
    }

    var body: some View {
        DirectionsButton {
            map
                .overlay(alignment: .bottomTrailing) {
                    directionsBadge
                }
                .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Choose Apple Maps or Google Maps")
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
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        // The whole card is one button; the map itself shouldn't take touches.
        .allowsHitTesting(false)
        .frame(height: 220)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line))
        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
    }

    /// Bone, not red: the Directions button under the address is this screen's red.
    private var directionsBadge: some View {
        Label("Directions", systemImage: Symbol.directions)
            .textRole(.buttonSmall)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.bone, in: Capsule())
            .padding(12)
    }
}

/// The address with a copy button, then Directions and Call.
private struct VisitAddressCard: View {
    @State private var copyCount = 0
    @State private var showsCopied = false
    @ScaledMetric(relativeTo: .body) private var scaledIconSize: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let shop = AppData.shop

    /// Grows with the text, but not so much that the address runs out of room.
    /// (At accessibility sizes the pin and the round copy button give way.)
    private var iconSize: CGFloat { min(scaledIconSize, 56) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest text sizes the address gets the card's full
                // width, and copying it becomes a labeled button under it.
                address
                copyButton
            } else {
                HStack(alignment: .top, spacing: 14) {
                    pin
                    address
                    Spacer(minLength: 8)
                    copyButton
                }
            }
            actions
        }
        .card()
    }

    private var pin: some View {
        Image(systemName: Symbol.location)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.electric)
            .frame(width: iconSize, height: iconSize)
            .background(Theme.ink4, in: Circle())
            .accessibilityHidden(true)
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shop.fullName)
                .font(.headline)
                .foregroundStyle(Theme.bone)
            Text(shop.address.streetLine)
                .font(.subheadline)
                .foregroundStyle(Theme.smoke)
            Text(shop.address.cityLine)
                .font(.subheadline)
                .foregroundStyle(Theme.smoke)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var copyButton: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Button(action: copyAddress) {
                    Label(showsCopied ? "Copied" : "Copy Address", systemImage: showsCopied ? Symbol.checkmark : Symbol.copy)
                }
                .buttonStyle(.secondary)
            } else {
                Button(action: copyAddress) {
                    Image(systemName: showsCopied ? Symbol.checkmark : Symbol.copy)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.electric)
                        .frame(width: iconSize, height: iconSize)
                        .background(Theme.ink4, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
            }
        }
        .accessibilityLabel(showsCopied ? "Address copied" : "Copy address")
        .accessibilityIdentifier("copyAddressButton")
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

    /// Side by side, or stacked at large text sizes.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { actionButtons }
            VStack(spacing: 12) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        DirectionsButton {
            Text("Directions")
        }
        .buttonStyle(.primary(trailingSymbol: Symbol.directions))
        .accessibilityIdentifier("visitDirectionsButton")

        CallButton {
            Label("Call", systemImage: Symbol.call)
        }
        .buttonStyle(.secondary)
        .accessibilityIdentifier("visitCallButton")
    }

    private func copyAddress() {
        UIPasteboard.general.string = shop.address.singleLine
        showsCopied = true
        copyCount += 1
        UIAccessibility.post(notification: .announcement, argument: "Address copied")
    }
}

// MARK: - Hours

/// Open-now status and the week's hours, with today picked out.
private struct VisitHoursSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Hours")
            LiveStatusPill()
            // Re-checked every minute so "today" moves on at midnight.
            TimelineView(.everyMinute) { context in
                VisitHoursCard(today: AppData.clock.weekday(of: context.date))
            }
            Text("Hours are in Pacific time and may change on holidays. Walk-ins are welcome any time we're open.")
                .font(.footnote)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VisitHoursCard: View {
    let today: Weekday

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Weekday.mondayFirst) { day in
                VisitHoursRow(
                    day: day,
                    hours: AppData.clock.schedule.hours(on: day),
                    isToday: day == today
                )
            }
        }
        .card(padding: 8)
    }
}

/// "Monday · 10 AM – 7 PM"; today's row is tinted, with a bone "Today" tag.
private struct VisitHoursRow: View {
    let day: Weekday
    let hours: OpeningHours?
    let isToday: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dayLabel
                Spacer(minLength: 12)
                hoursLabel
            }
            VStack(alignment: .leading, spacing: 4) {
                dayLabel
                hoursLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.ink4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("hours-\(day.name.lowercased())")
    }

    private var dayLabel: some View {
        HStack(spacing: 8) {
            Text(day.name)
                .font(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(Theme.bone)
            if isToday {
                todayChip
            }
        }
    }

    private var hoursLabel: some View {
        Text(hours?.label ?? "Closed")
            .font(.body)
            .fontWeight(isToday ? .bold : .regular)
            .foregroundStyle(isToday ? Theme.bone : Theme.smoke)
            .monospacedDigit()
    }

    private var todayChip: some View {
        MonoTag(text: "Today", style: .bone)
    }

    /// "Today, Tuesday: 10 AM to 7 PM". Spelled out, since a dash between
    /// times isn't always read as "to".
    private var accessibilityText: String {
        let spokenHours = hours.map { "\($0.opens.label) to \($0.closes.label)" } ?? "Closed"
        return isToday ? "Today, \(day.name): \(spokenHours)" : "\(day.name): \(spokenHours)"
    }
}

// MARK: - Good to know

private struct VisitInfoSection: View {
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Good to know")
            VStack(alignment: .leading, spacing: 14) {
                VisitInfoRow(symbol: Symbol.walkIn, title: "What to expect", items: shop.highlights)
                Divider()
                VisitInfoRow(symbol: Symbol.payment, title: "Payment", items: shop.paymentMethods)
                Divider()
                VisitInfoRow(symbol: Symbol.accessibility, title: "Accessibility", items: shop.accessibility)
            }
            .card()
        }
    }
}

private struct VisitInfoRow: View {
    let symbol: String
    let title: String
    let items: [String]
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                // The glyph stops growing with the circle, so it stays inside.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(Theme.electric)
                // Capped, so large text keeps the room for the words.
                .frame(width: min(iconSize, 56), height: min(iconSize, 56))
                .background(Theme.ink4, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.bone)
                Text(items.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(items.joined(separator: ", "))")
    }
}

// MARK: - The shop

/// The storefront, so it's easy to spot, and a few words about the shop.
private struct VisitShopSection: View {
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("The Shop")
            VisitStorefrontCard()
            if !shop.about.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(shop.about, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.body)
                            .foregroundStyle(Theme.bone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
            }
        }
    }
}

/// The storefront photo, and what to look for.
private struct VisitStorefrontCard: View {
    private let shop = AppData.shop
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FillImage(name: Asset.storefront)
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The \(shop.name) storefront at \(shop.address.street), with the shop's sign over the windows")
                .accessibilityAddTraits(.isImage)
            VStack(alignment: .leading, spacing: 3) {
                Text("Look for the \(shop.name) sign")
                    .font(.headline)
                    .foregroundStyle(Theme.bone)
                Text("\(shop.address.streetLine), \(shop.address.city)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .background(Theme.ink3)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line))
        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
    }
}

// MARK: - Reviews

/// Ratings on each site, then all reviews and Google's review form.
private struct VisitReviewsSection: View {
    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Reviews")
            RatingSummary(ratings: shop.ratings, onOpen: { sourced in
                if let url = sourced.url {
                    router.openWeb(url)
                }
            })

            NavigationLink(value: VisitRoute.reviews) {
                Label("See all reviews", systemImage: Symbol.reviews)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("visitSeeAllReviews")

            Button {
                router.openOutside(shop.googleReviewURL)
            } label: {
                Label("Leave a review on Google", systemImage: Symbol.writeReview)
            }
            // Not red: Directions is this screen's main action.
            .buttonStyle(.tertiary)
            .accessibilityHint("Opens Google's review form")
            .accessibilityIdentifier("leaveReviewButton")
        }
    }
}

// MARK: - Links

private struct VisitLinksSection: View {
    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Follow along")
            VStack(spacing: 0) {
                instagram
                Divider().padding(.horizontal, 14)
                website
                Divider().padding(.horizontal, 14)
                share
            }
            .card(padding: 4)
        }
    }

    private var instagram: some View {
        Link(destination: shop.instagramURL) {
            VisitLinkRow(symbol: Symbol.instagram, title: "Instagram", detail: "@\(shop.instagramHandle)")
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(shop.name) on Instagram")
        .accessibilityIdentifier("visitInstagramLink")
    }

    private var website: some View {
        Button {
            router.openWeb(shop.websiteURL)
        } label: {
            VisitLinkRow(symbol: Symbol.website, title: "Website", detail: websiteLabel)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(shop.name) website")
        .accessibilityIdentifier("visitWebsiteLink")
    }

    private var share: some View {
        ShareLink(
            item: shop.websiteURL,
            subject: Text(shop.fullName),
            message: Text("\(shop.fullName), \(shop.address.singleLine)")
        ) {
            VisitLinkRow(
                symbol: Symbol.share,
                title: "Share the shop",
                detail: "Send \(shop.name) to a friend",
                trailingSymbol: Symbol.chevron
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Share \(shop.name)")
        .accessibilityIdentifier("visitShareLink")
    }

    /// "izzyclipzbarbershop.net".
    private var websiteLabel: String {
        let host = shop.websiteURL.host() ?? shop.websiteURL.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// An icon, a title over a detail line, and a trailing arrow.
private struct VisitLinkRow: View {
    let symbol: String
    let title: String
    let detail: String
    var trailingSymbol: String = Symbol.external
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                // The glyph stops growing with the circle, so it stays inside.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(Theme.electric)
                // Capped, so large text keeps the room for the words.
                .frame(width: min(iconSize, 56), height: min(iconSize, 56))
                .background(Theme.ink4, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.bone)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: trailingSymbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.electric)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Footer

private struct VisitFooter: View {
    var body: some View {
        VStack(spacing: 10) {
            MascotSticker(size: 44)
            Text("Appointments are confirmed on Squire, the shop's booking system.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Version \(VisitView.appVersion)")
        }
        .font(.footnote)
        .foregroundStyle(Theme.smoke)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
