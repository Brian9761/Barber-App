import SwiftUI

/// One service: its category and name, its price, length and how many barbers do it, what it is and
/// what's included, then who does it at what price. Each "Book with" row jumps straight to the
/// calendar with that choice; the red "Book this" bar (the screen's one red) goes to picking a
/// barber.
struct ServiceDetailView: View {
    let service: Service

    @Environment(AppRouter.self) private var router
    @Environment(Favorites.self) private var favorites
    /// Whether the title in the content has scrolled up under the navigation bar.
    @State private var titleIsUnderBar = false
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    titles
                        .menuTitleScrolledUnderBar($titleIsUnderBar)
                    ServiceStats(service: service)
                    Text(service.summary)
                        .textRole(.body)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                includes
                bookingOptions
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .menuNavigationTitle(service.name, showsInBar: titleIsUnderBar)
        .screenBackground()
        .stickyBottomBar {
            Button {
                router.startBooking(serviceID: service.id)
            } label: {
                Text("Book this")
            }
            .buttonStyle(.primary)
            .accessibilityLabel("Book \(service.name)")
            .accessibilityHint("Next, pick your barber")
            .accessibilityIdentifier("bookServiceButton")
        }
    }

    // MARK: Title

    private var titles: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if service.id == MenuFeaturedService.id {
                // The tag beside the category, or under it with big text.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        Kicker(service.category.title)
                        featuredTag
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Kicker(service.category.title)
                        featuredTag
                    }
                }
            } else {
                Kicker(service.category.title)
            }
            MenuTitleText(service.name, role: .displayL)
                .foregroundStyle(Theme.bone)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// "THE WORKS", from VIP's own description. VoiceOver already hears it in the summary.
    private var featuredTag: some View {
        MonoTag(text: MenuFeaturedService.tag, style: .bone)
            .accessibilityHidden(true)
    }

    // MARK: What's included

    @ViewBuilder private var includes: some View {
        if !service.includes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("What's included")
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(service.includes, id: \.self) { item in
                        IncludedItem(text: item)
                    }
                }
            }
        }
    }

    // MARK: Book with

    private var bookingOptions: some View {
        let offerings = sortedOfferings
        let option = catalog.firstAvailableOption(forService: service.id)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Book with")
            if let option {
                firstAvailableButton(option)
                Kicker("Or choose your barber")
                    .padding(.top, Theme.Space.xs)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(offerings) { offering in
                if let barber = catalog.barber(withID: offering.barberID) {
                    offeringButton(offering, barber: barber)
                }
            }
            Text("Next, you'll pick a day and time. Squire confirms the real opening.")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xxs)
        }
    }

    private func firstAvailableButton(_ option: FirstAvailableOption) -> some View {
        Button {
            router.startBooking(choice: .firstAvailable(option))
        } label: {
            BookWithRow(name: "First available", isFavorite: false, price: option.priceLabel, duration: option.durationLabel) {
                FirstAvailableMonograms(barberIDs: option.barberIDs)
            } detail: {
                Text("Squire picks whoever's free")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(FirstAvailableRow.accessibilityText(for: option))
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("bookFirstAvailable")
    }

    private func offeringButton(_ offering: Offering, barber: Barber) -> some View {
        let isFavorite = favorites.isFavorite(barber.id)
        return Button {
            router.startBooking(choice: .offering(offering))
        } label: {
            BookWithRow(
                name: barber.name,
                isFavorite: isFavorite,
                price: offering.price.label,
                duration: offering.durationLabel,
                note: offering.note
            ) {
                MonogramTile(barber: barber, side: 56)
            } detail: {
                if let rating = barber.rating {
                    RatingLine(rating: rating)
                } else {
                    // No published rating: their title ("BARBER"), never "0 reviews".
                    Text(barber.title)
                        .textRole(.monoNumber)
                        .foregroundStyle(Theme.smoke)
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(offeringAccessibilityText(offering, barber: barber, isFavorite: isFavorite))
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("book-\(offering.id)")
    }

    /// "Book with Carlos, your barber, rated 5.0 out of 5 from 8 reviews, $45, 45 minutes, …".
    private func offeringAccessibilityText(_ offering: Offering, barber: Barber, isFavorite: Bool) -> String {
        var parts = ["Book with \(barber.name)" + (isFavorite ? ", your barber" : "")]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5 from \(rating.countLabel)")
        }
        parts.append(offering.price.label.spokenRanges)
        parts.append(DurationText.spoken(minutes: offering.durationMinutes))
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    /// The client's favorite barber first, then cheapest first.
    private var sortedOfferings: [Offering] {
        let offerings = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return offerings }
        return offerings.filter { $0.barberID == favorite } + offerings.filter { $0.barberID != favorite }
    }
}

// MARK: - Stats

/// Three mono stat blocks: PRICE $35–$45 · TIME 45 MIN – 1 HR · BARBERS 5, across everyone who
/// offers the service. Side by side up to xLarge text, stacked above it.
private struct ServiceStats: View {
    let service: Service

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let catalog = AppData.catalog

    var body: some View {
        let barbers = catalog.barbers(offering: service.id).count
        layout {
            if !price.isEmpty {
                ServiceStat(label: "Price", value: price, spoken: price.spokenRanges)
            }
            if !duration.isEmpty {
                ServiceStat(label: "Time", value: duration.menuKeepingUnits, spoken: spokenDuration)
            }
            ServiceStat(label: barbers == 1 ? "Barber" : "Barbers", value: "\(barbers)", spoken: "\(barbers)")
        }
        // Side by side, the blocks are as tall as the tallest.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var layout: AnyLayout {
        dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.s))
    }

    private var price: String {
        catalog.priceSummary(forService: service.id)
    }

    private var duration: String {
        catalog.durationSummary(forService: service.id)
    }

    /// "45 minutes to 1 hour".
    private var spokenDuration: String {
        let minutes = catalog.offerings(forService: service.id).map(\.durationMinutes)
        guard let shortest = minutes.min(), let longest = minutes.max() else { return duration }
        if shortest == longest { return DurationText.spoken(minutes: shortest) }
        return "\(DurationText.spoken(minutes: shortest)) to \(DurationText.spoken(minutes: longest))"
    }
}

/// A label in mono over a value in Archivo Condensed on an `ink3` tile. The value wraps between
/// words rather than being cut off ("45 MIN –" over "1 HR" in a narrow block), and a word wider
/// than the block ("INCLUDED", a third of a 375 pt screen) shrinks a little instead of breaking.
private struct ServiceStat: View {
    let label: String
    let value: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label)
                .textRole(.monoTag)
                .foregroundStyle(Theme.smoke)
            MenuTitleText(value, role: .price)
                .textCase(.uppercase)
                .foregroundStyle(Theme.bone)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(spoken)")
    }
}

