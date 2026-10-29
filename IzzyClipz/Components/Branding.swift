import SwiftUI

/// Diagonal barber-pole stripes: red, white, blue, white.
struct StripeBand: View {
    var stripeWidth: CGFloat = 9
    var colors: [Color] = [Theme.red, .white, Theme.blue, .white]

    var body: some View {
        Canvas { context, size in
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

/// Faint diagonal stripes for laying over dark brand backgrounds.
struct StripeTexture: View {
    var opacity: Double = 0.07

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 26
            let width: CGFloat = 10
            var x = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                stripe.addLine(to: CGPoint(x: x + size.height + width, y: 0))
                stripe.addLine(to: CGPoint(x: x + width, y: size.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(.white.opacity(opacity)))
                x += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The shop's official logo (barber-pole mascot and "Izzy Clipz" wordmark),
/// with a transparent background.
struct LogoImage: View {
    var body: some View {
        Image(Asset.logo)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("\(AppData.shop.name) logo")
    }
}

/// Just the barber-pole mascot from the logo.
struct MascotImage: View {
    var body: some View {
        Image(Asset.mascot)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// The official logo on a white rounded badge, for placing over photos and
/// brand colors.
struct LogoBadge: View {
    var height: CGFloat = 92

    var body: some View {
        LogoImage()
            .frame(height: height)
            .padding(.horizontal, height * 0.18)
            .padding(.vertical, height * 0.12)
            .background(
                RoundedRectangle(cornerRadius: height * 0.24, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            )
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
                    colors: [Theme.blueBright, Theme.blue, Theme.blueDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(barber.initials)
                .font(.system(size: size * 0.36, weight: .heavy).width(.condensed))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .padding(max(2, size * 0.05))
        .background(
            Circle().fill(
                AngularGradient(
                    gradient: Gradient(colors: [Theme.red, .white, Theme.blue, .white, Theme.red]),
                    center: .center
                )
            )
        )
        .overlay(Circle().strokeBorder(Theme.stroke))
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
        .foregroundStyle(Theme.star)
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
    /// Use on photos and brand colors; off, it suits white cards.
    var onDark = true

    var body: some View {
        TimelineView(.everyMinute) { context in
            StatusPill(summary: AppData.clock.summary(at: context.date), onDark: onDark)
        }
    }
}

struct StatusPill: View {
    let summary: StatusSummary
    var onDark = true

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.color(for: summary.tone))
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.white.opacity(onDark ? 0.9 : 0), lineWidth: 1.5))
            Text("\(Text(summary.headline).fontWeight(.bold).foregroundStyle(onDark ? Color.white : Theme.ink)) · \(summary.detail)")
                .foregroundStyle(onDark ? Color.white.opacity(0.85) : Theme.secondaryText)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(onDark ? Color.black.opacity(0.32) : Theme.surface)
        )
        .overlay(Capsule().strokeBorder(onDark ? Color.white.opacity(0.22) : Theme.stroke))
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
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.red)
                    .frame(width: 4, height: 18)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(.display(.title2))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            trailing
                .font(.subheadline.weight(.semibold))
                .tint(Theme.blue)
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
            .foregroundStyle(Theme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.tint, in: Capsule())
    }
}

/// The rounded square icon used for a service.
struct ServiceIcon: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Theme.blueBright, Theme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// "STEP 3 OF 4" over a big title, for the booking flow.
struct StepHeader: View {
    let step: Int
    let total: Int
    let title: String
    let subtitle: String

    init(step: Int, of total: Int = 4, title: String, subtitle: String) {
        self.step = step
        self.total = total
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...max(total, 1), id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.red : Theme.ink.opacity(0.12))
                        .frame(width: index == step ? 26 : 12, height: 5)
                }
            }
            .accessibilityHidden(true)
            Text("STEP \(step) OF \(total)")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.red)
            Text(title.uppercased())
                .font(.display(.title))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
