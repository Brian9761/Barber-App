import SwiftUI

// MARK: - Logo and mascot

/// The shop's official logo (barber-pole mascot and "Izzy Clipz" wordmark), with a transparent
/// background. Its blue letters vanish on ink, so on the dark canvas use `LogoSticker`.
struct LogoImage: View {
    var body: some View {
        Image(Asset.logo)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("\(AppData.shop.name) logo")
    }
}

/// Just the barber-pole mascot from the logo, uncropped. Prefer `MascotSticker`: the cut-out has
/// stray letter fragments along its right edge.
struct MascotImage: View {
    var body: some View {
        Image(Asset.mascot)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// The official logo on a white sticker, slapped on at a slight angle: on the dark canvas the
/// logo always sits on white. Rounded corners, a few points of white around the art and the
/// sticker shadow.
///
///     LogoSticker(width: 120)                       // Visit's hero, bottom-left
///     LogoSticker(width: 72, rotation: .degrees(7)) // the corner of a card
struct LogoSticker: View {
    /// The sticker's width, white border included.
    var width: CGFloat = 120
    var rotation: Angle = .degrees(-6)

    var body: some View {
        let border = max(4, width * 0.045)
        LogoImage()
            .frame(width: width - 2 * border)
            .padding(border)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.sticker * width / 120, style: .continuous))
            .rotationEffect(rotation)
            .shadow(color: .black.opacity(0.55), radius: 9, y: 8)
    }
}

/// The mascot's head in a bone circle with a white ring, tilted like a sticker (46 pt in the Home
/// header, 32 pt in the compact one). Decorative: hidden from VoiceOver.
struct MascotSticker: View {
    var size: CGFloat = 46

    var body: some View {
        Image(Asset.mascot)
            .resizable()
            .scaledToFit()
            // The head crop from the spec: the art at 1.96 × the circle, nudged up and left so the
            // stray letter fragments on the cut-out's right edge stay outside the circle.
            .frame(width: size * 1.96)
            .offset(x: -0.565 * size, y: -0.30 * size)
            .frame(width: size, height: size, alignment: .topLeading)
            .background(Theme.bone)
            .clipShape(Circle())
            .padding(size > 40 ? 2.5 : 2)
            .background(Color.white, in: Circle())
            .rotationEffect(.degrees(-8))
            .shadow(color: .black.opacity(0.55), radius: size > 40 ? 7 : 5, y: size > 40 ? 6 : 4)
            .accessibilityHidden(true)
    }
}

/// "IZZY CLIPZ" in Archivo Expanded Black: "IZZY" in bone and "CLIPZ" in hot red, one of the only
/// two places hot red text is allowed. VoiceOver reads the shop's name.
struct Wordmark: View {
    var isCompact = false

    var body: some View {
        Text("\(Text("Izzy ").foregroundStyle(Theme.bone))\(Text("Clipz").foregroundStyle(Theme.hotRed))")
            .font(.system(isCompact ? .headline : .title3, design: .default, weight: .heavy))
            .lineLimit(1)
            .accessibilityLabel(AppData.shop.name)
    }
}

// MARK: - Monograms

/// A barber's tile. There are no headshots, so each barber gets two letters of their name in
/// Archivo ExtraCondensed Black on a fill picked by their place on the team: bone, blue, ink4,
/// bone, blue, and around again. No red (red is for actions) and no stripes (the stripes belong to
/// the pole). The owner's wide tiles carry an "OWNER" tag. Decorative: the row or card around it
/// says who it is.
///
///     MonogramTile(barber: izzy, size: CGSize(width: 116, height: 66))
///     MonogramTile(barber: carlos, side: 56)
struct MonogramTile: View {
    let barber: Barber
    var size = CGSize(width: 56, height: 56)
    /// `nil` scales the radius with the tile.
    var cornerRadius: CGFloat?

    init(barber: Barber, size: CGSize, cornerRadius: CGFloat? = nil) {
        self.barber = barber
        self.size = size
        self.cornerRadius = cornerRadius
    }

    /// A square tile.
    init(barber: Barber, side: CGFloat, cornerRadius: CGFloat? = nil) {
        self.init(barber: barber, size: CGSize(width: side, height: side), cornerRadius: cornerRadius)
    }

