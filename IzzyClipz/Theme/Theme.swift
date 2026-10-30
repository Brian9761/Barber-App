import SwiftUI

/// Street Drip: an ink-black canvas, bone-white type, and one loud red per screen.
///
/// The app is dark only (`.preferredColorScheme(.dark)` on the root and
/// `UIUserInterfaceStyle: Dark` in Info.plist). The palette is the brand, so
/// there is no light theme and no token changes with the color scheme.
///
/// Contrast rules (WCAG 2.x, measured from these exact values):
/// - Text needs 4.5:1. Bold display type at 24 pt or more needs 3:1.
/// - `bone` on `ink` is 16.99, on `ink3` 14.52. `smoke` on ink, ink2 and ink3 is 7.38, 6.84 and 6.31.
/// - `smokeDark` goes on bone only (5.92). On ink it's 2.87, which fails.
/// - Text on `dripRed` is `white` at full opacity (5.24; at 92% it drops to 4.59).
/// - `electric` passes on every ink surface (ink3 4.95), so it's the blue for text and icons on dark.
/// - `line` is 1.46:1 on ink: decoration only, never the only sign of a state.
/// - Text over a photo sits only where `PhotoScrim` is at least 75% ink (its bottom 38%).
///
/// Red budget: the raised Book button is the only red on every screen, and
/// each screen may add exactly one more: its primary action. Selection is
/// never red; selected chips, days and segments are `bone` with `ink` text.
enum Theme {
    // MARK: Ink: the canvas, darkest to lightest

    /// The app background, and primary text on bone.
    static let ink = Color(hex: 0x0B0B0C)
    /// Raised surfaces: sheets, the calendar card.
    static let ink2 = Color(hex: 0x151517)
    /// Cards, tiles, chips and icon buttons on the canvas.
    static let ink3 = Color(hex: 0x1D1D20)
    /// Inactive progress segments, icon tiles inside ink3 cards, monogram fills.
    static let ink4 = Color(hex: 0x27272B)
    /// 1 pt borders on ink cards and chips. Decoration only (1.46:1).
    static let line = Color(hex: 0x2E2E33)

    // MARK: Bone: the type and the light surfaces

    /// Primary text on ink, and light surfaces: tickets, review cards, product tiles, the tab bar.
    static let bone = Color(hex: 0xF2EEE5)
    /// Pressed state of a bone surface.
    static let bone2 = Color(hex: 0xE4DFD3)
    /// Disabled text and controls on ink, e.g. past calendar days (3.47:1, so they're still findable).
    static let boneDisabled = bone.opacity(0.4)
    /// Secondary text on ink (6.31 or better on every ink surface).
    static let smoke = Color(hex: 0xA39E94)
    /// Secondary text on bone (5.92), and unselected tab icons and labels. Never on ink.
    static let smokeDark = Color(hex: 0x5E5A53)

    // MARK: Red: actions only

    /// The primary-action color: the Book button, each screen's one main button, the Shop's bag badge.
    /// Labels on it are `white` at 100%.
    static let dripRed = Color(hex: 0xD7141C)
    /// Red text on ink, used in exactly two places: the wordmark's "CLIPZ" and the "BOOKED" drip word.
    static let hotRed = Color(hex: 0xFF4545)
    /// Red text on bone (5.97). Kept for the logo's own red; the build rules leave it almost unused.
    static let logoRed = Color(hex: 0xB80000)

    // MARK: Blue

    /// The logo's royal blue: the promo gradient's start, blue text on bone, the pole's blue stripes.
    static let royal = Color(hex: 0x00309A)
    /// The promo gradient's end, and the blue monogram tiles.
    static let blue = Color(hex: 0x1F4FD8)
    /// Blue on ink: the Call tile, toggles, the free-shipping meter, links on dark cards (4.95 on ink3).
    static let electric = Color(hex: 0x5A84FF)

    // MARK: Status

