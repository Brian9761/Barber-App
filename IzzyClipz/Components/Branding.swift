import SwiftUI

/// Diagonal barber-pole stripes: red, white, navy, white.
struct StripeBand: View {
    var stripeWidth: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let colors: [Color] = [Theme.red, .white, Theme.navy, .white]
            let rise = size.height
            var x = -rise
            var index = 0
            while x < size.width + rise {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + rise, y: 0))
                stripe.addLine(to: CGPoint(x: x + rise + stripeWidth, y: 0))
                stripe.addLine(to: CGPoint(x: x + stripeWidth, y: size.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(colors[index % colors.count]))
                x += stripeWidth
                index += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// "IZZY CLIPZ" set in heavy condensed italics over a barber-pole stripe.
struct Wordmark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IZZY CLIPZ")
                .font(.system(size: size, weight: .black).width(.condensed).italic())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
            StripeBand()
                .frame(width: 132, height: 8)
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppData.shop.name)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A monogram with a barber-pole ring. The team has no headshots, so
/// initials stand in rather than stock photos.
struct BarberAvatar: View {
    let barber: Barber
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Theme.navy, Theme.navy.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(barber.initials)
                .font(.system(size: size * 0.36, weight: .heavy).width(.condensed))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().strokeBorder(
                AngularGradient(gradient: Gradient(colors: [Theme.red, .white, Theme.navy, .white, Theme.red]), center: .center),
                lineWidth: max(2, size * 0.05)
            )
        )
        .accessibilityHidden(true)
    }
}

/// Five stars, with halves.
struct RatingStars: View {
    let average: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(forStar: index))
                    .font(.system(size: size, weight: .bold))
            }
        }
        .foregroundStyle(Theme.soon)
        .accessibilityHidden(true)
    }

    private func symbol(forStar index: Int) -> String {
        let remaining = average - Double(index)
        if remaining >= 0.75 { return Symbol.starFilled }
        if remaining >= 0.25 { return Symbol.starHalf }
        return Symbol.starEmpty
    }
}

/// "★★★★★ 5.0 · 92 reviews".
struct RatingLine: View {
    let rating: Rating
    var source: String?

    var body: some View {
        HStack(spacing: 6) {
            RatingStars(average: rating.average)
            Text("\(rating.averageLabel) · \(rating.countLabel)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = "Rated \(rating.averageLabel) out of 5, \(rating.countLabel)"
        guard let source else { return base }
        return "\(base) on \(source)"
    }
}

/// "Open now · Closes 7 PM", kept current every minute.
struct LiveStatusPill: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            StatusPill(summary: AppData.clock.summary(at: context.date))
        }
    }
}

struct StatusPill: View {
    let summary: StatusSummary

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.color(for: summary.tone))
                .frame(width: 8, height: 8)
            Text("\(Text(summary.headline).fontWeight(.semibold).foregroundStyle(.white)) · \(summary.detail)")
                .foregroundStyle(Theme.secondaryText)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityIdentifier("shopStatus")
    }
}

/// A large condensed section title with an optional trailing control.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.display(.title2))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// A rounded tag, e.g. for specialties.
struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// The square icon used for a service.
struct ServiceIcon: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Theme.red, Theme.red.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