    /// The first two letters of the name clients know: IZ, CA, FL, CR, JU.
    static func letters(for barber: Barber) -> String {
        String(barber.name.prefix(2)).uppercased()
    }

    var body: some View {
        let palette = MonogramPalette(teamIndex: AppData.catalog.barbers.firstIndex(where: { $0.id == barber.id }) ?? 0)
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? min(size.width, size.height) * 0.27, style: .continuous)
        let letterSize = min(size.height * 0.76, size.width * 0.8)
        Text(Self.letters(for: barber))
            .font(.system(size: letterSize * 0.8, weight: .heavy, design: .default))
            .tracking(-0.01 * letterSize)
            .foregroundStyle(palette.letters)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size.width, height: size.height)
            .background(palette.fill, in: shape)
            .overlay(alignment: .topLeading) {
                if barber.isOwner && size.width >= 96 {
                    MonoTag(text: "Owner", style: palette.isLight ? .ink : .bone)
                        .padding(7)
                }
            }
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}

/// The fill and letter colors for a place on the team (art direction §11).
private struct MonogramPalette {
    let fill: AnyShapeStyle
    let letters: Color
    let isLight: Bool

    init(teamIndex: Int) {
        let blueToRoyal = LinearGradient(colors: [Theme.blue, Theme.royal], startPoint: .topLeading, endPoint: .bottomTrailing)
        switch teamIndex % 5 {
        case 0, 3:
            fill = AnyShapeStyle(Theme.bone)
            letters = Theme.ink
            isLight = true
        case 2:
            fill = AnyShapeStyle(Theme.ink4)
            letters = Theme.bone
            isLight = false
        default:
            fill = AnyShapeStyle(blueToRoyal)
            letters = Theme.bone
            isLight = false
        }
    }
}

extension Barber {
    /// Whether their title on Squire says they own the shop.
    var isOwner: Bool {
        title.localizedCaseInsensitiveContains("owner")
    }
}

// MARK: - Open status

/// The shop's open status in one wording everywhere: "OPEN · TIL 7 PM", "CLOSING SOON · TIL 7 PM",
/// "OPENING SOON · 10 AM", "CLOSED · OPENS 10 AM TOMORROW". Computed from the regular hours.
struct ShopStatusLine: Equatable {
    let text: String
    let tone: StatusSummary.Tone
    let accessibilityLabel: String

    init(at date: Date, clock: ShopClock = AppData.clock) {
        let summary = clock.summary(at: date)
        tone = summary.tone
        switch clock.status(at: date) {
        case .open(let closesAt):
            let time = clock.timeLabel(for: closesAt)
            let headline = summary.tone == .changingSoon ? "Closing soon" : "Open"
            text = "\(headline) · til \(time)"
            accessibilityLabel = "\(summary.tone == .changingSoon ? "Closing soon" : "Open now"), until \(time)"
        case .closed(let opensAt?) where summary.tone == .changingSoon:
            let time = clock.timeLabel(for: opensAt)
            text = "Opening soon · \(time)"
            accessibilityLabel = "Opening soon, at \(time)"
        case .closed:
            text = "\(summary.headline) · \(summary.detail)"
            accessibilityLabel = summary.accessibilityLabel
        }
    }
}

/// The open-status pill: a status dot and the status in mono. On the ink canvas it's an `ink3`
/// capsule; over a photo it's frosted ink (solid with Reduce Transparency).
struct StatusPill: View {
    let status: ShopStatusLine
    var isOverPhoto = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.color(for: status.tone))
                .frame(width: 8, height: 8)
                .padding(3)
                .background(Theme.color(for: status.tone).opacity(0.22), in: Circle())
            Text(status.text)
                .textRole(.label)
                .foregroundStyle(Theme.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(minHeight: 30)
        .background {
            if isOverPhoto {
                InkMaterial(shape: Capsule(), tint: 0.9)
            } else {
                Capsule().fill(Theme.ink3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityIdentifier("shopStatus")
    }
}

/// `StatusPill`, kept current every minute.
struct LiveStatusPill: View {
    var isOverPhoto = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            StatusPill(status: ShopStatusLine(at: context.date), isOverPhoto: isOverPhoto)
        }
    }
}