    /// Only the "open now" dot.
    static let go = Color(hex: 0x38E07B)
    /// Warnings: a picked time that has passed, hours that don't fit, notifications off, sold out,
    /// an expired slot. For icons and short labels (11.06 on ink; ink text on it is 11.06 too).
    static let caution = Color(hex: 0xF5B83D)

    // MARK: Layout

    /// The screen's side margin.
    static let gutter: CGFloat = 16

    /// Corner radii, all drawn with `.continuous` corners.
    enum Radius {
        /// The Home hero, big photo bands, the product detail tile.
        static let hero: CGFloat = 26
        /// Cards and promo cards.
        static let card: CGFloat = 22
        /// The main buttons, the ticket, tiles and product tiles.
        static let tile: CGFloat = 18
        /// Service icon tiles and photo thumbnails.
        static let thumbnail: CGFloat = 15
        /// The arrow square inside the main button.
        static let arrowSquare: CGFloat = 13
        /// Chips and time slots.
        static let chip: CGFloat = 12
        /// The white sticker behind the logo.
        static let sticker: CGFloat = 14
    }

    /// The 4 pt grid. Gaps between stacked cards are `cardGap`, padding inside a card `cardPadding`.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 10
        static let l: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let cardGap: CGFloat = 14
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        /// Between the sections of a scrolling screen.
        static let section: CGFloat = 32
    }

    /// The smallest tap target on any control.
    static let minimumTapSize: CGFloat = 44

    // MARK: Gradients

    /// Bravo's promo cards: royal into blue at about 120°. White text on it is 6.63:1 or better.
    static let promoGradient = LinearGradient(
        stops: [
            .init(color: royal, location: 0),
            .init(color: blue, location: 0.64),
            .init(color: Color(hex: 0x3A66F0), location: 1),
        ],
        startPoint: UnitPoint(x: 0.07, y: 0.25),
        endPoint: UnitPoint(x: 0.93, y: 0.75)
    )

    /// The fade above the floating tab bar, so scrolling content dissolves before it reaches the bar.
    static let tabScrim = LinearGradient(
        stops: [
            .init(color: ink.opacity(0), location: 0),
            .init(color: ink.opacity(0.88), location: 0.34),
            .init(color: ink, location: 0.58),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The dot in the open-status pill.
    static func color(for tone: StatusSummary.Tone) -> Color {
        switch tone {
        case .open: return go
        case .changingSoon: return caution
        case .closed: return smoke
        }
    }
}

extension Color {
    /// An sRGB color from a hex literal, e.g. `Color(hex: 0xF2EEE5)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The darkening behind text on a photo: ink at the top for the status bar, clear through the
/// middle, then 84% to 96% ink over the bottom 38%, plus a vignette in the bottom-left corner so
/// the black capes in the photos never fight the headline.
///
/// Put text only in the bottom 38%, where the scrim is at least 75% ink.
struct PhotoScrim: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.ink.opacity(0.55), location: 0),
                    .init(color: Theme.ink.opacity(0), location: 0.24),
                    .init(color: Theme.ink.opacity(0), location: 0.38),
                    .init(color: Theme.ink.opacity(0.84), location: 0.62),
                    .init(color: Theme.ink.opacity(0.96), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                // An ellipse 130% of the width by 62% of the height, centred on the bottom-left corner.
                let size = CGSize(width: proxy.size.width * 2.6, height: proxy.size.height * 1.24)
                EllipticalGradient(
                    stops: [
                        .init(color: Theme.ink.opacity(0.92), location: 0),
                        .init(color: Theme.ink.opacity(0.70), location: 0.45),
                        .init(color: Theme.ink.opacity(0), location: 1),
                    ],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
                .frame(width: size.width, height: size.height)
                .position(x: 0, y: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A frosted ink background for headers and pills that float over content. Tinted at least 90% ink,
/// so hot red and bone text stay readable over a bright photo. With Reduce Transparency on, it's
/// solid `ink2` instead.
struct InkMaterial<S: Shape>: View {
    var shape: S
    /// How much ink tints the blur. Keep it at 0.9 or more behind text.
    var tint: Double = 0.9

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.ink2)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.ink.opacity(tint)))
        }
    }
}