// MARK: - What's included

/// A line in "What's included" with a 6 pt bone square for a bullet.
private struct IncludedItem: View {
    let text: String

    /// How far above the text's baseline the bullet's centre sits: about half the x-height.
    @ScaledMetric(relativeTo: .body) private var bulletRise: CGFloat = 4.5

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Rectangle()
                .fill(Theme.bone)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height / 2 + bulletRise }
                .accessibilityHidden(true)
            Text(text)
                .textRole(.body)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Book with rows

/// One way to book the service, the same row as booking step 2: a 56 pt tile, the name with a line
/// under it, the price and length on the right and a chevron. When the name and price can't share
/// a line (big text, a long price like "Included with cut"), the price moves under the name. At
/// accessibility text sizes the tile moves above the text so the name keeps the full width. A
/// barber's note runs full width below.
private struct BookWithRow<Leading: View, Detail: View>: View {
    let name: String
    let isFavorite: Bool
    let price: String
    let duration: String
    let note: String?
    let leading: Leading
    let detail: Detail

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        name: String,
        isFavorite: Bool,
        price: String,
        duration: String,
        note: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder detail: () -> Detail
    ) {
        self.name = name
        self.isFavorite = isFavorite
        self.price = price
        self.duration = duration
        self.note = note
        self.leading = leading()
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                mainLayout {
                    leading
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                            nameBlock
                            Spacer(minLength: Theme.Space.l)
                            priceBlock(isStacked: false)
                        }
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            nameBlock
                            priceBlock(isStacked: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MenuChevron()
            }
            if let note {
                Text(note)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var mainLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                Text(name)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if isFavorite {
                    Image(systemName: Symbol.favoriteFilled)
                        .font(.caption)
                        // Grows a little with the text, never enough to squeeze the name.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(Theme.bone)
                        .accessibilityHidden(true)
                }
            }
            detail
        }
    }

    /// Beside the name it stays on one line; under it, a long price wraps.
    private func priceBlock(isStacked: Bool) -> some View {
        VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
            Text(price)
                .textRole(.price)
                .foregroundStyle(Theme.bone)
                .lineLimit(isStacked ? nil : 1)
                .multilineTextAlignment(isStacked ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
            Text(duration)
                .textRole(.monoNumber)
                .foregroundStyle(Theme.smoke)
        }
    }
}

/// The barbers "first available" covers: up to three 32 pt monograms fanned across a 56 pt square,
/// so the row lines up with the barber rows under it.
private struct FirstAvailableMonograms: View {
    let barberIDs: [String]

    private static let side: CGFloat = 32
    private static let box: CGFloat = 56

    var body: some View {
        let barbers = Array(barberIDs.compactMap { AppData.catalog.barber(withID: $0) }.prefix(3))
        // Corner to corner; a single tile sits in the middle.
        let travel = Self.box - Self.side
        let step = barbers.count > 1 ? travel / CGFloat(barbers.count - 1) : 0
        let start = barbers.count > 1 ? 0 : travel / 2
        ZStack(alignment: .topLeading) {
            ForEach(Array(barbers.enumerated()), id: \.element.id) { index, barber in
                let offset = start + CGFloat(index) * step
                MonogramTile(barber: barber, side: Self.side, cornerRadius: 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.ink3, lineWidth: 2)
                    )
                    .offset(x: offset, y: offset)
            }
        }
        .frame(width: Self.box, height: Self.box, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