extension View {
    /// A frosted ink background (`InkMaterial`), solid `ink2` with Reduce Transparency.
    func inkMaterialBackground<S: Shape>(_ shape: S, tint: Double = 0.9) -> some View {
        background(InkMaterial(shape: shape, tint: tint))
    }
}

/// Every SF Symbol the app uses, in one place so a test can check they exist.
/// All of them are in SF Symbols 5 (iOS 17).
enum Symbol {
    // Tabs (the selected Home and Shop tabs use the filled variant)
    static let home = "house"
    static let homeSelected = "house.fill"
    static let services = "scissors"
    static let book = "calendar.badge.plus"
    static let shop = "bag"
    static let shopSelected = "bag.fill"
    static let visit = "mappin.and.ellipse"

    // Actions
    static let reminders = "bell"
    static let remindersOn = "bell.fill"
    static let call = "phone.fill"
    static let directions = "location.fill"
    static let instagram = "camera"
    static let message = "paperplane"
    static let website = "safari"
    static let share = "square.and.arrow.up"
    static let copy = "doc.on.doc"
    static let external = "arrow.up.right"
    static let forward = "arrow.right"
    static let close = "xmark"
    static let chevron = "chevron.right"
    static let back = "chevron.left"
    static let more = "ellipsis.circle"
    static let remove = "trash"
    static let edit = "pencil"
    static let writeReview = "square.and.pencil"
    static let cart = "cart"
    static let buy = "bag.fill"
    static let add = "plus"
    static let subtract = "minus"

    // Content
    static let team = "person.3"
    static let starFilled = "star.fill"
    static let starHalf = "star.leadinghalf.filled"
    static let starEmpty = "star"
    static let favorite = "heart"
    static let favoriteFilled = "heart.fill"
    static let included = "checkmark.circle.fill"
    static let clock = "clock"
    static let calendar = "calendar"
    static let calendarAdd = "calendar.badge.plus"
    static let calendarClock = "calendar.badge.clock"
    static let payment = "creditcard"
    static let accessibility = "figure.roll"
    static let walkIn = "figure.walk"
    static let firstAvailable = "person.2.fill"
    static let gallery = "photo.on.rectangle"
    static let quote = "quote.opening"
    static let info = "info.circle"
    static let map = "map"
    static let location = "location.fill"
    static let checkmark = "checkmark"
    static let success = "checkmark.circle.fill"
    static let partner = "checkmark.seal.fill"
    static let shipping = "shippingbox"
    static let reviews = "text.bubble"
    static let morning = "sunrise"
    static let afternoon = "sun.max"
    static let evening = "sunset"
    static let sparkles = "sparkles"
    static let warning = "exclamationmark.triangle.fill"
    static let remindersOff = "bell.slash"

    /// Includes the symbols the shop data refers to.
    static var all: [String] {
        let own = [
            home, homeSelected, services, book, shop, shopSelected, visit,
            reminders, remindersOn, call, directions, instagram, message, website, share, copy, external, forward,
            close, chevron, back, more, remove, edit, writeReview, cart, buy, add, subtract,
            team, starFilled, starHalf, starEmpty, favorite, favoriteFilled, included, clock, calendar, calendarAdd,
            calendarClock, payment, accessibility, walkIn, firstAvailable, gallery, quote, info, map, location,
            checkmark, success, partner, shipping, reviews, morning, afternoon, evening, sparkles, warning, remindersOff,
        ]
        let data = Catalog.izzyClipz.services.map(\.symbol) + ServiceCategory.allCases.map(\.symbol)
        return Array(Set(own + data)).sorted()
    }

    /// The icon for a part of the day on the booking calendar.
    static func symbol(for part: DayPart) -> String {
        switch part {
        case .morning: return morning
        case .afternoon: return afternoon
        case .evening: return evening
        }
    }
}
